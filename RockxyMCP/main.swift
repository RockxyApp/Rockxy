import Foundation

let handshake: HandshakeReader.Handshake
do {
    handshake = try HandshakeReader.readHandshake()
} catch {
    FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
    FileHandle.standardError.write(Data("Debug: \(String(reflecting: error))\n".utf8))
    FileHandle.standardError.write(
        Data("Rockxy is not running or MCP server not started. Please launch Rockxy first & enable MCP in Settings.\n"
            .utf8)
    )
    exit(1)
}

let bridge = StdioBridge(token: handshake.token, port: handshake.port)
bridge.run()
