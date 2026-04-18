import Foundation
import os
import Security

// MARK: - MCPHandshakeStore

/// Manages the MCP authentication handshake file written at server start and
/// removed on shutdown. Both the Rockxy app and CLI binary read the same path
/// to obtain the bearer token and port.
enum MCPHandshakeStore {
    // MARK: Internal

    struct Handshake: Codable {
        let token: String
        let port: Int
    }

    static var handshakeFilePath: URL {
        RockxyIdentity.current.appSupportDirectory()
            .appendingPathComponent("mcp-handshake.json")
    }

    static func generateToken() -> String? {
        var bytes = [UInt8](repeating: 0, count: tokenByteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            logger.error("SecRandomCopyBytes failed with status \(status)")
            return nil
        }
        return Data(bytes).base64EncodedString()
    }

    static func write(token: String, port: Int) throws {
        try write(token: token, port: port, to: handshakeFilePath)
    }

    static func write(token: String, port: Int, to fileURL: URL) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let handshake = Handshake(token: token, port: port)
        let data = try JSONEncoder().encode(handshake)
        let tempURL = directory
            .appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")

        do {
            guard FileManager.default.createFile(
                atPath: tempURL.path,
                contents: data,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }

            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: fileURL)
            }
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }

        logger.info("Wrote MCP handshake file at port \(port)")
    }

    static func read() throws -> Handshake {
        try read(from: handshakeFilePath)
    }

    static func read(from fileURL: URL) throws -> Handshake {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Handshake.self, from: data)
    }

    static func delete() {
        delete(at: handshakeFilePath)
    }

    static func delete(at fileURL: URL) {
        do {
            try FileManager.default.removeItem(at: fileURL)
            logger.info("Deleted MCP handshake file")
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && error.code == NSFileNoSuchFileError
        {
            logger.debug("MCP handshake file already absent")
        } catch {
            logger.warning("Failed to delete MCP handshake file: \(error.localizedDescription)")
        }
    }

    /// Constant-time comparison to prevent timing side-channel attacks.
    /// Empty candidate or stored values are always rejected, so an unset
    /// handshake cannot match any client input.
    static func validateToken(_ candidate: String, against stored: String) -> Bool {
        guard !candidate.isEmpty, !stored.isEmpty else {
            return false
        }
        let candidateBytes = Array(candidate.utf8)
        let storedBytes = Array(stored.utf8)
        guard candidateBytes.count == storedBytes.count else {
            return false
        }
        var result: UInt8 = 0
        for (a, b) in zip(candidateBytes, storedBytes) {
            result |= a ^ b
        }
        return result == 0
    }

    // MARK: Private

    private static let tokenByteCount = 32

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "MCPHandshakeStore"
    )
}
