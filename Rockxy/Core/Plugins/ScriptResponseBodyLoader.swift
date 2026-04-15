import Foundation
import os

/// Loads a local file as a response body for `response.bodyFilePath`. Bounded
/// by `ProxyLimits.maxResponseBodySize` and sandboxed to the user's home
/// directory to prevent traversal-style abuse.
enum ScriptResponseBodyLoader {
    // MARK: Internal

    enum LoadError: Error, LocalizedError {
        case invalidPath(String)
        case outsideHome(String)
        case notRegularFile(String)
        case oversize(Int)
        case readFailed(String)

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case let .invalidPath(p): "Invalid path: \(p)"
            case let .outsideHome(p): "Path is outside the user's home directory: \(p)"
            case let .notRegularFile(p): "Not a regular file: \(p)"
            case let .oversize(size): "File exceeds response body cap (\(size) bytes)"
            case let .readFailed(msg): "Read failed: \(msg)"
            }
        }
    }

    /// Load the file at `path` into a `Data` value. `path` may begin with `~/`.
    /// Throws if the resolved path is not under `$HOME`, is not a regular file,
    /// or exceeds `limit` bytes.
    static func load(path: String, limit: Int = ProxyLimits.maxResponseBodySize) throws -> Data {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LoadError.invalidPath(path)
        }

        let expanded = (trimmed as NSString).expandingTildeInPath
        let resolved = URL(fileURLWithPath: expanded).standardizedFileURL.resolvingSymlinksInPath()
        let homeURL = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.resolvingSymlinksInPath()

        // Reject paths outside $HOME (defense in depth — bodyFilePath is a remote-controlled string).
        let resolvedPath = resolved.path
        let homePath = homeURL.path.hasSuffix("/") ? homeURL.path : homeURL.path + "/"
        guard resolvedPath == homeURL.path || resolvedPath.hasPrefix(homePath) else {
            throw LoadError.outsideHome(resolvedPath)
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedPath, isDirectory: &isDir), !isDir.boolValue else {
            throw LoadError.notRegularFile(resolvedPath)
        }

        // Pre-check size before reading to avoid loading oversized files into memory.
        if let attrs = try? FileManager.default.attributesOfItem(atPath: resolvedPath),
           let size = attrs[.size] as? Int,
           size > limit
        {
            throw LoadError.oversize(size)
        }

        do {
            let data = try Data(contentsOf: resolved, options: [.mappedIfSafe])
            if data.count > limit {
                throw LoadError.oversize(data.count)
            }
            return data
        } catch let LoadError.oversize(size) {
            throw LoadError.oversize(size)
        } catch {
            throw LoadError.readFailed(error.localizedDescription)
        }
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "ScriptResponseBodyLoader"
    )
}
