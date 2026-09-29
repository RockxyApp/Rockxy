import AppKit
import Foundation
import SwiftUI

// Editor view-model and message helpers for the Map Local editor window.
// Split out of `MapLocalWindowView.swift` to keep that file within the length limit;
// the two-window `mapLocal` / `mapLocalEditor` flow and all type names are unchanged.

// MARK: - MapLocalFileSource

/// How the editor should persist the Map Local response file on save.
/// Keeps app-owned generated content, captured binary payloads, and user-owned
/// external references distinct so we never rewrite files we do not own.
private enum MapLocalFileSource: Equatable {
    /// App-owned generated file — the editable HTTP message buffer is the source of truth.
    case generated
    /// Captured binary response seeded from a transaction — written byte-for-byte.
    case capturedBinary(Data)
    /// User-owned external file referenced by the rule — never rewritten on save.
    case externalReference
}

// MARK: - MapLocalExternalFileInterpretation

private enum MapLocalExternalFileInterpretation: Equatable {
    case uninspected
    case rawBody
    case fullHTTPMessage(hasBinaryBody: Bool)
    case malformedHTTPMessage
}

// MARK: - MapLocalEditorViewModel

@MainActor @Observable
final class MapLocalEditorViewModel {
    // MARK: Internal

    var name = "Untitled"
    var urlText = ""
    var method: MapLocalHTTPMethod = .any
    var matchType: MapLocalMatchType = .wildcard
    var includeSubpaths = false
    /// Optional exact GraphQL operation name; empty matches every request to the URL.
    var graphQLOperationName = ""
    var delayPreset: MapLocalDelayPreset = .none
    var customDelaySeconds = 15
    var targetMode: MapLocalTargetMode = .localFile
    var localFileEnabled = true
    var localDirectoryEnabled = false
    var filePath = ""
    var directoryPath = ""
    var httpMessageText = MapLocalHTTPMessage.defaultMessage(statusCode: 200)
    var testURLText = ""
    var testMethod: MapLocalHTTPMethod = .get
    private(set) var testResult: MapLocalRuleTestResult?
    var errorMessage: String?

    private(set) var existingID: UUID?
    private(set) var originalRule: ProxyRule?
    private(set) var draft: MapLocalDraft?
    private(set) var isLoaded = false

    /// True when the selected local file is a user-owned external reference that
    /// must never be rewritten when the rule is saved.
    var isExternalReference: Bool {
        fileSource == .externalReference
    }

    var isCapturedBinary: Bool {
        if case .capturedBinary = fileSource {
            return true
        }
        return false
    }

    var isInlineResponseEditable: Bool {
        fileSource == .generated
    }

    var isExternalFullHTTPMessage: Bool {
        if targetMode == .localFile, case .fullHTTPMessage = externalFileInterpretation {
            return true
        }
        return false
    }

    var externalFullMessageHasBinaryBody: Bool {
        if case let .fullHTTPMessage(hasBinaryBody) = externalFileInterpretation {
            return hasBinaryBody
        }
        return false
    }

    var externalFileValidationMessage: String? {
        guard targetMode == .localFile, externalFileInterpretation == .malformedHTTPMessage else {
            return nil
        }
        return String(
            localized: "This file starts like an HTTP response but is malformed. Rockxy will continue to the origin until the file is corrected.",
            bundle: RockxyLocalization.bundle
        )
    }

