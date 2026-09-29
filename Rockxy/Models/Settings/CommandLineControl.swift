import Foundation

// Commands the `rockxy-cli` tool sends to the running app, how they are parsed, and how they
// are carried out against the main workspace.

// MARK: - CommandLineRequest

/// One request from `rockxy-cli`: its arguments and the directory it ran in, so relative file
/// paths resolve the way the user typed them.
struct CommandLineRequest: Codable, Equatable {
    var arguments: [String]
    var workingDirectory: String
}

// MARK: - CommandLineResponse

struct CommandLineResponse: Codable, Equatable {
    var ok: Bool
    var message: String

    static func success(_ message: String) -> CommandLineResponse {
        CommandLineResponse(ok: true, message: message)
    }

    static func failure(_ message: String) -> CommandLineResponse {
        CommandLineResponse(ok: false, message: message)
    }
}

// MARK: - CommandLineTool

/// Debugging tools the command line can switch on and off.
enum CommandLineTool: String, CaseIterable {
    case breakpoint
    case maplocal
    case mapremote
    case blocklist
    case allowlist
    case networkconditions
    case modifyheaders
    case scripting
    case nocaching
}

// MARK: - CommandLineExportFormat

enum CommandLineExportFormat: String, CaseIterable {
    case har
    case session
}

// MARK: - CommandLineCommand

enum CommandLineCommand: Equatable {
    case status
    case startProxy
    case stopProxy
    case systemProxy(Bool)
    case recording(Bool)
    case clearSession
    case tool(CommandLineTool, Bool)
    case exportConfig(path: String, onlyEnabled: Bool)
    case importConfig(path: String, mode: SettingsBackupImportMode)
    case exportLog(path: String, format: CommandLineExportFormat, domains: [String])
    case help

    // MARK: Internal

    static let usage = """
    Usage: rockxy-cli <command> [options]

    Commands:
      status                                   Show whether the proxy and system proxy are on.
      start | stop                             Start or stop the proxy.
      proxy on|off                             Route macOS traffic through Rockxy, or stop.
      record on|off                            Resume or pause recording.
      clear-session                            Remove every captured request.
      <tool> on|off                            Switch a tool: breakpoint, maplocal, mapremote,
                                               blocklist, allowlist, networkconditions,
                                               modifyheaders, scripting, nocaching.
      export -o <file> [--enabled-only]        Save every tool's rules to a file.
      import -i <file> [--mode append|replace] Load rules saved by export. Default: append.
      export-log -o <file> [--format har|session] [--domain <host>]...
                                               Save captured traffic, optionally for some hosts.
      help                                     Show this help.

    Command-line control must be on in Rockxy Settings > Advanced.
    """

    /// Parses arguments; relative paths resolve against `workingDirectory`.
    static func parse(_ arguments: [String], workingDirectory: String) throws -> CommandLineCommand {
        guard let name = arguments.first?.lowercased() else {
            return .help
        }
        let rest = Array(arguments.dropFirst())
        func onOff() throws -> Bool {
            switch rest.first?.lowercased() {
            case "on": return true
            case "off": return false
            default: throw CommandLineParseError(String(localized: "Add on or off.", bundle: RockxyLocalization.bundle))
            }
        }
        switch name {
        case "help",
             "-h",
             "--help":
            return .help
        case "status":
            return .status
        case "start":
            return .startProxy
        case "stop":
            return .stopProxy
        case "proxy":
            return try .systemProxy(onOff())
        case "record",
             "recording":
            return try .recording(onOff())
        case "clear-session",
             "clear":
            return .clearSession
        case "export":
            let options = try Options(rest, valued: ["-o", "--output"], flags: ["--enabled-only"])
            return try .exportConfig(
                path: resolve(options.required("-o", "--output"), in: workingDirectory),
                onlyEnabled: options.flags.contains("--enabled-only")
            )
        case "import":
            let options = try Options(rest, valued: ["-i", "--input", "-m", "--mode"], flags: [])
            let mode: SettingsBackupImportMode
            switch options.value("-m", "--mode")?.lowercased() ?? "append" {
            case "append": mode = .append
            case "replace",
                 "override": mode = .replace
            default:
                throw CommandLineParseError(String(
                    localized: "The mode must be append or replace.",
                    bundle: RockxyLocalization.bundle
                ))
            }
            return try .importConfig(path: resolve(options.required("-i", "--input"), in: workingDirectory), mode: mode)
        case "export-log":
            let options = try Options(
                rest,
                valued: ["-o", "--output", "-f", "--format", "--domain", "--domains"],
                flags: []
            )
            guard let format = CommandLineExportFormat(rawValue: options.value("-f", "--format")?
                .lowercased() ?? "har") else
            {
                throw CommandLineParseError(String(
                    localized: "The format must be har or session.",
                    bundle: RockxyLocalization.bundle
                ))
            }
            return try .exportLog(
                path: resolve(options.required("-o", "--output"), in: workingDirectory),
                format: format,
                domains: options.values("--domain", "--domains").map { $0.lowercased() }
            )
        default:
            guard let tool = CommandLineTool(rawValue: name.replacingOccurrences(of: "-", with: "")) else {
                throw CommandLineParseError(String(
                    localized: "Unknown command “\(name)”. Run rockxy-cli help to see the commands.",
                    bundle: RockxyLocalization.bundle
                ))
            }
            return try .tool(tool, onOff())
        }
    }

