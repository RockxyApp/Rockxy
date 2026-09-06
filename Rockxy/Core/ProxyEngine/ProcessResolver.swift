import AppKit
import Foundation
import os

// MARK: - ProcessResolver

/// Resolves macOS process names from TCP source ports by querying `lsof`.
/// Called once per batch in `processBatch()` to map all active connections to
/// the proxy port → originating app name. Results are cached briefly since
/// TCP ports are reused slowly.
final class ProcessResolver: @unchecked Sendable {
    // MARK: Lifecycle

    init() {
        identityResolver = ClientIdentityResolver(
            connectionTableProvider: { proxyPort, deadline in
                ProcessResolver.runLsofConnectionTable(proxyPort: proxyPort, deadline: deadline)
            },
            identityProvider: { pid, command in
                ProcessResolver.applicationIdentity(forPID: pid, command: command)
            },
            excludePID: getpid()
        )
    }

    // MARK: Internal

    static let shared = ProcessResolver()

    /// Per-connection application-identity resolver backed by the live OS connection table.
    /// Used by the proxy to drive application-scoped SSL proxying decisions.
    let identityResolver: ClientIdentityResolver

    /// Runs a single `lsof` call against the proxy port and returns a mapping of
    /// client source port → human-readable app name. Cached for 2 seconds to avoid
    /// shelling out on every batch.
    func resolveProcesses(proxyPort: Int) -> [UInt16: String] {
        let now = DispatchTime.now()
        lock.lock()
        if let cached = cachedResult,
           let cacheTime = cacheTimestamp,
           Double(now.uptimeNanoseconds - cacheTime.uptimeNanoseconds) / 1_000_000_000 < cacheTTL
        {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let result = queryLsof(proxyPort: proxyPort)

        lock.lock()
        cachedResult = result
        cacheTimestamp = now
        lock.unlock()

        return result
    }

    /// Async version that dispatches the blocking lsof call off the cooperative thread pool.
    /// Safe to call from Swift actors without blocking their executor.
    func resolveProcessesAsync(proxyPort: Int) async -> [UInt16: String] {
        let now = DispatchTime.now()
        lock.lock()
        if let cached = cachedResult,
           let cacheTime = cacheTimestamp,
           Double(now.uptimeNanoseconds - cacheTime.uptimeNanoseconds) / 1_000_000_000 < cacheTTL
        {
            lock.unlock()
            return cached
        }
        lock.unlock()

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let result = self.resolveProcesses(proxyPort: proxyPort)
                continuation.resume(returning: result)
            }
        }
    }

    /// Resolves a single source port to an app name using `proc_pidinfo`-style lookup.
    /// Used as a fallback when `lsof` batch hasn't run yet.
    func resolveAppName(remotePort: UInt16) -> String? {
        lock.lock()
        if let cached = cachedResult, let name = cached[remotePort] {
            lock.unlock()
            return name
        }
        lock.unlock()

        guard let pid = findPIDForLocalPort(remotePort) else {
            return nil
        }
        return appNameForPID(pid)
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ProcessResolver")
    private let lock = NSLock()
    private var cachedResult: [UInt16: String]?
    private var cacheTimestamp: DispatchTime?
    private let cacheTTL: Double = 5.0

    /// Runs `lsof -i TCP:PORT -n -P -F pcn` and parses the output into a port→appName map.
    /// The `-F` flag produces machine-parseable output:
    ///   `p<pid>` lines, `c<command>` lines, `n<connection>` lines.
    private func queryLsof(proxyPort: Int) -> [UInt16: String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-i", "TCP:\(proxyPort)", "-n", "-P", "-F", "pcn"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            Self.logger.warning("Failed to launch lsof: \(error.localizedDescription)")
            return [:]
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return [:]
        }

        let output = String(data: data, encoding: .utf8) ?? ""
        return parseLsofOutput(output, proxyPort: proxyPort)
    }

    private func parseLsofOutput(_ output: String, proxyPort: Int) -> [UInt16: String] {
        var result: [UInt16: String] = [:]
        var currentPID: pid_t = 0
        var currentCommand = ""

        let proxyPortStr = ":\(proxyPort)"

        for line in output.components(separatedBy: "\n") {
            guard !line.isEmpty else {
                continue
            }

            let prefix = line.first
            let value = String(line.dropFirst())

            switch prefix {
            case "p":
                currentPID = pid_t(value) ?? 0
            case "c":
                currentCommand = value
            case "n":
                // Connection lines look like: 127.0.0.1:54321->127.0.0.1:9090
                // We want the source port (54321) from connections TO our proxy port
                guard value.contains("->") else {
                    continue
                }
                let parts = value.split(separator: "->")
                guard parts.count == 2 else {
                    continue
                }

                let destination = String(parts[1])
                guard destination.hasSuffix(proxyPortStr) else {
                    continue
                }

                // Extract source port from "127.0.0.1:54321"
                let source = String(parts[0])
                guard let lastColon = source.lastIndex(of: ":") else {
                    continue
                }
                let portStr = source[source.index(after: lastColon)...]
                guard let port = UInt16(portStr) else {
                    continue
                }

                let appName = resolveAppNameFromPID(currentPID, command: currentCommand)
                result[port] = appName
            default:
                break
            }
        }

        Self.logger.debug("Resolved \(result.count) process mappings via lsof")
        return result
    }

    /// Converts a PID + command name into a user-friendly app name.
    /// First tries `NSRunningApplication` for GUI apps (gives localized name + bundle path),
    /// then falls back to `proc_pidpath` for daemons, finally uses the raw command name.
    private func resolveAppNameFromPID(_ pid: pid_t, command: String) -> String {
        // Try NSRunningApplication first (gives nice names for GUI apps)
        if let app = NSRunningApplication(processIdentifier: pid),
           let name = app.localizedName, !name.isEmpty
        {
            return name
        }

        // Try proc_pidpath for daemons
        let name = appNameForPID(pid)
        if !name.isEmpty {
            return name
        }

        // Fall back to command name from lsof
        return prettifyCommandName(command)
    }

    /// Uses `proc_pidpath` to get the executable path, then derives a readable name.
    private func appNameForPID(_ pid: pid_t) -> String {
        var pathBuffer = [CChar](repeating: 0, count: 4_096)
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        guard pathLength > 0 else {
            return ""
        }

        let path = String(cString: pathBuffer)
        let execName = (path as NSString).lastPathComponent

        // If the executable is inside a .app bundle, extract the app name
        if let appRange = path.range(of: ".app/") {
            let appPath = String(path[path.startIndex ..< appRange.upperBound])
            let appName = ((appPath as NSString).lastPathComponent as NSString).deletingPathExtension
            if !appName.isEmpty {
                return appName
            }
        }

        return prettifyCommandName(execName)
    }

    /// Finds the PID that owns a given local TCP port by scanning `/proc` via libproc.
    private func findPIDForLocalPort(_ port: UInt16) -> pid_t? {
        // Use lsof for a single port lookup (simpler than iterating all PIDs)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-i", "TCP:\(port)", "-n", "-P", "-F", "p", "-sTCP:ESTABLISHED"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("p"), let pid = pid_t(line.dropFirst()) {
                return pid
            }
        }
        return nil
    }

    /// Cleans up raw command/executable names into human-readable form.
    private func prettifyCommandName(_ command: String) -> String {
        // Known daemon → friendly name mappings
        let daemonNames: [String: String] = [
            "nsurlsessiond": "NSURLSession (System)",
            "trustd": "Certificate Trust",
            "cloudd": "iCloud",
            "sharingd": "Sharing",
            "rapportd": "Rapport",
            "networkserviceproxy": "Network Service Proxy",
            "symptomsd": "Symptoms",
            "com.apple.WebKit.Networking": "WebKit Networking",
            "mDNSResponder": "DNS",
            "apsd": "Apple Push",
            "assistantd": "Siri",
            "parsecd": "Parsec",
            "gamed": "Game Center",
            "storekitagent": "StoreKit",
            "commcenter": "CommCenter",
            "identityservicesd": "Identity Services",
            "accountsd": "Accounts",
            "CalendarAgent": "Calendar",
            "remindd": "Reminders",
        ]

        if let friendly = daemonNames[command] {
            return friendly
        }

        // Strip trailing "d" from daemon names and capitalize
        var name = command
        if name.hasSuffix("d"), name.count > 2, name[name.index(before: name.endIndex)] == "d" {
            name = String(name.dropLast())
        }

        // Capitalize first letter
        if let first = name.first {
            return String(first).uppercased() + name.dropFirst()
        }

        return command
    }
}

