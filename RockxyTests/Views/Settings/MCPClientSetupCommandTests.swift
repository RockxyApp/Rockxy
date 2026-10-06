import Foundation
@testable import Rockxy
import Testing

// MARK: - MCPClientSetupCommandTests

struct MCPClientSetupCommandTests {
    @Test("Client commands register the bridge under the rockxy server name")
    func commandsUseBridgePath() {
        let path = "/Applications/Rockxy.app/Contents/MacOS/rockxy-mcp"

        #expect(MCPClientSetupCommand.claudeCode.command(bridgePath: path)
            == "claude mcp add rockxy -- '/Applications/Rockxy.app/Contents/MacOS/rockxy-mcp'")
        #expect(MCPClientSetupCommand.codex.command(bridgePath: path)
            == "codex mcp add rockxy -- '/Applications/Rockxy.app/Contents/MacOS/rockxy-mcp'")
    }

    @Test("Paths with spaces and quotes stay a single shell word")
    func quotesUnusualPaths() {
        let command = MCPClientSetupCommand.claudeCode.command(bridgePath: "/Users/o'neil/My Apps/rockxy-mcp")

        #expect(command == #"claude mcp add rockxy -- '/Users/o'"'"'neil/My Apps/rockxy-mcp'"#)
    }
}
