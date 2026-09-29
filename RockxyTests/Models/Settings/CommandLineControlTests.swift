import Foundation
@testable import Rockxy
import Testing

// MARK: - CommandLineControlTests

@MainActor
struct CommandLineControlTests {
    // MARK: Internal

    @Test("Commands and options parse, with relative paths resolved against the caller's directory")
    func parsing() throws {
        func parse(_ line: String) throws -> CommandLineCommand {
            try CommandLineCommand.parse(
                line.split(separator: " ").map(String.init),
                workingDirectory: "/Users/me/work"
            )
        }
        #expect(try parse("status") == .status)
        #expect(try parse("proxy on") == .systemProxy(true))
        #expect(try parse("record off") == .recording(false))
        #expect(try parse("Map-Local off") == .tool(.maplocal, false))
        #expect(try parse("scripting on") == .tool(.scripting, true))
        #expect(try parse("export -o out/rules.json --enabled-only")
            == .exportConfig(path: "/Users/me/work/out/rules.json", onlyEnabled: true))
        #expect(try parse("import -i /tmp/a.json -m replace") == .importConfig(path: "/tmp/a.json", mode: .replace))
        #expect(try parse("import -i ../a.json") == .importConfig(path: "/Users/me/a.json", mode: .append))
        #expect(try parse("export-log -o log.har --domain API.example.com --domain b.com")
            == .exportLog(path: "/Users/me/work/log.har", format: .har, domains: ["api.example.com", "b.com"]))
        #expect(try parse("export-log -o s.rockxysession --format session")
            == .exportLog(path: "/Users/me/work/s.rockxysession", format: .session, domains: []))
        #expect(try CommandLineCommand.parse([], workingDirectory: "/") == .help)

        #expect(throws: CommandLineParseError.self) { try parse("proxy maybe") }
        #expect(throws: CommandLineParseError.self) { try parse("teleport on") }
        #expect(throws: CommandLineParseError.self) { try parse("export") }
        #expect(throws: CommandLineParseError.self) { try parse("export -o") }
        #expect(throws: CommandLineParseError.self) { try parse("import -i a.json --mode merge") }
        #expect(throws: CommandLineParseError.self) { try parse("export -o a.json --surprise") }
    }

    @Test("Commands act on the app and report what happened")
    func running() async {
        let target = FakeTarget()
        var response = await run("status", target)
        #expect(response.ok)
        #expect(response.message.contains("Proxy: stopped"))

        response = await run("proxy on", target)
        #expect(!response.ok, "system proxy needs a running proxy")

        response = await run("start", target)
        #expect(response.ok)
        #expect(target.isProxyRunning)
        response = await run("proxy on", target)
        #expect(response.ok)
        #expect(target.isSystemProxyOn)

        response = await run("record off", target)
        #expect(response.ok)
        #expect(!target.isRecording)

        response = await run("blocklist off", target)
        #expect(target.tools[.blocklist] == false)

        response = await run("clear-session", target)
        #expect(target.clearCount == 1)

        response = await run("bogus", target)
        #expect(!response.ok)
        #expect(response.message.contains("rockxy-cli help"))

        response = await CommandLineCommandRunner.run(
            CommandLineRequest(arguments: ["status"], workingDirectory: "/"),
            target: nil
        )
        #expect(!response.ok)
    }

    @Test("Traffic exports as HAR, filtered by host, readable only by the user")
    func exportLog() async throws {
        let target = FakeTarget()
        target.transactions = [
            TestFixtures.makeTransaction(url: "https://api.example.com/a"),
            TestFixtures.makeTransaction(url: "https://cdn.example.com/b"),
        ]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let response = await CommandLineCommandRunner.run(
            CommandLineRequest(
                arguments: ["export-log", "-o", "log.har", "--domain", "api.example.com"],
                workingDirectory: directory.path
            ),
            target: target
        )
        #expect(response.ok)
        let file = directory.appendingPathComponent("log.har")
        let har = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        let entries = (har?["log"] as? [String: Any])?["entries"] as? [[String: Any]]
        #expect(entries?.count == 1)
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test("The socket answers a request from this user and removes its file when stopped")
    func socketRoundTrip() async throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("rx-\(UUID().uuidString.prefix(8)).sock").path
        let server = LocalCommandSocketServer { data in
            Data("echo:".utf8) + data
        }
        try server.start(path: path)
        let permissions = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)

        let reply = try await Task.detached { try Self.send(Data("ping\n".utf8), to: path) }.value
        #expect(reply == "echo:ping\n")

        server.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    // MARK: Private

    @MainActor
    private final class FakeTarget: CommandLineControlTarget {
        var isProxyRunning = false
        var isRecording = true
        var isSystemProxyOn = false
        var tools: [CommandLineTool: Bool] = [:]
        var clearCount = 0
        var transactions: [HTTPTransaction] = []

        var cliIsProxyRunning: Bool {
            isProxyRunning
        }

        var cliProxyPort: Int {
            9_090
        }

        var cliIsRecording: Bool {
            isRecording
        }

        var cliIsSystemProxyOn: Bool {
            isSystemProxyOn
        }

        func cliStartProxy() {
            isProxyRunning = true
        }

        func cliStopProxy() {
            isProxyRunning = false
        }

        func cliSetSystemProxy(_ isOn: Bool) {
            isSystemProxyOn = isOn
        }

        func cliSetRecording(_ isRecording: Bool) {
            self.isRecording = isRecording
        }

        func cliClearSession() async {
            clearCount += 1
        }

        func cliSetTool(_ tool: CommandLineTool, enabled: Bool) async {
            tools[tool] = enabled
        }

        func cliTransactions() -> [HTTPTransaction] {
            transactions
        }

        func cliWriteSession(_ transactions: [HTTPTransaction], to url: URL) throws {}
    }

    nonisolated private static func send(_ payload: Data, to path: String) throws -> String {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(fd) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: path.utf8)
            buffer[path.utf8.count] = 0
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            throw CocoaError(.fileNoSuchFile)
        }
        _ = payload.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        var reply = Data()
        var chunk = [UInt8](repeating: 0, count: 1_024)
        while true {
            let count = read(fd, &chunk, chunk.count)
            guard count > 0 else {
                break
            }
            reply.append(contentsOf: chunk[0 ..< count])
        }
        return String(bytes: reply, encoding: .utf8) ?? ""
    }

    private func run(_ line: String, _ target: FakeTarget) async -> CommandLineResponse {
        await CommandLineCommandRunner.run(
            CommandLineRequest(arguments: line.split(separator: " ").map(String.init), workingDirectory: "/"),
            target: target
        )
    }
}
