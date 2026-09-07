import Foundation
import os

// Resolves request URLs to files inside a Map Local directory mapping.

// MARK: - MapLocalError

/// Errors that can occur when resolving a file from a Map Local directory mapping.
enum MapLocalError: Error, CustomStringConvertible {
    case directoryNotFound
    case fileNotFound(path: String)
    case pathTraversal
    case fileTooLarge
    case readError(Error)

    // MARK: Internal

    var description: String {
        switch self {
        case .directoryNotFound:
            "Map local directory does not exist"
        case let .fileNotFound(path):
            "File not found: \(path)"
        case .pathTraversal:
            "Path traversal attempt blocked"
        case .fileTooLarge:
            "File exceeds maximum size limit"
        case let .readError(error):
            "Failed to read file: \(error.localizedDescription)"
        }
    }
}

// MARK: - MapLocalDirectoryResolver

/// Resolves incoming request paths against a local directory for Map Local directory rules.
/// Extracts the subpath from the request URL (relative to the matched pattern prefix),
/// maps it to a file inside the directory root, and returns the file data with MIME type.
enum MapLocalDirectoryResolver {
    // MARK: Internal

    struct ResolvedFile {
        let url: URL
        let data: Data
        let mimeType: String
    }

    /// Resolves a request path to a local file inside the mapped directory.
    ///
    /// - Parameters:
    ///   - requestPath: The full path from the incoming HTTP request (e.g. `/static/js/app.js`).
    ///   - urlPattern: The URL pattern from the rule match condition (e.g. `https://cdn.example.com/static/.*`).
    ///   - directoryPath: The local directory root to serve files from.
    /// - Returns: A `ResolvedFile` on success, or a `MapLocalError` on failure.
    static func resolve(
        requestPath: String,
        urlPattern: String,
        directoryPath: String
    )
        -> Result<ResolvedFile, MapLocalError>
    {
        let subpath = extractSubpath(requestPath: requestPath, urlPattern: urlPattern)
        return serve(subpath: subpath, directoryPath: directoryPath)
    }

    /// Resolves a request to a local file using the authored match context the editor
    /// persisted. Wildcard rules map the suffix after the authored prefix; regex rules
    /// use the first capture group when one is present.
    /// Query and fragment are stripped before any filesystem access.
    ///
    /// - Returns: A `ResolvedFile` on success, or a `MapLocalError` on failure so the
    ///   caller can fall back to the original upstream request.
    static func resolve(
        requestURL: String,
        matchContext: MapLocalMatchContext,
        directoryPath: String
    )
        -> Result<ResolvedFile, MapLocalError>
    {
        guard let subpath = extractSubpath(matchContext: matchContext, requestURL: requestURL) else {
            return .failure(.fileNotFound(path: requestURL))
        }
        return serve(subpath: subpath, directoryPath: directoryPath)
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "MapLocalDirectoryResolver"
    )

    /// Maximum file size: 10 MB (same as MapLocalFileValidator).
    private static let maxFileSize: UInt64 = 10 * 1_024 * 1_024

    /// Serves the file addressed by `subpath` inside `directoryPath`, enforcing directory
    /// existence, traversal containment, symlink containment, and the size limit.
    private static func serve(
        subpath: String,
        directoryPath: String
    )
        -> Result<ResolvedFile, MapLocalError>
    {
        let expanded = (directoryPath as NSString).expandingTildeInPath
        let dirURL = URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else {
            logger.warning("SECURITY: Map local directory does not exist: \(dirURL.path)")
            return .failure(.directoryNotFound)
        }

        let targetURL = resolveTargetURL(dirURL: dirURL, subpath: subpath)

        let resolved = targetURL.resolvingSymlinksInPath()
        let resolvedDir = dirURL.resolvingSymlinksInPath()

        let rootPath = resolvedDir.path.hasSuffix("/") ? resolvedDir.path : resolvedDir.path + "/"
        guard resolved.path == resolvedDir.path || resolved.path.hasPrefix(rootPath) else {
            logger.warning("SECURITY: Path traversal attempt blocked: \(resolved.path) outside \(resolvedDir.path)")
            return .failure(.pathTraversal)
        }

        if !fm.fileExists(atPath: resolved.path) {
            logger.info("Map local file not found: \(resolved.path)")
            return .failure(.fileNotFound(path: subpath))
        }

        var isDirTarget: ObjCBool = false
        if fm.fileExists(atPath: resolved.path, isDirectory: &isDirTarget), isDirTarget.boolValue {
            // A directory target (including the mapped root reached by an empty suffix) never
            // synthesizes an index file — the handler forwards the origin request instead.
            logger.info("Map local target is a directory, no index synthesis: \(resolved.path)")
            return .failure(.fileNotFound(path: subpath))
        }

        return loadFile(at: resolved, dirRoot: resolvedDir)
    }