    var isSelectedFileAvailable: Bool {
        guard !filePath.isEmpty else {
            return false
        }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    var responseContentType: String {
        let configured = MapLocalHTTPMessage.parse(httpMessageText).headers.first {
            $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame
        }?.value
        return configured ?? MimeTypeResolver.mimeType(for: filePath)
    }

    var responseStatusCode: Int {
        MapLocalHTTPMessage.parse(httpMessageText).statusCode
    }

    var responseBodyText: String {
        get {
            MapLocalHTTPMessage.parse(httpMessageText).body
        }
        set {
            let parsed = MapLocalHTTPMessage.parse(httpMessageText)
            httpMessageText = MapLocalHTTPMessage.message(
                statusCode: parsed.statusCode,
                headers: parsed.headers,
                body: newValue
            )
        }
    }

    /// The host whose HTTPS traffic must be intercepted before a Map Local rule can run.
    /// Regex patterns are intentionally excluded because inferring a safe host from an
    /// arbitrary regular expression would be misleading.
    var httpsTargetHost: String? {
        guard matchType == .wildcard else {
            return nil
        }
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty,
              !host.contains("*"), !host.contains("?") else
        {
            return nil
        }
        return host
    }

    var isHTTPSPattern: Bool {
        urlText.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("https://")
    }

    var windowTitle: String {
        "Map Local Editor: \(name.isEmpty ? "Untitled" : name)"
    }

    var selectedPath: String {
        targetMode == .localDirectory ? directoryPath : filePath
    }

    var isDirectoryValid: Bool {
        guard !directoryPath.isEmpty else {
            return false
        }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: directoryPath, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    var isSaveEnabled: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && isTargetValid
            && RegexValidator.compile(urlPatternForSaving()).isSuccess
            && directoryRegexCaptureIsValid
    }

    var urlValidationMessage: String? {
        guard !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        if case let .failure(error) = RegexValidator.compile(urlPatternForSaving()) {
            return error.localizedDescription
        }
        return nil
    }

    var directoryRegexValidationMessage: String? {
        guard targetMode == .localDirectory, matchType == .regex,
              !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              RegexValidator.compile(urlPatternForSaving()).isSuccess,
              !directoryRegexCaptureIsValid else
        {
            return nil
        }
        return String(
            localized: "Regex directory rules need a capture group, such as /assets/(.*), to choose a file inside the directory.",
            bundle: RockxyLocalization.bundle
        )
    }

    var visibleTestResult: MapLocalRuleTestResult? {
        testedConfiguration == currentTestConfiguration ? testResult : nil
    }

    var delayMs: Int {
        if delayPreset == .custom {
            return max(0, customDelaySeconds) * 1_000
        }
        return delayPreset.delayMs
    }

    func load(context: MapLocalEditorContext) {
        resetTransientState()
        existingID = context.existingRule?.id
        originalRule = context.existingRule
        draft = context.draft

        if let rule = context.existingRule {
            load(existingRule: rule)
        } else if let draft = context.draft {
            load(draft: draft)
        } else {
            loadBlank()
        }
        isLoaded = true
    }

    func choosePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = targetMode == .localFile
        panel.canChooseDirectories = targetMode == .localDirectory
        panel.allowsMultipleSelection = false
        panel.message = targetMode == .localDirectory
            ? String(localized: "Select a local directory to serve files from", bundle: RockxyLocalization.bundle)
            : String(localized: "Select a local file to serve for matched requests", bundle: RockxyLocalization.bundle)

        if panel.runModal() == .OK, let url = panel.url {
            if targetMode == .localDirectory {
                directoryPath = url.path(percentEncoded: false)
                localDirectoryEnabled = true
                externalFileInterpretation = .uninspected
            } else {
                selectExternalFile(at: url.path(percentEncoded: false))
            }
        }
    }

    /// Selects a user-owned file without taking ownership of its bytes. Keeping this
    /// transition separate from `NSOpenPanel` also makes stale-preview behavior testable.
    func selectExternalFile(at path: String) {
        let actionMessage = externalActionMessageForNextSelection()
        filePath = path
        localFileEnabled = true
        fileSource = .externalReference
        externalActionMessageText = actionMessage
        // Restore the rule-owned metadata before inspecting the new file. Otherwise a
        // malformed/raw file selected after a full-response file would retain that old
        // file's authoritative preview and could persist stale status/headers.
        httpMessageText = actionMessage
        let parsed = MapLocalHTTPMessage.parse(actionMessage)
        loadExternalFilePreview(
            path: path,
            actionStatusCode: parsed.statusCode,
            responseHeaders: parsed.headers
        )
    }

    func setResponseStatusCode(_ statusCode: Int) {
        let normalizedStatus = min(max(statusCode, 100), 599)
        let parsed = MapLocalHTTPMessage.parse(httpMessageText)
        httpMessageText = MapLocalHTTPMessage.message(
            statusCode: normalizedStatus,
            headers: parsed.headers,
            body: parsed.body
        )
    }

    func testRule() {
        testedConfiguration = currentTestConfiguration
        let candidate = testURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil else
        {
            testResult = .invalidURL
            return
        }

        let condition = RuleMatchCondition(
            urlPattern: urlPatternForSaving(),
            sourceURLPattern: urlText.trimmingCharacters(in: .whitespacesAndNewlines),
            method: method.ruleValue,
            matchType: matchType == .regex ? .regex : .wildcard,
            includeSubpaths: matchType == .wildcard ? includeSubpaths : false
        )
        // The tester checks URL and method only; the operation filter is shown beside it.
        let runtimePattern = condition.runtimeURLPattern ?? urlPatternForSaving()
        switch RegexValidator.compile(runtimePattern) {
        case let .failure(error):
            testResult = .invalidPattern(error.localizedDescription)
        case let .success(regex):
            testResult = condition.matches(
                method: testMethod.rawValue,
                url: url,
                headers: [],
                compiledPattern: regex
            ) ? .matched : .notMatched
        }
    }

