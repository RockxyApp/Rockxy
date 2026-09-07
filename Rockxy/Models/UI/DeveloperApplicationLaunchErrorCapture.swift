import Foundation

/// Drains a long-lived LaunchServices supervisor's stderr without allowing it to block on a full
/// pipe. Only a bounded prefix is retained for a useful failure message.
final class DeveloperApplicationLaunchErrorCapture: @unchecked Sendable {
    var capturedData: Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    func startDraining(_ handle: FileHandle) {
        completion.enter()
        DispatchQueue.global(qos: .utility).async { [self] in
            defer { completion.leave() }
            while true {
                let chunk = handle.readData(ofLength: 4_096)
                guard !chunk.isEmpty else {
                    return
                }
                lock.lock()
                if data.count < Self.maximumCapturedBytes {
                    data.append(contentsOf: chunk.prefix(Self.maximumCapturedBytes - data.count))
                }
                lock.unlock()
            }
        }
    }

    func waitForDrain() {
        _ = completion.wait(timeout: .now() + .seconds(1))
    }

    private static let maximumCapturedBytes = 4_096
    private let lock = NSLock()
    private let completion = DispatchGroup()
    private var data = Data()
}
