import AppKit
import Foundation
import os

/// Resolves macOS process names from TCP source ports by querying `lsof`.
/// Called once per batch in `processBatch()` to map all active connections to
/// the proxy port → originating app name. Results are cached briefly since
/// TCP ports are reused slowly.
final class ProcessResolver: @unchecked Sendable {
    // MARK: Internal

    static let shared = ProcessResolver()

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
        var pathBuffer = [CChar](repeating: 0, count: 4096)
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