// MARK: - Connection Table & Identity Resolution

extension ProcessResolver {
    /// Resolves a pid + command into a stable `ClientApplicationIdentity`. Prefers a bundle
    /// identity (running application or owning `.app` bundle) and falls back to a
    /// privacy-preserving executable digest when no bundle identity is available.
    static func applicationIdentity(forPID pid: Int32, command: String) -> ClientApplicationIdentity? {
        var pathBuffer = [CChar](repeating: 0, count: 4_096)
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        guard pathLength > 0 else {
            return nil
        }

        let path = String(cString: pathBuffer)
        guard commandMatchesExecutable(command: command, executablePath: path) else {
            Self.logger.debug("Declining stale client identity because the pid command no longer matches")
            return nil
        }
        if let outerBundlePath = ClientApplicationIdentity.outerAppBundlePath(forExecutablePath: path) {
            let displayName = ClientApplicationIdentity.appName(fromBundlePath: outerBundlePath)
            if let bundle = Bundle(path: outerBundlePath), let bundleID = bundle.bundleIdentifier {
                return .bundle(identifier: bundleID, displayName: displayName)
            }
            return .executable(normalizedPath: outerBundlePath, displayName: displayName)
        }
        if let running = NSRunningApplication(processIdentifier: pid), let bundleID = running.bundleIdentifier {
            let name = running.localizedName ?? command
            return .bundle(identifier: bundleID, displayName: name)
        }

        let execName = (path as NSString).lastPathComponent
        return .executable(normalizedPath: path, displayName: execName)
    }

