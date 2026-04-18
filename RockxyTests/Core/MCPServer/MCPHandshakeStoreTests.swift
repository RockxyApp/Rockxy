import Foundation
@testable import Rockxy
import Testing

// MARK: - MCPHandshakeStoreTests

@Suite("MCP Handshake Store", .serialized)
struct MCPHandshakeStoreTests {
    // MARK: Internal

    @Test("Token generation returns base64 string")
    func tokenGeneration() throws {
        let token = MCPHandshakeStore.generateToken()
        #expect(token != nil)
        #expect(try !#require(token?.isEmpty))
        #expect(try Data(base64Encoded: #require(token)) != nil)
    }

    @Test("Generated tokens are unique")
    func tokenUniqueness() {
        let t1 = MCPHandshakeStore.generateToken()
        let t2 = MCPHandshakeStore.generateToken()
        #expect(t1 != t2)
    }

    @Test("Write and read handshake file")
    func writeAndRead() throws {
        let token = try #require(MCPHandshakeStore.generateToken())
        let fileURL = makeTempHandshakeURL()
        try MCPHandshakeStore.write(token: token, port: 9_710, to: fileURL)

        let handshake = try MCPHandshakeStore.read(from: fileURL)
        #expect(handshake.token == token)
        #expect(handshake.port == 9_710)

        MCPHandshakeStore.delete(at: fileURL)
    }

    @Test("Validate token with correct value")
    func validateCorrect() {
        #expect(MCPHandshakeStore.validateToken("abc123", against: "abc123"))
    }

    @Test("Validate token with wrong value")
    func validateWrong() {
        #expect(!MCPHandshakeStore.validateToken("abc123", against: "xyz789"))
    }

    @Test("Validate token with different lengths")
    func validateDifferentLengths() {
        #expect(!MCPHandshakeStore.validateToken("short", against: "muchlonger"))
    }

    @Test("Delete is idempotent")
    func deleteIdempotent() {
        let fileURL = makeTempHandshakeURL()
        MCPHandshakeStore.delete(at: fileURL)
        MCPHandshakeStore.delete(at: fileURL)
    }

    @Test("Handshake file uses identity-aware path")
    func pathUsesIdentity() {
        let path = MCPHandshakeStore.handshakeFilePath
        #expect(path.lastPathComponent == "mcp-handshake.json")
    }

    @Test("Generated token has expected base64 length for 32 bytes")
    func tokenLength() throws {
        let token = try #require(MCPHandshakeStore.generateToken())
        let data = try #require(Data(base64Encoded: token))
        #expect(data.count == 32)
    }

    @Test("Validate token with empty strings")
    func validateEmptyStrings() {
        #expect(MCPHandshakeStore.validateToken("", against: ""))
        #expect(!MCPHandshakeStore.validateToken("", against: "notempty"))
        #expect(!MCPHandshakeStore.validateToken("notempty", against: ""))
    }

    @Test("Handshake file has 0o600 permissions")
    func filePermissions() throws {
        let token = try #require(MCPHandshakeStore.generateToken())
        let fileURL = makeTempHandshakeURL()
        try MCPHandshakeStore.write(token: token, port: 9_710, to: fileURL)
        defer { MCPHandshakeStore.delete(at: fileURL) }

        let attrs = try FileManager.default.attributesOfItem(
            atPath: fileURL.path
        )
        let permissions = attrs[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    // MARK: Private

    private func makeTempHandshakeURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("mcp-handshake.json")
    }
}