    // MARK: Private

    private struct Options {
        // MARK: Lifecycle

        init(_ arguments: [String], valued: Set<String>, flags known: Set<String>) throws {
            var index = 0
            while index < arguments.count {
                let argument = arguments[index]
                if valued.contains(argument) {
                    guard index + 1 < arguments.count else {
                        throw CommandLineParseError(String(
                            localized: "\(argument) needs a value.",
                            bundle: RockxyLocalization.bundle
                        ))
                    }
                    pairs.append((argument, arguments[index + 1]))
                    index += 2
                } else if known.contains(argument) {
                    flags.insert(argument)
                    index += 1
                } else {
                    throw CommandLineParseError(String(
                        localized: "Unknown option “\(argument)”.",
                        bundle: RockxyLocalization.bundle
                    ))
                }
            }
        }

        // MARK: Internal

        var pairs: [(String, String)] = []
        var flags: Set<String> = []

        func value(_ names: String...) -> String? {
            pairs.last { names.contains($0.0) }?.1
        }

        func values(_ names: String...) -> [String] {
            pairs.filter { names.contains($0.0) }.flatMap { $0.1.split(separator: ",").map(String.init) }
        }

        func required(_ names: String...) throws -> String {
            guard let found = pairs.last(where: { names.contains($0.0) })?.1, !found.isEmpty else {
                throw CommandLineParseError(String(
                    localized: "Add \(names[0]) with a file path.",
                    bundle: RockxyLocalization.bundle
                ))
            }
            return found
        }
    }

    private static func resolve(_ path: String, in workingDirectory: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL.path
        }
        return URL(fileURLWithPath: workingDirectory, isDirectory: true)
            .appendingPathComponent(expanded).standardizedFileURL.path
    }
}

// MARK: - CommandLineParseError

struct CommandLineParseError: LocalizedError, Equatable {
    // MARK: Lifecycle

    init(_ message: String) {
        self.message = message
    }

    // MARK: Internal

    let message: String

    var errorDescription: String? {
        message
    }
}

// MARK: - CommandLineControlTarget

/// What a command needs from the running app. The main workspace provides it; tests use a fake.
@MainActor
protocol CommandLineControlTarget: AnyObject {
    var cliIsProxyRunning: Bool { get }
    var cliProxyPort: Int { get }
    var cliIsRecording: Bool { get }
    var cliIsSystemProxyOn: Bool { get }
    func cliStartProxy()
    func cliStopProxy()
    func cliSetSystemProxy(_ isOn: Bool)
    func cliSetRecording(_ isRecording: Bool)
    func cliClearSession() async
    func cliSetTool(_ tool: CommandLineTool, enabled: Bool) async
    /// Transactions of the current session, newest last.
    func cliTransactions() -> [HTTPTransaction]
    func cliWriteSession(_ transactions: [HTTPTransaction], to url: URL) throws
}

// MARK: - CommandLineCommandRunner

@MainActor
enum CommandLineCommandRunner {
    static func run(_ request: CommandLineRequest, target: CommandLineControlTarget?) async -> CommandLineResponse {
        let command: CommandLineCommand
        do {
            command = try CommandLineCommand.parse(request.arguments, workingDirectory: request.workingDirectory)
        } catch {
            return .failure(error.localizedDescription)
        }
        if command == .help {
            return .success(CommandLineCommand.usage)
        }
        guard let target else {
            return .failure(String(
                localized: "Rockxy has no open window. Open a Rockxy window and try again.",
                bundle: RockxyLocalization.bundle
            ))
        }
        return await execute(command, target: target)
    }

