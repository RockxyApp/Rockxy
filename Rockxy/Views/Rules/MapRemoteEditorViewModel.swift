import Foundation
import SwiftUI
#if canImport(Darwin)
import Darwin
#endif

// Editor view-model for the Map Remote editor window.
// Split out of `MapRemoteWindowView.swift` to keep that file within the length
// limit; the two-window `mapRemote` / `mapRemoteEditor` flow is unchanged.

// MARK: - MapRemoteEditorViewModel

@MainActor @Observable
final class MapRemoteEditorViewModel {
    // MARK: Internal

    var name = "Untitled"
    var urlText = ""
    var method: MapLocalHTTPMethod = .any
    var matchType: MapLocalMatchType = .wildcard
    var includeSubpaths = true
    /// Optional exact GraphQL operation name; empty matches every request to the URL.
    var graphQLOperationName = ""
    var destScheme = ""
    var destHost = ""
    var destPort = ""
    var destPath = ""
    var destQuery = ""
    /// Explicit full-URL field. Applying it fills the component fields; it is never
    /// parsed implicitly while the user types into another field.
    var destinationURLPaste = ""
    var preserveHost = false
    var preserveOriginalURL = false
    var errorMessage: String?
    var urlParseError: String?
    var urlFillConfirmation: String?
    private(set) var isSaving = false

    private(set) var existingID: UUID?
    private(set) var originalRule: ProxyRule?
    private(set) var draft: MapRemoteDraft?
    private(set) var isLoaded = false

    var windowTitle: String {
        "Map Remote Editor: \(name.isEmpty ? "Untitled" : name)"
    }