    /// Extracts the subpath by stripping the URL pattern prefix from the request path.
    /// For a pattern like `https://cdn.example.com/static/.*` and request path `/static/js/app.js`,
    /// returns `js/app.js`.
    private static func extractSubpath(requestPath: String, urlPattern: String) -> String {
        let patternPath = extractPathFromPattern(urlPattern)

        let cleanPattern = patternPath
            .replacingOccurrences(of: ".*", with: "")
            .replacingOccurrences(of: "\\.*", with: "")

        let trimmedPattern = cleanPattern.hasSuffix("/")
            ? String(cleanPattern.dropLast())
            : cleanPattern

        var requestPathOnly = requestPath
        if let components = URLComponents(string: requestPath) {
            requestPathOnly = components.path.isEmpty ? "/" : components.path
        }

        if !trimmedPattern.isEmpty, requestPathOnly.hasPrefix(trimmedPattern) {
            var sub = String(requestPathOnly.dropFirst(trimmedPattern.count))
            if sub.hasPrefix("/") {
                sub = String(sub.dropFirst())
            }
            return sub
        }

        if requestPathOnly.hasPrefix("/") {
            return String(requestPathOnly.dropFirst())
        }
        return requestPathOnly
    }

    /// Extracts just the path portion from a URL pattern string.
    private static func extractPathFromPattern(_ pattern: String) -> String {
        if let components = URLComponents(string: pattern.replacingOccurrences(of: ".*", with: "")) {
            return components.path
        }
        if let slashRange = pattern.range(of: "//") {
            let afterScheme = pattern[slashRange.upperBound...]
            if let pathStart = afterScheme.firstIndex(of: "/") {
                return String(afterScheme[pathStart...])
            }
        }
        return pattern
    }

    /// Extracts the subpath using the authored match context. Returns `nil` only when a
    /// regex rule fails to compile or does not match — the caller treats that as a resolver
    /// failure and falls back to the origin request.
    private static func extractSubpath(matchContext: MapLocalMatchContext, requestURL: String) -> String? {
        let requestPath = pathOnly(from: requestURL)

        if matchContext.matchType == .regex,
           let authored = matchContext.authoredPattern,
           !authored.isEmpty
        {
            return regexCaptureSubpath(pattern: authored, requestURL: requestURL)
        }

        // Wildcard (or unspecified legacy) rules strip the authored prefix from the path.
        let authored = matchContext.authoredPattern
            ?? matchContext.compiledURLPattern
            ?? ""
        let prefix = wildcardPrefixPath(from: authored)
        return stripPrefix(prefix, from: requestPath)
    }

    /// Returns the percent-decoded path component of a request URL (or raw path), with any
    /// query or fragment removed so they can never enter a filesystem path.
    private static func pathOnly(from requestURL: String) -> String {
        if let components = URLComponents(string: requestURL) {
            return components.path.isEmpty ? "/" : components.path
        }
        let stripped = requestURL.prefix { $0 != "?" && $0 != "#" }
        return String(stripped)
    }

