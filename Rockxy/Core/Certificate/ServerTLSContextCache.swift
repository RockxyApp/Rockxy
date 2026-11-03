import Crypto
import Foundation
import NIOSSL
import X509

// The vocabulary shared between `CertificateManager`, which caches one built server TLS context
// per host certificate, and `TLSInterceptHandler`, which consumes it. It sits beside the cache
// rather than beside the handler because the cache is what has to reason about when a context
// stops being valid; `ServerTLSContextOptions.current` is the one place that reaches the other
// way, to sample the two proxy switches a built context bakes in.

// MARK: - ServerTLSContextOptions

/// The runtime server-TLS switches a built `NIOSSLContext` bakes in.
///
/// Both are user-visible settings documented to take effect on the next connection without
/// restarting the proxy, so a context reused across connections has to be rebuilt when either
/// moves. The TLS key log is the reason this is a value and not an assumption: a context built
/// while logging was off carries no key-log callback, and reusing it would leave the setting
/// showing as on while nothing was being written.
nonisolated struct ServerTLSContextOptions: Equatable, Sendable {
    let allowsHTTP2: Bool
    let logsTLSKeys: Bool

    /// Samples both switches as they stand now. Sampled once per connection, before any
    /// certificate work, so one handshake cannot see them change underneath it.
    static var current: Self {
        Self(
            allowsHTTP2: HTTP2ProxyOptions.isEnabled,
            logsTLSKeys: TLSKeyLogWriter.shared.destination != nil
        )
    }
}

// MARK: - TLSInterceptionSetupError

/// Why a server TLS context for an intercepted host could not be built.
nonisolated enum TLSInterceptionSetupError: Error, Equatable, LocalizedError {
    /// The resolved identity carried no certificate chain or no private key, so there is nothing
    /// to present. Still a raw-tunnel fallback; it now reports through the same failure path as
    /// every other setup error instead of a separate early return.
    case emptyCertificateMaterial

    var errorDescription: String? {
        switch self {
        case .emptyCertificateMaterial:
            "The certificate material for this host is empty"
        }
    }
}

// MARK: - GeneratedHostTLSContext

/// A server TLS context for one intercepted host, and whether the chain it presents is anchored
/// in Rockxy's own trusted root rather than a user-supplied one.
nonisolated struct GeneratedHostTLSContext: Sendable {
    let context: NIOSSLContext
    let provesRootCATrust: Bool
}

// MARK: - CachedServerTLSContext

/// A built context together with the server-TLS options it was built for, so a later connection
/// can tell whether those options have moved under it.
///
/// Stored inside `CertificateManager`'s host-certificate cache entry rather than in a cache of
/// its own, so a context and the leaf it presents share one lifetime.
nonisolated struct CachedServerTLSContext {
    let context: NIOSSLContext
    let options: ServerTLSContextOptions
}

// MARK: - HostCertEntry

/// One entry of `CertificateManager`'s LRU host-certificate cache: the signed leaf, its key, and
/// the server TLS context built from them.
nonisolated struct HostCertEntry {
    let certificate: Certificate
    let privateKey: P256.Signing.PrivateKey
    /// Built lazily by the first connection that needs it and reused by every later one. It lives
    /// here, not in a second dictionary, so there is exactly one lifetime to reason about: nothing
    /// can hold a context for a leaf that has been evicted or for a root that has been replaced.
    var serverTLSContext: CachedServerTLSContext?
}
