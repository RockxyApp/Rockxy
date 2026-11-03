import Darwin
import Dispatch
import Foundation
@testable import Rockxy
import Testing

// MARK: - ClientIdentityCollectionExecutorTests

/// The connection-table provider shells out to `lsof` and blocks until it exits or its
/// deadline passes. Pinning where it runs is the point of these tests: on the Swift
/// cooperative pool that block holds one of a small, fixed number of threads per
/// connection burst and stalls every unrelated async task in the app.
struct ClientIdentityCollectionExecutorTests {
    @Test("Connection-table collection runs on its own queue, never the cooperative pool")
    func collectionRunsOnDedicatedQueue() async {
        let observed = LabelBox()
        let resolver = ClientIdentityResolver(
            connectionTableProvider: { _, _ in
                observed.set(String(cString: __dispatch_queue_get_label(nil)))
                return []
            },
            identityProvider: { _, _ in nil },
            excludePID: 999
        )

        _ = await resolver.resolveIdentity(descriptor: ProxyConnectionDescriptor(
            acceptedAt: DispatchTime(uptimeNanoseconds: 1_000),
            clientHost: "127.0.0.1",
            clientPort: 54_321,
            proxyHost: "127.0.0.1",
            proxyPort: 9_090
        ))

        #expect(observed.get() == "rockxy.client-identity.connection-table")
    }
}

// MARK: - LabelBox

private final class LabelBox: @unchecked Sendable {
    // MARK: Internal

    func set(_ value: String) {
        lock.withLock { stored = value }
    }

    func get() -> String? {
        lock.withLock { stored }
    }

    // MARK: Private

    private let lock = NSLock()
    private var stored: String?
}