    /// Applies a regex rule to the request URL and returns the first capture group as the
    /// subpath. A capture group is required: a regex that
    /// matches but declares no capture group (or an empty one) fails so the handler falls back
    /// to the origin rather than reinterpreting the whole request path as a docroot-relative
    /// path. Query/fragment are always stripped.
    private static func regexCaptureSubpath(
        pattern: String,
        requestURL: String
    )
        -> String?
    {
        guard case let .success(regex) = RegexValidator.compile(pattern) else {
            logger.warning("Map local regex directory pattern failed to compile")
            return nil
        }
        let target = String(requestURL.prefix(ProxyLimits.maxURILength))
        let ns = target as NSString
        guard let match = regex.firstMatch(in: target, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        guard match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound else {
            logger.info("Map local regex directory pattern has no capture group; falling back to origin")
            return nil
        }
        return sanitizeCapturedSubpath(ns.substring(with: match.range(at: 1)))
    }

    /// Normalizes a captured subpath: strip query/fragment, percent-decode, drop a leading
    /// slash. Percent-decoding is intentional so traversal payloads collapse and get caught
    /// by the containment check in `serve`.
    private static func sanitizeCapturedSubpath(_ captured: String) -> String {
        var value = String(captured.prefix { $0 != "?" && $0 != "#" })
        value = value.removingPercentEncoding ?? value
        if value.hasPrefix("/") {
            value = String(value.dropFirst())
        }
        return value
    }

    /// Extracts the literal path prefix (everything before the first wildcard) from an
    /// authored wildcard pattern or a legacy compiled regex pattern.
    ///
    /// In authored wildcard syntax both `*` (any run) and `?` (one character) are wildcards,
    /// so the literal prefix ends at whichever appears first. That boundary is taken on the
    /// raw pattern before any URL parsing, so a wildcard `?` is never mistaken for a query
    /// separator (nor a `#` for a fragment). A compiled/legacy regex pattern carries escaped
    /// metacharacters (`\.`, `\/`) or `.*` and may use `?` as a quantifier, so it keeps the
    /// existing `*`-only boundary to avoid cutting a regex.
    private static func wildcardPrefixPath(from pattern: String) -> String {
        let looksCompiledRegex = pattern.contains(".*")
            || pattern.contains("\\.")
            || pattern.contains("\\/")

        var literalPrefix = pattern
        if !looksCompiledRegex,
           let boundary = pattern.firstIndex(where: { $0 == "*" || $0 == "?" })
        {
            literalPrefix = String(pattern[..<boundary])
        }

        let path = extractPathFromPattern(literalPrefix)
        let normalized = path
            .replacingOccurrences(of: "\\.", with: ".")
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: ".*", with: "*")
        if let star = normalized.firstIndex(of: "*") {
            return String(normalized[..<star])
        }
        return normalized
    }

    /// Strips a path prefix from the request path, returning the trailing subpath with no
    /// leading slash. Mirrors the legacy extraction so both entry points behave identically.
    private static func stripPrefix(_ prefix: String, from requestPath: String) -> String {
        let trimmedPrefix = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
        if !trimmedPrefix.isEmpty, requestPath.hasPrefix(trimmedPrefix) {
            var sub = String(requestPath.dropFirst(trimmedPrefix.count))
            if sub.hasPrefix("/") {
                sub = String(sub.dropFirst())
            }
            return sub
        }
        if requestPath.hasPrefix("/") {
            return String(requestPath.dropFirst())
        }
        return requestPath
    }

    /// Builds the target file URL from directory root and subpath. An empty suffix resolves to
    /// the directory root itself, which `serve` rejects as a directory target — there is no
    /// implicit index synthesis.
    private static func resolveTargetURL(dirURL: URL, subpath: String) -> URL {
        if subpath.isEmpty {
            return dirURL
        }
        return dirURL.appendingPathComponent(subpath).standardizedFileURL
    }

    /// Loads file data with security checks (size limit, readability, path containment).
    private static func loadFile(
        at fileURL: URL,
        dirRoot: URL
    )
        -> Result<ResolvedFile, MapLocalError>
    {
        let resolved = fileURL.resolvingSymlinksInPath()

        let rootPath = dirRoot.path.hasSuffix("/") ? dirRoot.path : dirRoot.path + "/"
        guard resolved.path == dirRoot.path || resolved.path.hasPrefix(rootPath) else {
            logger.warning("SECURITY: Symlink escape blocked: \(resolved.path)")
            return .failure(.pathTraversal)
        }

        let fm = FileManager.default
        guard fm.isReadableFile(atPath: resolved.path) else {
            return .failure(.fileNotFound(path: resolved.lastPathComponent))
        }

        guard let attrs = try? fm.attributesOfItem(atPath: resolved.path),
              let fileSize = attrs[.size] as? UInt64 else
        {
            return .failure(.readError(
                NSError(domain: "MapLocalDirectoryResolver", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Cannot read file attributes",
                ])
            ))
        }

        guard fileSize <= maxFileSize else {
            logger.warning("SECURITY: File exceeds \(maxFileSize) bytes (\(fileSize)): \(resolved.path)")
            return .failure(.fileTooLarge)
        }

        do {
            let data = try Data(contentsOf: resolved)
            let mimeType = detectMIMEType(for: resolved)
            return .success(ResolvedFile(url: resolved, data: data, mimeType: mimeType))
        } catch {
            logger.error("Failed to read file: \(error.localizedDescription)")
            return .failure(.readError(error))
        }
    }

    /// Detects MIME type from file extension. Delegates to shared MimeTypeResolver.
    private static func detectMIMEType(for url: URL) -> String {
        MimeTypeResolver.mimeType(for: url)
    }
}