    func showSelectedPathInFinder() {
        let path = selectedPath
        guard !path.isEmpty else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openSelectedPath(with app: MapLocalExternalEditor) {
        let path = selectedPath
        guard !path.isEmpty else {
            return
        }
        let url = URL(fileURLWithPath: path)
        if let bundleID = app.bundleIdentifier,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: .init()) { _, _ in }
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func makeRule() -> ProxyRule? {
        guard isSaveEnabled else {
            errorMessage = String(
                localized: "Complete the matching rule and local target before saving.",
                bundle: RockxyLocalization.bundle
            )
            return nil
        }

        do {
            if targetMode == .localFile {
                try saveLocalFileIfNeeded()
            }
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }

        var condition = originalRule?.matchCondition ?? RuleMatchCondition()
        condition.urlPattern = urlPatternForSaving()
        condition.method = method.ruleValue
        // Retain the authored pattern + match semantics so reopening the rule does
        // not have to guess (and rewrite) advanced regex from the compiled pattern.
        condition.sourceURLPattern = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        condition.matchType = matchType == .regex ? .regex : .wildcard
        condition.includeSubpaths = matchType == .wildcard ? includeSubpaths : false
        let operationName = graphQLOperationName.trimmingCharacters(in: .whitespacesAndNewlines)
        condition.graphQLOperationName = operationName.isEmpty ? nil : operationName

        let parsedResponse = MapLocalHTTPMessage.parse(actionResponseMessageForSaving)

        return ProxyRule(
            id: existingID ?? UUID(),
            name: name,
            isEnabled: originalRule?.isEnabled ?? true,
            matchCondition: condition,
            action: .mapLocal(
                filePath: targetMode == .localDirectory ? directoryPath : filePath,
                statusCode: parsedResponse.statusCode,
                isDirectory: targetMode == .localDirectory,
                delayMs: delayMs,
                responseHeaders: parsedResponse.headers
            ),
            priority: originalRule?.priority ?? 0
        )
    }

    /// After a brand-new rule's save fails to persist, the optimistically-added rule
    /// already lives in `RuleEngine` under `rule.id`. Adopting that identity flips the
    /// next Save from add-new to update-existing semantics so a retry updates the same
    /// rule instead of appending a duplicate under a fresh UUID. The editor stays open
    /// with the failure visible; no engine rollback is performed, so a concurrent
    /// mutation cannot be erased.
    func adoptFailedAddIdentity(_ rule: ProxyRule) {
        existingID = rule.id
        originalRule = rule
    }

    func urlPatternForSaving() -> String {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard matchType == .wildcard else {
            return trimmed
        }
        return RulePatternBuilder.regexSource(
            rawPattern: trimmed,
            matchType: .wildcard,
            includeSubpaths: includeSubpaths
        )
    }

    // MARK: Private

    private struct RuleTestConfiguration: Equatable {
        let authoredPattern: String
        let method: MapLocalHTTPMethod
        let matchType: MapLocalMatchType
        let includeSubpaths: Bool
        let testURL: String
        let testMethod: MapLocalHTTPMethod
    }

    /// Root directory Rockxy owns for generated Map Local response files.
    private static var mapLocalDirectoryRoot: URL {
        RockxyIdentity.current
            .appSupportDirectory()
            .appendingPathComponent("map-local", isDirectory: true)
    }

    private var fileSource: MapLocalFileSource = .generated
    private var externalFileInterpretation: MapLocalExternalFileInterpretation = .uninspected
    /// Rule-owned fallback status/headers kept separate from a full HTTP file's read-only
    /// authoritative preview. This is what Rockxy persists for the action if the file later
    /// becomes a raw body.
    private var externalActionMessageText: String?
    private var testedConfiguration: RuleTestConfiguration?

    private var actionResponseMessageForSaving: String {
        if isExternalFullHTTPMessage, let externalActionMessageText {
            return externalActionMessageText
        }
        return httpMessageText
    }

    private var currentTestConfiguration: RuleTestConfiguration {
        RuleTestConfiguration(
            authoredPattern: urlText,
            method: method,
            matchType: matchType,
            includeSubpaths: includeSubpaths,
            testURL: testURLText,
            testMethod: testMethod
        )
    }

    private var directoryRegexCaptureIsValid: Bool {
        guard targetMode == .localDirectory, matchType == .regex else {
            return true
        }
        guard case let .success(regex) = RegexValidator.compile(urlPatternForSaving()) else {
            return false
        }
        return regex.numberOfCaptureGroups > 0
    }

    private var isTargetValid: Bool {
        switch targetMode {
        case .localFile:
            !filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .localDirectory:
            isDirectoryValid
        }
    }

    private static func defaultMapLocalFilePath() -> String {
        generatedMapLocalFilePath(fileExtension: nil)
    }

    /// Builds an app-owned generated file path using the inferred extension so
    /// binary responses land in a correctly-typed file instead of always `.json`.
    private static func generatedMapLocalFilePath(fileExtension: String?) -> String {
        let ext = sanitizedExtension(fileExtension) ?? "json"
        return mapLocalDirectoryRoot
            .appendingPathComponent("default_message_\(UUID().uuidString.prefix(8)).\(ext)")
            .path
    }

    private static func sanitizedExtension(_ candidate: String?) -> String? {
        guard let trimmed = candidate?.trimmingCharacters(in: .whitespaces).lowercased(), !trimmed.isEmpty else {
            return nil
        }
        let allowed = CharacterSet.alphanumerics
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        return trimmed
    }

    /// Returns true only when `path` resolves inside Rockxy's app-owned Map Local
    /// directory. Paths are standardized and symlink-resolved before the containment
    /// check to avoid naive string-prefix false positives.
    private static func isAppOwnedPath(_ path: String) -> Bool {
        guard !path.isEmpty else {
            return false
        }
        let root = mapLocalDirectoryRoot.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        if candidate.path == root.path {
            return true
        }
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return candidate.path.hasPrefix(rootPrefix)
    }

    private func loadBlank() {
        name = "Untitled"
        urlText = ""
        method = .any
        matchType = .wildcard
        includeSubpaths = false
        graphQLOperationName = ""
        delayPreset = .none
        customDelaySeconds = 15
        targetMode = .localFile
        localFileEnabled = true
        localDirectoryEnabled = false
        filePath = Self.defaultMapLocalFilePath()
        directoryPath = ""
        httpMessageText = MapLocalHTTPMessage.defaultMessage(statusCode: 200)
        fileSource = .generated
        externalFileInterpretation = .uninspected
        externalActionMessageText = nil
    }

    private func load(draft: MapLocalDraft) {
        loadBlank()
        name = draft.suggestedName.isEmpty ? "Untitled" : draft.suggestedName
        method = MapLocalHTTPMethod(ruleMethod: draft.sourceMethod)
        matchType = .wildcard
        includeSubpaths = draft.origin == .domainQuickCreate
        graphQLOperationName = draft.graphQLOperationName ?? ""
        if let sourceURL = draft.sourceURL {
            urlText = sourceURL.absoluteString
        } else {
            urlText = "https://\(draft.sourceHost)/*"
        }
        // A transaction quick-create should be immediately testable against that
        // transaction. Never retain the tester URL or result from a previous editor.
        testURLText = urlText
        testMethod = method == .any ? .get : method

        // Seed an app-owned generated file using the inferred extension.
        filePath = Self.generatedMapLocalFilePath(fileExtension: draft.inferredExtension)

        let status = draft.responseStatusCode ?? 200
        let responseHeaders = draft.responseHeaders.isEmpty
            ? [
                HTTPHeader(
                    name: "Content-Type",
                    value: draft.responseContentType ?? MimeTypeResolver.mimeType(for: filePath)
                ),
            ]
            : draft.responseHeaders
        guard let body = draft.responseBody, !body.isEmpty else {
            if draft.responseStatusCode != nil {
                // No body but a captured status — reflect it in the template.
                httpMessageText = MapLocalHTTPMessage.message(
                    statusCode: status,
                    headers: responseHeaders,
                    body: "{\n  \"status\": \"ok\"\n}"
                )
            }
            fileSource = .generated
            return
        }

        if let bodyText = String(data: body, encoding: .utf8) {
            httpMessageText = MapLocalHTTPMessage.message(
                statusCode: status,
                headers: responseHeaders,
                body: bodyText
            )
            fileSource = .generated
        } else {
            // Binary payload — keep the raw bytes for byte-identical persistence and
            // show a header-only preview (never a fallback JSON/empty-UTF-8 conversion).
            httpMessageText = MapLocalHTTPMessage.message(
                statusCode: status,
                headers: responseHeaders,
                body: ""
            )
            fileSource = .capturedBinary(body)
        }
    }

    private func load(existingRule rule: ProxyRule) {
        externalFileInterpretation = .uninspected
        name = rule.name.isEmpty ? "Untitled" : rule.name
        loadURLMetadata(from: rule.matchCondition)
        method = MapLocalHTTPMethod(ruleMethod: rule.matchCondition.method)
        graphQLOperationName = rule.matchCondition.requiredGraphQLOperationName ?? ""
        if case let .mapLocal(path, statusCode, isDirectory, delayMs, responseHeaders) = rule.action {
            targetMode = isDirectory ? .localDirectory : .localFile
            filePath = isDirectory ? "" : path
            directoryPath = isDirectory ? path : ""
            localFileEnabled = !isDirectory
            localDirectoryEnabled = isDirectory
            delayPreset = MapLocalDelayPreset.from(delayMs: delayMs)
            if delayPreset == .custom {
                customDelaySeconds = max(0, delayMs / 1_000)
            }
            if isDirectory {
                let headers = responseHeaders.isEmpty
                    ? [HTTPHeader(name: "Content-Type", value: "application/octet-stream")]
                    : responseHeaders
                httpMessageText = MapLocalHTTPMessage.message(
                    statusCode: statusCode,
                    headers: headers,
                    body: ""
                )
                fileSource = .externalReference
                externalFileInterpretation = .uninspected
                externalActionMessageText = nil
            } else {
                loadExistingFile(path: path, statusCode: statusCode, responseHeaders: responseHeaders)
            }
        }
    }

    private func resetTransientState() {
        testURLText = ""
        testMethod = .get
        testResult = nil
        testedConfiguration = nil
        errorMessage = nil
    }

    private func loadExistingFile(path: String, statusCode: Int, responseHeaders: [HTTPHeader]) {
        let headers = responseHeaders.isEmpty
            ? [HTTPHeader(name: "Content-Type", value: MimeTypeResolver.mimeType(for: path))]
            : responseHeaders
        guard Self.isAppOwnedPath(path) else {
            // External references are inspected through the same bounded runtime resolver
            // for an accurate preview, but are never rewritten.
            httpMessageText = MapLocalHTTPMessage.message(
                statusCode: statusCode,
                headers: headers,
                body: ""
            )
            fileSource = .externalReference
            externalActionMessageText = httpMessageText
            loadExternalFilePreview(
                path: path,
                actionStatusCode: statusCode,
                responseHeaders: headers
            )
            return
        }

        if let data = MapLocalFileValidator.loadFileData(at: path) {
            if let body = String(data: data, encoding: .utf8) {
                httpMessageText = MapLocalHTTPMessage.message(
                    statusCode: statusCode,
                    headers: headers,
                    body: body
                )
                fileSource = .generated
                externalActionMessageText = nil
            } else {
                httpMessageText = MapLocalHTTPMessage.message(
                    statusCode: statusCode,
                    headers: headers,
                    body: ""
                )
                fileSource = .capturedBinary(data)
                externalActionMessageText = nil
            }
            return
        }

        let fileExists = FileManager.default.fileExists(atPath: path)
        httpMessageText = MapLocalHTTPMessage.message(
            statusCode: statusCode,
            headers: headers,
            body: ""
        )
        // A missing app-owned target may be recreated. Existing data that failed
        // validation stays read-only so Save cannot destroy an oversized or unsafe file.
        fileSource = fileExists ? .externalReference : .generated
        externalFileInterpretation = .uninspected
        externalActionMessageText = fileExists ? httpMessageText : nil
    }

    private func externalActionMessageForNextSelection() -> String {
        if isExternalFullHTTPMessage, let externalActionMessageText {
            return externalActionMessageText
        }
        return httpMessageText
    }

    private func loadExternalFilePreview(
        path: String,
        actionStatusCode: Int,
        responseHeaders: [HTTPHeader]
    ) {
        externalFileInterpretation = .uninspected
        guard let data = MapLocalFileValidator.loadFileData(at: path) else {
            return
        }

        let looksLikeHTTPMessage = data.starts(with: Data("HTTP/".utf8))
        let outcome = MapLocalResponseResolver.resolve(
            fileData: data,
            actionStatusCode: actionStatusCode,
            configuredHeaders: responseHeaders,
            inferredContentType: MimeTypeResolver.mimeType(for: path)
        )
        switch outcome {
        case .fallbackToOrigin:
            externalFileInterpretation = looksLikeHTTPMessage ? .malformedHTTPMessage : .rawBody
        case let .serve(payload) where looksLikeHTTPMessage:
            let bodyText = String(data: payload.body, encoding: .utf8)
            httpMessageText = MapLocalHTTPMessage.message(
                statusCode: payload.statusCode,
                headers: payload.headers,
                body: bodyText ?? ""
            )
            externalFileInterpretation = .fullHTTPMessage(hasBinaryBody: bodyText == nil && !payload.body.isEmpty)
        case .serve:
            externalFileInterpretation = .rawBody
        }
    }

    /// Restores the editor's URL fields, preferring authored metadata when present
    /// and falling back to the legacy heuristic for rules saved before metadata existed.
    private func loadURLMetadata(from condition: RuleMatchCondition) {
        if let authored = condition.sourceURLPattern, let storedMatchType = condition.matchType {
            urlText = authored
            matchType = storedMatchType == .regex ? .regex : .wildcard
            includeSubpaths = condition.includeSubpaths ?? false
            return
        }

        let storedPattern = condition.urlPattern ?? ""
        if MapLocalPatternFormatter.prefersWildcardPresentation(storedPattern) {
            urlText = MapLocalPatternFormatter.readablePattern(storedPattern)
            matchType = .wildcard
        } else {
            urlText = storedPattern
            matchType = .regex
        }
        includeSubpaths = false
    }

    private func saveLocalFileIfNeeded() throws {
        switch fileSource {
        case .externalReference:
            // Referenced user-owned file — leave its bytes untouched.
            return
        case let .capturedBinary(data):
            try writeData(data)
        case .generated:
            let parsed = MapLocalHTTPMessage.parse(httpMessageText)
            try writeData(Data(parsed.body.utf8))
        }
    }

    private func writeData(_ data: Data) throws {
        let url = URL(fileURLWithPath: filePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}

private extension Result where Success == NSRegularExpression, Failure == RegexValidator.ValidationError {
    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
}

// MARK: - MapLocalHTTPMessage

enum MapLocalHTTPMessage {
    struct ParsedResponse: Equatable {
        let statusCode: Int
        let headers: [HTTPHeader]
        let body: String
    }

    static func defaultMessage(statusCode: Int) -> String {
        message(
            statusCode: statusCode,
            contentType: "application/json; charset=utf-8",
            body: "{\n  \"status\": \"ok\"\n}"
        )
    }

    static func message(statusCode: Int, contentType: String, body: String) -> String {
        message(
            statusCode: statusCode,
            headers: [HTTPHeader(name: "Content-Type", value: contentType)],
            body: body
        )
    }

    static func message(statusCode: Int, headers: [HTTPHeader], body: String) -> String {
        let status = HTTPResponseStatusLookup.reasonPhrase(for: statusCode)
            ?? HTTPReasonPhrase.standard(for: statusCode)
        let headerText = headers
            .map { "\($0.name): \($0.value)" }
            .joined(separator: "\n")
        let separator = headerText.isEmpty ? "" : "\n"
        return "HTTP/1.1 \(statusCode) \(status)\n\(headerText)\(separator)\n\(body)"
    }

    static func parse(_ text: String) -> ParsedResponse {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let headerBlock: Substring
        let body: String
        if let range = normalized.range(of: "\n\n") {
            headerBlock = normalized[..<range.lowerBound]
            body = String(normalized[range.upperBound...])
        } else {
            headerBlock = Substring(normalized)
            body = ""
        }
        let lines = headerBlock.split(separator: "\n", omittingEmptySubsequences: false)
        let statusCode = lines.first
            .flatMap { line in
                line.split(separator: " ").dropFirst().first.flatMap { Int($0) }
            } ?? 200

        let headers = lines.dropFirst().compactMap { line -> HTTPHeader? in
            guard let separator = line.firstIndex(of: ":") else {
                return nil
            }
            let name = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                return nil
            }
            return HTTPHeader(name: name, value: value)
        }
        return ParsedResponse(statusCode: min(max(statusCode, 100), 599), headers: headers, body: body)
    }
}