    var isSaveEnabled: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hasAnyDestination
            && isPortValid
            && isSchemeValid
            && isHostValid
            && RegexValidator.compile(urlPatternForSaving()).isSuccess
    }

    var hasAnyDestination: Bool {
        !destScheme.isEmpty
            || !trimmedHost.isEmpty
            || !destPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !normalizedPath().isEmpty
            || !destQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var trimmedHost: String {
        destHost.trimmingCharacters(in: .whitespacesAndNewlines)
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

    var portValidationMessage: String? {
        let trimmed = destPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isPortValid else {
            return nil
        }
        return String(localized: "Port must be a number from 1 to 65535.", bundle: RockxyLocalization.bundle)
    }

    var hostValidationMessage: String? {
        guard !trimmedHost.isEmpty, !isHostValid else {
            return nil
        }
        return String(
            localized: "Enter a host only. Put the port in the Port field.",
            bundle: RockxyLocalization.bundle
        )
    }

    var schemeValidationMessage: String? {
        guard !destScheme.isEmpty, !isSchemeValid else {
            return nil
        }
        return String(localized: "Map Remote supports HTTP and HTTPS destinations.", bundle: RockxyLocalization.bundle)
    }

    var destinationValidationMessage: String? {
        guard !hasAnyDestination else {
            return nil
        }
        return String(localized: "Add at least one destination override.", bundle: RockxyLocalization.bundle)
    }

    /// A truthful description of the resulting destination. When a draft source URL is
    /// available it renders the concrete merged URL; otherwise it lists the configured
    /// overrides and notes that unset components are inherited from the request.
    var destinationSummary: String {
        let summary: String = if let source = draft?.sourceURL {
            mergedDestination(onto: source)
        } else {
            overrideDescription()
        }
        guard preserveOriginalURL else {
            return summary
        }
        return "\(summary) The forwarded request keeps its original path and query."
    }

    func load(context: MapRemoteEditorContext) {
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

    /// Fills the destination component fields from a full URL. Every component is
    /// replaced atomically, so a URL missing a component clears the stale value.
    /// Returns false and surfaces `urlParseError` when the input is not a full URL.
    @discardableResult
    func applyDestinationURL(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            urlParseError = String(
                localized: "Enter a URL to fill the destination fields.",
                bundle: RockxyLocalization.bundle
            )
            urlFillConfirmation = nil
            return false
        }
        guard trimmed.contains("://"),
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              Self.supportedSchemes.contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.fragment == nil else
        {
            urlParseError = String(
                localized: "Enter a full HTTP or HTTPS URL without credentials or a fragment.",
                bundle: RockxyLocalization.bundle
            )
            urlFillConfirmation = nil
            return false
        }

        destScheme = scheme
        destHost = host
        destPort = components.port.map(String.init) ?? ""
        if components.percentEncodedPath.isEmpty || components.percentEncodedPath == "/" {
            destPath = "/"
        } else {
            destPath = String(components.percentEncodedPath.drop(while: { $0 == "/" }))
        }
        destQuery = components.percentEncodedQuery ?? ""
        urlParseError = nil
        urlFillConfirmation = String(localized: "Destination fields filled.", bundle: RockxyLocalization.bundle)
        return true
    }

    @discardableResult
    func save(using gate: RulePolicyGate = .shared) async -> Bool {
        guard !isSaving, let rule = makeRule() else {
            return false
        }

        isSaving = true
        defer { isSaving = false }

        if existingID == nil {
            let accepted = await gate.addRule(rule)
            guard accepted else {
                errorMessage = String(
                    localized: "The active Map Remote rule limit was reached. Disable another rule and try again.",
                    bundle: RockxyLocalization.bundle
                )
                return false
            }
        } else {
            await gate.updateRule(rule)
        }

        errorMessage = nil
        return true
    }

    func makeRule() -> ProxyRule? {
        guard isSaveEnabled else {
            errorMessage = String(
                localized: "Complete the matching rule and destination before saving.",
                bundle: RockxyLocalization.bundle
            )
            return nil
        }

        let condition = matchCondition()

        let config = MapRemoteConfiguration(
            scheme: destScheme.isEmpty ? nil : destScheme.lowercased(),
            host: nilIfBlank(normalizedHost),
            port: parsedPort,
            path: nilIfBlank(normalizedPath()),
            query: nilIfBlank(destQuery),
            preserveOriginalURL: preserveOriginalURL,
            preserveHostHeader: preserveHost
        )

        return ProxyRule(
            id: existingID ?? UUID(),
            name: name,
            isEnabled: originalRule?.isEnabled ?? true,
            matchCondition: condition,
            action: .mapRemote(configuration: config),
            priority: originalRule?.priority ?? 0
        )
    }

    /// The match condition the current fields describe; also used by the rule tester.
    func matchCondition() -> RuleMatchCondition {
        var condition = originalRule?.matchCondition ?? RuleMatchCondition()
        condition.urlPattern = urlPatternForSaving()
        condition.method = method.ruleValue
        // Retain the authored pattern + match semantics so reopening the rule does
        // not have to guess (and rewrite) the compiled pattern from a heuristic.
        condition.sourceURLPattern = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        condition.matchType = matchType == .regex ? .regex : .wildcard
        condition.includeSubpaths = matchType == .wildcard ? includeSubpaths : false
        let operationName = graphQLOperationName.trimmingCharacters(in: .whitespacesAndNewlines)
        condition.graphQLOperationName = operationName.isEmpty ? nil : operationName
        return condition
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

    func mergedDestination(onto source: URL) -> String {
        guard var components = URLComponents(url: source, resolvingAgainstBaseURL: false) else {
            return source.absoluteString
        }
        if !destScheme.isEmpty {
            components.scheme = destScheme.lowercased()
            if parsedPort == nil {
                components.port = nil
            }
        }
        if !trimmedHost.isEmpty {
            components.host = hostForURLComponents
        }
        if let port = parsedPort {
            components.port = port
        }
        let path = normalizedPath()
        if !path.isEmpty, !preserveOriginalURL {
            components.percentEncodedPath = percentEncodedPathForPreview(path)
        }
        let query = destQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        components.fragment = nil
        if !query.isEmpty, !preserveOriginalURL {
            components.percentEncodedQuery = nil
            guard let baseURL = components.string else {
                return source.absoluteString
            }
            return "\(baseURL)?\(percentEncodedQueryForPreview(query))"
        }
        return components.string ?? source.absoluteString
    }

    // MARK: Private

    private static let supportedSchemes: Set<String> = ["http", "https"]

    private var parsedPort: Int? {
        Int(destPort.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var isPortValid: Bool {
        let trimmed = destPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return true
        }
        guard let port = Int(trimmed) else {
            return false
        }
        return (1 ... 65_535).contains(port)
    }

    private var isSchemeValid: Bool {
        destScheme.isEmpty || Self.supportedSchemes.contains(destScheme.lowercased())
    }

    private var isHostValid: Bool {
        guard !trimmedHost.isEmpty else {
            return true
        }
        guard trimmedHost.count <= 253,
              !trimmedHost.contains("://"),
              !trimmedHost.contains("/"),
              !trimmedHost.contains("\\"),
              !trimmedHost.contains("@"),
              !trimmedHost.contains("?"),
              !trimmedHost.contains("#"),
              !trimmedHost.contains("%") else
        {
            return false
        }

        let unbracketedHost: String
        if trimmedHost.hasPrefix("[") || trimmedHost.hasSuffix("]") {
            guard trimmedHost.hasPrefix("["), trimmedHost.hasSuffix("]") else {
                return false
            }
            unbracketedHost = String(trimmedHost.dropFirst().dropLast())
        } else {
            unbracketedHost = trimmedHost
        }
        if unbracketedHost.contains(":") {
            return Self.isIPv6Address(unbracketedHost)
        }
        guard !unbracketedHost.contains("["),
              !unbracketedHost.contains("]"),
              !unbracketedHost.contains(":"),
              Self.hasValidHostnameLabels(unbracketedHost) else
        {
            return false
        }
        return true
    }

    private var normalizedHost: String {
        guard trimmedHost.hasPrefix("["), trimmedHost.hasSuffix("]") else {
            return trimmedHost
        }
        return String(trimmedHost.dropFirst().dropLast())
    }

    private var hostForURLComponents: String {
        normalizedHost.contains(":") ? "[\(normalizedHost)]" : normalizedHost
    }

    private static func isIPv6Address(_ host: String) -> Bool {
        #if canImport(Darwin)
        var address = in6_addr()
        return host.withCString { inet_pton(AF_INET6, $0, &address) } == 1
        #else
        return false
        #endif
    }

    private static func hasValidHostnameLabels(_ host: String) -> Bool {
        let normalized = host.hasSuffix(".") ? String(host.dropLast()) : host
        guard !normalized.isEmpty else {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return normalized.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            guard !label.isEmpty,
                  label.count <= 63,
                  label.first != "-",
                  label.last != "-" else
            {
                return false
            }
            return label.unicodeScalars.allSatisfy { allowed.contains($0) }
        }
    }

    private func overrideDescription() -> String {
        var parts: [String] = []
        if !destScheme.isEmpty {
            parts.append("scheme → \(destScheme.lowercased())")
        }
        if !trimmedHost.isEmpty {
            parts.append("host → \(trimmedHost)")
        }
        if let port = parsedPort {
            parts.append("port → \(port)")
        }
        let path = normalizedPath()
        if !path.isEmpty, !preserveOriginalURL {
            parts.append("path → \(path)")
        }
        let query = destQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty, !preserveOriginalURL {
            parts.append("query → \(query)")
        }
        if preserveOriginalURL {
            parts.append("request target → original")
        }
        guard !parts.isEmpty else {
            return String(
                localized: "Add at least one destination override before saving.",
                bundle: RockxyLocalization.bundle
            )
        }
        let overrides = parts.joined(separator: ", ")
        return String(
            localized: "Overrides \(overrides). Other components are kept from the request.",
            bundle: RockxyLocalization.bundle
        )
    }

    private func percentEncodedQueryForPreview(_ query: String) -> String {
        if let components = URLComponents(string: "https://rockxy.invalid/?\(query)"),
           let encoded = components.percentEncodedQuery
        {
            return encoded
        }
        return query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
    }

    private func percentEncodedPathForPreview(_ path: String) -> String {
        if let components = URLComponents(string: "https://rockxy.invalid\(path)") {
            return components.percentEncodedPath
        }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "%")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }

    private func loadBlank() {
        name = "Untitled"
        urlText = ""
        method = .any
        matchType = .wildcard
        includeSubpaths = true
        graphQLOperationName = ""
        destScheme = ""
        destHost = ""
        destPort = ""
        destPath = ""
        destQuery = ""
        destinationURLPaste = ""
        preserveOriginalURL = false
        preserveHost = false
        urlParseError = nil
        urlFillConfirmation = nil
        errorMessage = nil
    }

    private func load(draft: MapRemoteDraft) {
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
    }

    private func load(existingRule rule: ProxyRule) {
        name = rule.name.isEmpty ? "Untitled" : rule.name
        loadURLMetadata(from: rule.matchCondition)
        method = MapLocalHTTPMethod(ruleMethod: rule.matchCondition.method)
        graphQLOperationName = rule.matchCondition.requiredGraphQLOperationName ?? ""
        destScheme = ""
        destHost = ""
        destPort = ""
        destPath = ""
        destQuery = ""
        preserveOriginalURL = false
        preserveHost = false
        destinationURLPaste = ""
        urlParseError = nil
        urlFillConfirmation = nil
        errorMessage = nil
        if case let .mapRemote(config) = rule.action {
            destScheme = config.scheme ?? ""
            destHost = config.host.map {
                $0.hasPrefix("[") && $0.hasSuffix("]")
                    ? String($0.dropFirst().dropLast())
                    : $0
            } ?? ""
            destPort = config.port.map(String.init) ?? ""
            destPath = config.path.map {
                $0 == "/" ? "/" : String($0.drop(while: { $0 == "/" }))
            } ?? ""
            destQuery = config.query ?? ""
            preserveOriginalURL = config.preserveOriginalURL
            preserveHost = config.preserveHostHeader
        }
    }

    /// Restores the editor's URL fields, preferring authored metadata when present.
    /// Legacy rules have only a runtime regex, so they remain regexes rather than being
    /// heuristically reinterpreted and potentially changed on save.
    private func loadURLMetadata(from condition: RuleMatchCondition) {
        if let authored = condition.sourceURLPattern, let storedMatchType = condition.matchType {
            urlText = authored
            matchType = storedMatchType == .regex ? .regex : .wildcard
            includeSubpaths = condition.includeSubpaths ?? false
            return
        }

        let stored = condition.urlPattern ?? ""
        matchType = .regex
        includeSubpaths = false
        urlText = stored
    }

    private func normalizedPath() -> String {
        let trimmed = destPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }
        return trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
    }

    private func nilIfBlank(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