    static func execute(_ command: CommandLineCommand, target: CommandLineControlTarget) async -> CommandLineResponse {
        switch command {
        case .help:
            return .success(CommandLineCommand.usage)
        case .status:
            let proxy = target.cliIsProxyRunning
                ? String(
                    localized: "Proxy: running on port \(String(target.cliProxyPort))",
                    bundle: RockxyLocalization.bundle
                )
                : String(localized: "Proxy: stopped", bundle: RockxyLocalization.bundle)
            let system = target.cliIsSystemProxyOn
                ? String(localized: "System proxy: on", bundle: RockxyLocalization.bundle)
                : String(localized: "System proxy: off", bundle: RockxyLocalization.bundle)
            let recording = target.cliIsRecording
                ? String(localized: "Recording: on", bundle: RockxyLocalization.bundle)
                : String(localized: "Recording: paused", bundle: RockxyLocalization.bundle)
            return .success([proxy, system, recording].joined(separator: "\n"))
        case .startProxy:
            target.cliStartProxy()
            return .success(String(localized: "Starting the proxy.", bundle: RockxyLocalization.bundle))
        case .stopProxy:
            target.cliStopProxy()
            return .success(String(localized: "Stopping the proxy.", bundle: RockxyLocalization.bundle))
        case let .systemProxy(isOn):
            guard target.cliIsProxyRunning || !isOn else {
                return .failure(String(
                    localized: "The proxy is not running. Run rockxy-cli start first.",
                    bundle: RockxyLocalization.bundle
                ))
            }
            target.cliSetSystemProxy(isOn)
            return .success(isOn
                ? String(localized: "Routing macOS traffic through Rockxy.", bundle: RockxyLocalization.bundle)
                : String(localized: "Stopped routing macOS traffic through Rockxy.", bundle: RockxyLocalization.bundle))
        case let .recording(isOn):
            guard target.cliIsProxyRunning else {
                return .failure(String(
                    localized: "The proxy is not running. Run rockxy-cli start first.",
                    bundle: RockxyLocalization.bundle
                ))
            }
            target.cliSetRecording(isOn)
            return .success(isOn
                ? String(localized: "Recording resumed.", bundle: RockxyLocalization.bundle)
                : String(localized: "Recording paused.", bundle: RockxyLocalization.bundle))
        case .clearSession:
            await target.cliClearSession()
            return .success(String(localized: "Session cleared.", bundle: RockxyLocalization.bundle))
        case let .tool(tool, enabled):
            await target.cliSetTool(tool, enabled: enabled)
            return .success(enabled
                ? String(localized: "\(tool.rawValue) is on.", bundle: RockxyLocalization.bundle)
                : String(localized: "\(tool.rawValue) is off.", bundle: RockxyLocalization.bundle))
        case let .exportConfig(path, onlyEnabled):
            let document = await SettingsBackupService.makeBackup(onlyEnabledRules: onlyEnabled)
            do {
                try SettingsBackupFlow.write(document, to: URL(fileURLWithPath: path))
            } catch {
                return .failure(error.localizedDescription)
            }
            return .success(String(localized: "Saved settings to \(path).", bundle: RockxyLocalization.bundle))
        case let .importConfig(path, mode):
            let document: SettingsBackupDocument
            do {
                let url = URL(fileURLWithPath: path)
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= SettingsBackupDocument.maxFileSize else {
                    throw SettingsBackupError.tooLarge
                }
                document = try SettingsBackupDocument.decode(Data(contentsOf: url))
            } catch {
                return .failure(error.localizedDescription)
            }
            let report = await SettingsBackupService.importBackup(
                document,
                mode: mode,
                proxyPort: target.cliProxyPort
            )
            let lines = SettingsBackupFlow.reportLines(report)
            return .success(lines.joined(separator: "\n"))
        case let .exportLog(path, format, domains):
            let transactions = target.cliTransactions().filter { transaction in
                domains.isEmpty || domains.contains(transaction.request.host.lowercased())
            }
            let url = URL(fileURLWithPath: path)
            do {
                switch format {
                case .har:
                    try HARExporter().export(transactions: transactions).write(to: url, options: .atomic)
                case .session:
                    try target.cliWriteSession(transactions, to: url)
                }
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch {
                return .failure(error.localizedDescription)
            }
            return .success(String(AttributedString(
                localized: "Saved ^[\(transactions.count) request](inflect: true) to \(path).",
                bundle: RockxyLocalization.bundle,
                locale: RockxyLocalization.locale
            ).characters))
        }
    }
}
