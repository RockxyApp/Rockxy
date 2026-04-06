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
        let expanded = (directoryPath as NSString).expandingTildeInPath
        let dirURL = URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else {
            logger.warning("SECURITY: Map local directory does not exist: \(dirURL.path)")
            return .failure(.directoryNotFound)
        }

        let subpath = extractSubpath(requestPath: requestPath, urlPattern: urlPattern)
        let targetURL = resolveTargetURL(dirURL: dirURL, subpath: subpath)

        let resolved = targetURL.resolvingSymlinksInPath()
        let resolvedDir = dirURL.resolvingSymlinksInPath()

        let rootPath = resolvedDir.path.hasSuffix("/") ? resolvedDir.path : resolvedDir.path + "/"
        guard resolved.path == resolvedDir.path || resolved.path.hasPrefix(rootPath) else {
            logger.warning("SECURITY: Path traversal attempt blocked: \(resolved.path) outside \(resolvedDir.path)")
            return .failure(.pathTraversal)
        }

        if !fm.fileExists(atPath: resolved.path) {
            let indexURL = resolved.appendingPathComponent("index.html")
            if fm.fileExists(atPath: indexURL.path) {
                return loadFile(at: indexURL, dirRoot: resolvedDir)
            }
            logger.info("Map local file not found: \(resolved.path)")
            return .failure(.fileNotFound(path: subpath))
        }

        var isDirTarget: ObjCBool = false
        if fm.fileExists(atPath: resolved.path, isDirectory: &isDirTarget), isDirTarget.boolValue {
            let indexURL = resolved.appendingPathComponent("index.html")
            if fm.fileExists(atPath: indexURL.path) {
                return loadFile(at: indexURL, dirRoot: resolvedDir)
            }
            return .failure(.fileNotFound(path: "\(subpath)/index.html"))
        }

        return loadFile(at: resolved, dirRoot: resolvedDir)
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "MapLocalDirectoryResolver")

    /// Maximum file size: 10 MB (same as MapLocalFileValidator).
    private static let maxFileSize: UInt64 = 10 * 1024 * 1024

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

    /// Builds the target file URL from directory root and subpath, handling index.html fallback.
    private static func resolveTargetURL(dirURL: URL, subpath: String) -> URL {
        if subpath.isEmpty {
            return dirURL.appendingPathComponent("index.html")
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
