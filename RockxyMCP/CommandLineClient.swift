import Darwin
import Foundation

// `rockxy-cli`: sends one command to the running Rockxy over its private command-line socket
// and prints the reply.

// MARK: - CommandLineClient

enum CommandLineClient {
    // MARK: Internal

    /// Runs the command and returns the process exit status.
    static func run(arguments: [String]) -> Int32 {
        if arguments.isEmpty || ["help", "-h", "--help"].contains(arguments[0].lowercased()) {
            print(usage)
            return 0
        }
        let socketPath = HandshakeReader.applicationSupportDirectory
            .appendingPathComponent(socketFileName).path
        let request: [String: Any] = [
            "arguments": arguments,
            "workingDirectory": FileManager.default.currentDirectoryPath,
        ]
        guard var payload = try? JSONSerialization.data(withJSONObject: request) else {
            return fail("Could not encode the request.")
        }
        payload.append(0x0A)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            return fail("Could not open a socket.")
        }
        defer { close(fd) }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 60, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        guard socketPath.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else {
            return fail("The socket path is too long.")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: socketPath.utf8)
            buffer[socketPath.utf8.count] = 0
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            return fail(
                "Rockxy is not running, or command-line control is off. Open Rockxy and turn on "
                    + "Settings > Advanced > Allow command-line control."
            )
        }

        let sent = payload.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else {
                return false
            }
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, base + offset, buffer.count - offset)
                guard written > 0 else {
                    return false
                }
                offset += written
            }
            return true
        }
        guard sent else {
            return fail("Could not send the command to Rockxy.")
        }

        var reply = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while reply.count < maxReplySize {
            let count = read(fd, &chunk, chunk.count)
            guard count > 0 else {
                break
            }
            reply.append(contentsOf: chunk[0 ..< count])
        }
        guard let object = try? JSONSerialization.jsonObject(with: reply) as? [String: Any],
              let ok = object["ok"] as? Bool,
              let message = object["message"] as? String else
        {
            return fail("Rockxy did not answer. Try again.")
        }
        if ok {
            print(message)
            return 0
        }
        return fail(message)
    }

    // MARK: Private

    private static let socketFileName = "rockxy-cli.sock"
    private static let maxReplySize = 1024 * 1024

    private static let usage = """
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

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data("rockxy-cli: \(message)\n".utf8))
        return 1
    }
}
