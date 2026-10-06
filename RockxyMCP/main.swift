import Foundation

// One executable, two names: `rockxy-cli` controls the running app from a terminal, and
// `rockxy-mcp` bridges an MCP client's stdio to the app's MCP server.
let invokedName = URL(fileURLWithPath: CommandLine.arguments.first ?? "").lastPathComponent
if invokedName == "rockxy-cli" {
    exit(CommandLineClient.run(arguments: Array(CommandLine.arguments.dropFirst())))
}

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
