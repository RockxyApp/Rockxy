import Foundation
@testable import Rockxy
import Testing

// Map Local file work is reached from NIO event loops, where a blocking read with no deadline
// stalls every connection multiplexed onto that loop. These tests hold the queued delivery and
// the fallback contract the proxy handlers depend on: a result that cannot be served is reported
// as "nothing", and the handler forwards the origin request instead.

// MARK: - MapLocalOffLoopReadTests

struct MapLocalOffLoopReadTests {
    // MARK: Internal

    @Test("A file read is queued, never performed on the calling thread")
    func fileReadIsQueued() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("mapped.json")
        try Data(#"{"source":"map-local"}"#.utf8).write(to: file)

        // Occupies the serial Map Local queue, so the read cannot have run by the time the
        // call returns unless it ran inline on this thread.
        let gate = DispatchSemaphore(value: 0)
        MapLocalFileIO.perform { gate.wait() }

        let outcome = DeliveredData()
        MapLocalFileValidator.loadFileData(at: file.path) { outcome.deliver($0) }
        #expect(outcome.isDelivered == false)

        gate.signal()
        try await Self.waitForDelivery(of: outcome)
        #expect(outcome.data == Data(#"{"source":"map-local"}"#.utf8))
    }

    @Test("A missing target reports nothing so the handler can serve the origin")
    func missingTargetReportsNothing() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let outcome = DeliveredData()
        MapLocalFileValidator
            .loadFileData(at: directory.appendingPathComponent("absent.json").path) { outcome.deliver($0) }

        try await Self.waitForDelivery(of: outcome)
        #expect(outcome.data == nil)
    }

    @Test("A target over the size cap reports nothing without reading its bytes")
    func oversizedTargetReportsNothing() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("huge.bin")
        // One byte over the 10 MB cap: the size is checked on the open descriptor, before any
        // read, so nothing of this file reaches the response path.
        try Data(count: 10 * 1_024 * 1_024 + 1).write(to: file)

        let outcome = DeliveredData()
        MapLocalFileValidator.loadFileData(at: file.path) { outcome.deliver($0) }

        try await Self.waitForDelivery(of: outcome)
        #expect(outcome.data == nil)
    }

    @Test("Directory resolution is queued and reports the file it resolved")
    func directoryResolutionIsQueued() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("local-asset".utf8).write(to: directory.appendingPathComponent("app.js"))

        let gate = DispatchSemaphore(value: 0)
        MapLocalFileIO.perform { gate.wait() }

        let outcome = DeliveredFile()
        MapLocalDirectoryResolver.resolve(
            requestURL: "http://127.0.0.1/assets/app.js",
            matchContext: Self.directoryMatchContext(),
            directoryPath: directory.path
        ) { outcome.deliver($0) }
        #expect(outcome.isDelivered == false)

        gate.signal()
        try await Self.waitForDelivery(of: outcome)
        #expect(outcome.file?.data == Data("local-asset".utf8))
    }

    @Test("A missing subpath reports nothing so the handler can serve the origin")
    func missingSubpathReportsNothing() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let outcome = DeliveredFile()
        MapLocalDirectoryResolver.resolve(
            requestURL: "http://127.0.0.1/assets/absent.js",
            matchContext: Self.directoryMatchContext(),
            directoryPath: directory.path
        ) { outcome.deliver($0) }

        try await Self.waitForDelivery(of: outcome)
        #expect(outcome.file == nil)
    }

    // MARK: Private

    /// Records what the Map Local queue delivered. Locked because the value crosses from the
    /// file-I/O queue back to the test.
    private final class DeliveredData: Delivery, @unchecked Sendable {
        // MARK: Internal

        var data: Data? {
            lock.withLock { value }
        }

        var isDelivered: Bool {
            lock.withLock { delivered }
        }

        func deliver(_ data: Data?) {
            lock.withLock {
                value = data
                delivered = true
            }
        }

        // MARK: Private

        private let lock = NSLock()
        private var value: Data?
        private var delivered = false
    }

    private final class DeliveredFile: Delivery, @unchecked Sendable {
        // MARK: Internal

        var file: MapLocalDirectoryResolver.ResolvedFile? {
            lock.withLock { value }
        }

        var isDelivered: Bool {
            lock.withLock { delivered }
        }

        func deliver(_ file: MapLocalDirectoryResolver.ResolvedFile?) {
            lock.withLock {
                value = file
                delivered = true
            }
        }

        // MARK: Private

        private let lock = NSLock()
        private var value: MapLocalDirectoryResolver.ResolvedFile?
        private var delivered = false
    }

    private static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MapLocalOffLoop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Wildcard mapping for `/assets/*`, matching what the Map Local editor persists.
    private static func directoryMatchContext() -> MapLocalMatchContext {
        MapLocalMatchContext(matchCondition: RuleMatchCondition(
            urlPattern: "http://127.0.0.1/assets/*",
            matchType: .wildcard
        ))
    }

    private static func waitForDelivery(of delivery: some Delivery) async throws {
        for _ in 0 ..< 200 where !delivery.isDelivered {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(delivery.isDelivered, "the Map Local queue never reported a result")
    }
}

// MARK: - Delivery

private protocol Delivery: Sendable {
    var isDelivered: Bool { get }
}
