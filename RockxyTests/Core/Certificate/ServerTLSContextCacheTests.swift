import Crypto
import Foundation
import NIOSSL
@testable import Rockxy
import SwiftASN1
import Testing
import X509

// MARK: - CountingServerTLSContextBuilder

/// Counts context builds so a reused context can be told apart from a rebuilt one.
private final class CountingServerTLSContextBuilder: @unchecked Sendable {
    // MARK: Internal

    func build(identity: CustomTLSIdentity, options: ServerTLSContextOptions) throws -> NIOSSLContext {
        lock.withLock { buildCount += 1 }
        return try TLSInterceptHandler.makeServerTLSContext(identity: identity, options: options)
    }

    func builds() -> Int {
        lock.withLock { buildCount }
    }

    // MARK: Private

    private let lock = NSLock()
    private var buildCount = 0
}

// MARK: - ServerTLSContextCacheTests

/// The TLS interception path asks for a server context on every intercepted connection, so one is
/// built at most once per cached host leaf. The hit tests below record that; the invalidation tests
/// are the ones that matter, because a context that outlived its signing material would make
/// Rockxy present a chain signed by a root the user has already replaced.
struct ServerTLSContextCacheTests {
    // MARK: Internal

    @Test("repeated connections to one host build the server context once and share it")
    func reusesContextAcrossConnections() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        let builder = CountingServerTLSContextBuilder()

        // A browser opens roughly this many connections for one page load.
        var contexts: [NIOSSLContext] = []
        for _ in 0 ..< 6 {
            try await contexts.append(self.context(from: manager, host: "example.com", builder: builder).context)
        }

        #expect(builder.builds() == 1)
        #expect(await manager.cachedHostCount == 1)
        #expect(await manager.cachedServerTLSContextCountForTests == 1)
        for cached in contexts.dropFirst() {
            #expect(cached === contexts[0])
        }
    }

    @Test("a different host gets its own context rather than another host's")
    func doesNotShareContextsBetweenHosts() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        let builder = CountingServerTLSContextBuilder()

        let first = try await context(from: manager, host: "one.example.com", builder: builder).context
        let second = try await context(from: manager, host: "two.example.com", builder: builder).context

        #expect(builder.builds() == 2)
        #expect(first !== second)
        #expect(await manager.cachedServerTLSContextCountForTests == 2)
    }

    /// Both switches a context bakes in are documented to take effect on the next connection. The
    /// TLS key log is the one that must not be missed: a context built while logging was off
    /// carries no callback, so reusing it would leave the setting reading as on while nothing was
    /// being written.
    @Test("a change to the server TLS options rebuilds the context")
    func rebuildsWhenOptionsChange() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        let builder = CountingServerTLSContextBuilder()

        let httpOneOnly = ServerTLSContextOptions(allowsHTTP2: false, logsTLSKeys: false)
        let withHTTP2 = ServerTLSContextOptions(allowsHTTP2: true, logsTLSKeys: false)
        let withKeyLog = ServerTLSContextOptions(allowsHTTP2: false, logsTLSKeys: true)

        let first = try await context(from: manager, host: "example.com", options: httpOneOnly, builder: builder)
        let afterHTTP2 = try await context(from: manager, host: "example.com", options: withHTTP2, builder: builder)
        let afterKeyLog = try await context(from: manager, host: "example.com", options: withKeyLog, builder: builder)

        #expect(builder.builds() == 3)
        #expect(afterHTTP2.context !== first.context)
        #expect(afterKeyLog.context !== afterHTTP2.context)
        // One leaf, one context: the rebuild replaced the cached context instead of accumulating.
        #expect(await manager.cachedHostCount == 1)
        #expect(await manager.cachedServerTLSContextCountForTests == 1)
    }

    /// Every signing-material change in `CertificateManager` funnels through `clearHostCache`, so
    /// this is the mechanism all three call sites rely on.
    @Test("clearing the host cache drops the cached context with its leaf")
    func clearingHostCacheDropsContext() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        let builder = CountingServerTLSContextBuilder()

        let first = try await context(from: manager, host: "example.com", builder: builder).context
        await manager.clearHostCache()

        #expect(await manager.cachedHostCount == 0)
        #expect(await manager.cachedServerTLSContextCountForTests == 0)

        let second = try await context(from: manager, host: "example.com", builder: builder).context
        #expect(builder.builds() == 2)
        #expect(second !== first)
    }

    @Test("adopting a different root CA drops the cached context")
    func adoptingDifferentRootDropsContext() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        let builder = CountingServerTLSContextBuilder()

        let first = try await context(from: manager, host: "example.com", builder: builder).context
        #expect(await manager.cachedServerTLSContextCountForTests == 1)

        let replacement = try RootCAGenerator.generate()
        try CertificateStore.saveRootCAPrivateKey(replacement.privateKey)
        try CertificateStore.saveRootCACertificate(replacement.certificate)
        #expect(try await manager.loadExistingRootCA())

        #expect(await manager.cachedHostCount == 0)
        #expect(await manager.cachedServerTLSContextCountForTests == 0)

        let second = try await context(from: manager, host: "example.com", builder: builder)
        #expect(builder.builds() == 2)
        #expect(second.context !== first)
        // The rebuilt chain is the one the replacement root signed.
        let leaf = try await manager.certificateForHost("example.com")
        #expect(
            leaf.issuerCertificate.publicKey.subjectPublicKeyInfoBytes
                == replacement.certificate.publicKey.subjectPublicKeyInfoBytes
        )
    }

    @Test("resetting the certificate manager drops the cached context")
    func resetDropsContext() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        let builder = CountingServerTLSContextBuilder()
        _ = try await context(from: manager, host: "example.com", builder: builder)

        try await manager.reset()

        #expect(await manager.cachedHostCount == 0)
        #expect(await manager.cachedServerTLSContextCountForTests == 0)
    }

    /// Empty material used to be rejected inside the pipeline setup. It still ends as a raw tunnel,
    /// but it now reports through the one failure path every other setup error takes.
    @Test("empty certificate material is refused instead of producing a context")
    func refusesEmptyCertificateMaterial() {
        let options = ServerTLSContextOptions(allowsHTTP2: false, logsTLSKeys: false)

        #expect(throws: TLSInterceptionSetupError.emptyCertificateMaterial) {
            try TLSInterceptHandler.makeServerTLSContext(
                identity: CustomTLSIdentity(certificateChainPEM: [], privateKeyPEM: "key"),
                options: options
            )
        }
        #expect(throws: TLSInterceptionSetupError.emptyCertificateMaterial) {
            try TLSInterceptHandler.makeServerTLSContext(
                identity: CustomTLSIdentity(certificateChainPEM: ["cert"], privateKeyPEM: ""),
                options: options
            )
        }
    }

    // MARK: Private

    private func context(
        from manager: CertificateManager,
        host: String,
        options: ServerTLSContextOptions = ServerTLSContextOptions(allowsHTTP2: false, logsTLSKeys: false),
        builder: CountingServerTLSContextBuilder
    )
        async throws -> GeneratedHostTLSContext
    {
        try await manager.serverTLSContextForHost(host, options: options) { identity, buildOptions in
            try builder.build(identity: identity, options: buildOptions)
        }
    }
}