    /// `lsof` command names may be truncated or omit punctuation, so compare normalized prefixes.
    /// A mismatch is strong evidence that the pid was recycled between socket collection and
    /// `proc_pidpath`; declining is safer than applying another process's application rule.
    static func commandMatchesExecutable(command: String, executablePath: String) -> Bool {
        let allowed = CharacterSet.alphanumerics
        func normalized(_ value: String) -> String {
            value.unicodeScalars
                .filter { allowed.contains($0) }
                .map(String.init)
                .joined()
                .lowercased()
        }

        let commandName = normalized(command)
        let executableName = normalized((executablePath as NSString).lastPathComponent)
        guard !commandName.isEmpty, !executableName.isEmpty else {
            return false
        }
        return commandName.hasPrefix(executableName) || executableName.hasPrefix(commandName)
    }

    /// Collects the live TCP connection table for the proxy port via `lsof`, bounded by a
    /// watchdog deadline. Reads the pipe on a background queue to avoid a full-pipe deadlock,
    /// and terminates the process if it overruns the deadline (returning an empty table).
    static func runLsofConnectionTable(proxyPort: Int, deadline: DispatchTime) -> [ProxyConnectionRecord] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP:\(proxyPort)", "-Fpcn"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            Self.logger.warning("Failed to launch lsof for connection table: \(error.localizedDescription)")
            return []
        }

        let handle = pipe.fileHandleForReading
        let outputBox = LsofOutputBox()
        let completion = DispatchSemaphore(value: 0)
        Self.lsofReadQueue.async {
            let data = handle.readDataToEndOfFile()
            outputBox.set(data)
            completion.signal()
        }

        let waitDeadline = deadline > DispatchTime.now() ? deadline : DispatchTime.now()
        if completion.wait(timeout: waitDeadline) == .timedOut {
            process.terminate()
            _ = completion.wait(timeout: .now() + .milliseconds(200))
            Self.logger.debug("lsof connection table timed out for port \(proxyPort)")
            return []
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return []
        }

        let output = String(data: outputBox.get(), encoding: .utf8) ?? ""
        return parseConnectionTable(output)
    }

    /// Parses `lsof -Fpcn` output into directional connection records. Kept pure and internal
    /// so parsing can be verified deterministically without shelling out.
    static func parseConnectionTable(_ output: String) -> [ProxyConnectionRecord] {
        var records: [ProxyConnectionRecord] = []
        var currentPID: Int32 = 0
        var currentCommand = ""

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            let prefix = line.first
            let value = String(line.dropFirst())

            switch prefix {
            case "p":
                currentPID = Int32(value) ?? 0
            case "c":
                currentCommand = value
            case "n":
                guard let record = parseConnectionLine(value, pid: currentPID, command: currentCommand) else {
                    continue
                }
                records.append(record)
            default:
                break
            }
        }

        return records
    }

    private static let lsofReadQueue = DispatchQueue(label: "rockxy.client-identity.lsof", qos: .utility)

    private static func parseConnectionLine(
        _ value: String,
        pid: Int32,
        command: String
    )
        -> ProxyConnectionRecord?
    {
        guard value.contains("->") else {
            return nil
        }
        let parts = value.components(separatedBy: "->")
        guard parts.count == 2,
              let source = parseEndpoint(parts[0]),
              let destination = parseEndpoint(parts[1]) else
        {
            return nil
        }
        return ProxyConnectionRecord(
            pid: pid,
            command: command,
            sourceHost: source.host,
            sourcePort: source.port,
            destHost: destination.host,
            destPort: destination.port
        )
    }

    private static func parseEndpoint(_ raw: String) -> (host: String, port: UInt16)? {
        let endpoint = raw.trimmingCharacters(in: .whitespaces)
        if endpoint.hasPrefix("[") {
            guard let closing = endpoint.firstIndex(of: "]") else {
                return nil
            }
            let host = String(endpoint[endpoint.index(after: endpoint.startIndex) ..< closing])
            let rest = endpoint[endpoint.index(after: closing)...]
            guard rest.hasPrefix(":"), let port = UInt16(rest.dropFirst()) else {
                return nil
            }
            return (host, port)
        }
        guard let lastColon = endpoint.lastIndex(of: ":") else {
            return nil
        }
        let host = String(endpoint[endpoint.startIndex ..< lastColon])
        guard let port = UInt16(endpoint[endpoint.index(after: lastColon)...]) else {
            return nil
        }
        return (host, port)
    }
}

// MARK: - LsofOutputBox

/// Thread-safe container so the background pipe reader and the watchdog thread can exchange
/// captured `lsof` output without a data race.
private final class LsofOutputBox: @unchecked Sendable {
    // MARK: Internal

    func set(_ data: Data) {
        lock.lock()
        stored = data
        lock.unlock()
    }

    func get() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    // MARK: Private

    private let lock = NSLock()
    private var stored = Data()
}
