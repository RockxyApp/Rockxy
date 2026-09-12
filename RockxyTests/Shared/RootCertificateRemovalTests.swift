import Crypto
import Foundation
@testable import Rockxy
import Security
import SwiftASN1
import Testing
import X509

// Behavior tests for the privileged root CA removal rules, driven through the injected
// keychain/trust boundary. Nothing here trusts a CA, opens `System.keychain`, or addresses the
// production daemon: the point is to exercise the ordering and refusal rules that a real
// removal can only demonstrate destructively.

// MARK: - RootCertificateOwnershipTests

struct RootCertificateOwnershipTests {
    @Test("empty and oversized input is refused before anything is inspected")
    func boundsAreEnforcedFirst() throws {
        let keychain = FakeSystemKeychain()

        #expect(throws: RootCertificateRemovalError.emptyCertificateData) {
            try RootCertificateRemover.removeExactCertificate(derData: Data(), using: keychain)
        }
        #expect(throws: RootCertificateRemovalError.oversizedCertificateData(bytes: 10_000)) {
            try RootCertificateRemover.removeExactCertificate(
                derData: Data(repeating: 0x30, count: 10_000),
                using: keychain
            )
        }
        #expect(keychain.hasMutated == false)
    }

    @Test("unparseable data is refused")
    func unparseableDataIsRefused() {
        let keychain = FakeSystemKeychain()

        #expect(throws: RootCertificateRemovalError.unreadableCertificateData) {
            try RootCertificateRemover.removeExactCertificate(
                derData: Data("not a certificate".utf8),
                using: keychain
            )
        }
        #expect(keychain.hasMutated == false)
    }

    @Test("a certificate with another common name is refused")
    func unrelatedCommonNameIsRefused() throws {
        let keychain = FakeSystemKeychain()
        let unrelated = try makeSelfSignedCertificateDER(commonName: "Some Other Root CA")

        #expect(throws: RootCertificateRemovalError.unexpectedCommonName("Some Other Root CA")) {
            try RootCertificateRemover.removeExactCertificate(derData: unrelated, using: keychain)
        }
        #expect(keychain.hasMutated == false)
    }

    @Test("a malformed key-specific Rockxy common name is refused")
    func malformedKeySpecificCommonNameIsRefused() throws {
        let keychain = FakeSystemKeychain()
        let lookalike = try makeSelfSignedCertificateDER(commonName: "Rockxy Root CA NOT-A-KEY-ID")

        #expect(throws: RootCertificateRemovalError.unexpectedCommonName("Rockxy Root CA NOT-A-KEY-ID")) {
            try RootCertificateRemover.removeExactCertificate(derData: lookalike, using: keychain)
        }
        #expect(keychain.hasMutated == false)
    }

    @Test("a certificate that borrows the common name but is not self-issued is refused")
    func borrowedCommonNameIsRefused() throws {
        let keychain = FakeSystemKeychain()
        let impostor = try makeImpostorCertificateDER()

        #expect(throws: RootCertificateRemovalError.notSelfIssued) {
            try RootCertificateRemover.removeExactCertificate(derData: impostor, using: keychain)
        }
        #expect(keychain.hasMutated == false)
    }

    @Test("a genuine Rockxy root validates and reports its own serial and fingerprint")
    func genuineRootValidates() throws {
        let der = try makeRockxyRootDER()

        let target = try RootCertificateRemover.validate(derData: der)

        let expectedSerialNumber = try serialNumber(of: der)
        #expect(target.derData == der)
        #expect(target.serialNumber == expectedSerialNumber)
        #expect(target.fingerprint == RootCertificateRemover.fingerprint(of: der))
    }
}

// MARK: - RootCertificateRemovalTests

struct RootCertificateRemovalTests {
    @Test("the exact certificate is removed even when its keychain label is something else")
    func exactTargetIsRemovedDespiteALabelMismatch() throws {
        let der = try makeRockxyRootDER()
        let keychain = FakeSystemKeychain()
        // A legacy import can carry the common name — or anything else — instead of the label
        // the app installs under. The DER is what selects it.
        try keychain.install(der: der, label: "Rockxy Root CA", trusted: true)

        let outcome = try RootCertificateRemover.removeExactCertificate(derData: der, using: keychain)

        #expect(outcome.removedCertificateCount == 1)
        #expect(outcome.removedTrustSettings)
        #expect(keychain.deletedDERs == [der])
        #expect(keychain.installedDERs.isEmpty)
        #expect(keychain.trustedDERs.isEmpty)
    }

    @Test("a certificate sharing the serial number but not the bytes is preserved")
    func sameSerialDifferentCertificateIsPreserved() throws {
        let der = try makeRockxyRootDER()
        var lookalike = der
        lookalike[lookalike.endIndex - 1] ^= 1

        let keychain = FakeSystemKeychain()
        let sharedSerial = try serialNumber(of: der)
        keychain.entries = [
            FakeSystemKeychain.Entry(derData: der, serialNumber: sharedSerial, label: "target"),
            FakeSystemKeychain.Entry(derData: lookalike, serialNumber: sharedSerial, label: "other"),
        ]

        let outcome = try RootCertificateRemover.removeExactCertificate(derData: der, using: keychain)

        // The serial number only narrows the search; the bytes decide.
        #expect(outcome.removedCertificateCount == 1)
        #expect(keychain.installedDERs == [lookalike])
    }

    @Test("a trust removal failure never reaches the deletion")
    func trustRemovalFailurePreventsDeletion() throws {
        let der = try makeRockxyRootDER()
        let keychain = FakeSystemKeychain()
        try keychain.install(der: der, label: "target", trusted: true)
        keychain.trustRemovalFailure = .trustRemovalFailed(detail: "security exit 1")

        #expect(throws: RootCertificateRemovalError.trustRemovalFailed(detail: "security exit 1")) {
            try RootCertificateRemover.removeExactCertificate(derData: der, using: keychain)
        }

        // The certificate is the only thing that can still address the settings that survived.
        #expect(keychain.deletedDERs.isEmpty)
        #expect(keychain.installedDERs == [der])
    }

    @Test("trust settings that survive a successful-looking removal block the deletion")
    func residualTrustSettingsPreventDeletion() throws {
        let der = try makeRockxyRootDER()
        let keychain = FakeSystemKeychain()
        try keychain.install(der: der, label: "target", trusted: true)
        keychain.trustRemovalLeavesResidue = true

        #expect(throws: RootCertificateRemovalError.self) {
            try RootCertificateRemover.removeExactCertificate(derData: der, using: keychain)
        }

        #expect(keychain.deletedDERs.isEmpty)
        #expect(keychain.installedDERs == [der])
    }

    @Test("a keychain query failure is never read as nothing to remove")
    func queryFailurePreventsMutation() throws {
        let der = try makeRockxyRootDER()
        let keychain = FakeSystemKeychain()
        try keychain.install(der: der, label: "target", trusted: true)
        keychain.serialQueryFailure = .keychainFailure(operation: "serial number query", status: errSecAuthFailed)

        #expect(throws: RootCertificateRemovalError.self) {
            try RootCertificateRemover.removeExactCertificate(derData: der, using: keychain)
        }
        #expect(keychain.hasMutated == false)
    }

    @Test("an unknown trust-settings status is never read as absence")
    func trustCopyFailurePreventsMutation() throws {
        let der = try makeRockxyRootDER()
        let keychain = FakeSystemKeychain()
        try keychain.install(der: der, label: "target", trusted: true)
        keychain.trustCopyFailure = .keychainFailure(operation: "copy admin trust settings", status: errSecAuthFailed)

        #expect(throws: RootCertificateRemovalError.self) {
            try RootCertificateRemover.removeExactCertificate(derData: der, using: keychain)
        }
        #expect(keychain.hasMutated == false)
    }

    @Test("orphaned trust settings are removed even with no installed copy left")
    func orphanedTrustSettingsAreRemoved() throws {
        let der = try makeRockxyRootDER()
        let keychain = FakeSystemKeychain()
        // Deleted in Keychain Access while its admin trust settings survived.
        keychain.trustedDERs = [der]

        let outcome = try RootCertificateRemover.removeExactCertificate(derData: der, using: keychain)

        #expect(outcome.removedCertificateCount == 0)
        #expect(outcome.removedTrustSettings)
        #expect(keychain.trustedDERs.isEmpty)
        #expect(keychain.deletedDERs.isEmpty)
    }

    @Test("a target that is neither installed nor trusted is an idempotent no-op")
    func removalIsIdempotent() throws {
        let der = try makeRockxyRootDER()
        let keychain = FakeSystemKeychain()
        try keychain.install(der: der, label: "target", trusted: true)

        let first = try RootCertificateRemover.removeExactCertificate(derData: der, using: keychain)
        let second = try RootCertificateRemover.removeExactCertificate(derData: der, using: keychain)

        #expect(first.removedCertificateCount == 1)
        #expect(second.removedCertificateCount == 0)
        #expect(second.removedTrustSettings == false)
        #expect(keychain.deletedDERs == [der])
        #expect(keychain.trustRemovalDERs == [der])
    }

    @Test("a delete that silently does not take is reported instead of believed")
    func unverifiedDeletionIsReported() throws {
        let der = try makeRockxyRootDER()
        let keychain = FakeSystemKeychain()
        try keychain.install(der: der, label: "target", trusted: true)
        keychain.deletionIsNoOp = true

        #expect(throws: RootCertificateRemovalError.certificateStillInstalled(
            fingerprint: RootCertificateRemover.fingerprint(of: der)
        )) {
            try RootCertificateRemover.removeExactCertificate(derData: der, using: keychain)
        }
    }

    @Test("removing one root later never disturbs the other one")
    func lateRemovalOfOnePreservesTheOther() throws {
        let first = try makeRockxyRootDER()
        let second = try makeRockxyRootDER()
        let keychain = FakeSystemKeychain()
        try keychain.install(der: first, label: "rockxy", trusted: true)
        try keychain.install(der: second, label: "rockxy", trusted: true)

        _ = try RootCertificateRemover.removeExactCertificate(derData: first, using: keychain)

        #expect(keychain.installedDERs == [second])
        #expect(keychain.trustedDERs == [second])

        _ = try RootCertificateRemover.removeExactCertificate(derData: second, using: keychain)

        #expect(keychain.installedDERs.isEmpty)
        #expect(keychain.trustedDERs.isEmpty)
    }
}

// MARK: - RootCertificateLegacySweepTests

/// The label sweeps that still exist for app builds predating protocol 2.
struct RootCertificateLegacySweepTests {
    @Test("the sweep addresses the label it installed under and nothing else")
    func sweepIsBoundedByLabel() throws {
        let labeled = try makeRockxyRootDER()
        let unlabeled = try makeRockxyRootDER()
        let keychain = FakeSystemKeychain()
        try keychain.install(der: labeled, label: "com.amunx.rockxy.rootCA", trusted: true)
        // Same common name, different label: widening discovery by name would sweep this up.
        try keychain.install(der: unlabeled, label: "someone.elses.label", trusted: true)

        let outcome = try RootCertificateRemover.removeLabeledCertificates(
            label: "com.amunx.rockxy.rootCA",
            keepingFingerprint: nil,
            using: keychain
        )

        #expect(outcome.removedCount == 1)
        #expect(outcome.isComplete)
        #expect(keychain.installedDERs == [unlabeled])
        #expect(keychain.trustedDERs == [unlabeled])
    }

    @Test("stale cleanup keeps the active fingerprint and removes the rest")
    func staleCleanupKeepsTheActiveCertificate() throws {
        let active = try makeRockxyRootDER()
        let stale = try makeRockxyRootDER()
        let keychain = FakeSystemKeychain()
        try keychain.install(der: active, label: "rockxy", trusted: true)
        try keychain.install(der: stale, label: "rockxy", trusted: true)

        let outcome = try RootCertificateRemover.removeLabeledCertificates(
            label: "rockxy",
            keepingFingerprint: RootCertificateRemover.fingerprint(of: active),
            using: keychain
        )

        #expect(outcome.removedCount == 1)
        #expect(keychain.installedDERs == [active])
        #expect(keychain.trustedDERs == [active])
    }

    @Test("only completed removals are counted, and the failures are reported")
    func failuresAreReportedAndNotCounted() throws {
        let removable = try makeRockxyRootDER()
        let stuck = try makeRockxyRootDER()
        let keychain = FakeSystemKeychain()
        try keychain.install(der: removable, label: "rockxy", trusted: true)
        try keychain.install(der: stuck, label: "rockxy", trusted: true)
        keychain.trustRemovalFailures = [stuck: .trustRemovalFailed(detail: "security exit 1")]

        let outcome = try RootCertificateRemover.removeLabeledCertificates(
            label: "rockxy",
            keepingFingerprint: nil,
            using: keychain
        )

        #expect(outcome.removedCount == 1)
        #expect(outcome.isComplete == false)
        let detail = try #require(outcome.failureDetail)
        #expect(detail.contains(RootCertificateRemover.fingerprint(of: stuck)))
        // The one that failed is still installed, so nothing claimed it was removed.
        #expect(keychain.installedDERs == [stuck])
    }

    @Test("a discovery failure propagates instead of reporting a clean sweep")
    func discoveryFailurePropagates() throws {
        let keychain = FakeSystemKeychain()
        keychain.labelQueryFailure = .keychainFailure(operation: "label query", status: errSecAuthFailed)

        #expect(throws: RootCertificateRemovalError.self) {
            try RootCertificateRemover.removeLabeledCertificates(
                label: "rockxy",
                keepingFingerprint: nil,
                using: keychain
            )
        }
        #expect(keychain.hasMutated == false)
    }
}

// MARK: - FakeSystemKeychain

/// An in-memory stand-in for the System keychain and the admin trust domain.
private final class FakeSystemKeychain: RootCertificateRemovalOperations {
    struct Entry {
        let derData: Data
        let serialNumber: Data
        let label: String
    }

    var entries: [Entry] = []
    var trustedDERs: [Data] = []

    var serialQueryFailure: RootCertificateRemovalError?
    var labelQueryFailure: RootCertificateRemovalError?
    var trustCopyFailure: RootCertificateRemovalError?
    var trustRemovalFailure: RootCertificateRemovalError?
    var trustRemovalFailures: [Data: RootCertificateRemovalError] = [:]
    var deletionFailure: RootCertificateRemovalError?

    /// Reports success while the settings survive — the shape a swallowed CLI failure produced.
    var trustRemovalLeavesResidue = false
    /// Reports success while the item stays installed.
    var deletionIsNoOp = false

    private(set) var deletedDERs: [Data] = []
    private(set) var trustRemovalDERs: [Data] = []

    var installedDERs: [Data] {
        entries.map(\.derData)
    }

    /// True once any privileged side effect has been attempted.
    var hasMutated: Bool {
        !deletedDERs.isEmpty || !trustRemovalDERs.isEmpty
    }

    func install(der: Data, label: String, trusted: Bool) throws {
        try entries.append(Entry(derData: der, serialNumber: serialNumber(of: der), label: label))
        if trusted {
            trustedDERs.append(der)
        }
    }

    func systemCertificates(serialNumber: Data) throws -> [SystemKeychainCertificate] {
        if let serialQueryFailure {
            throw serialQueryFailure
        }
        return entries
            .filter { $0.serialNumber == serialNumber }
            .map { SystemKeychainCertificate(reference: $0.derData as NSData, derData: $0.derData) }
    }

    func systemCertificates(label: String) throws -> [SystemKeychainCertificate] {
        if let labelQueryFailure {
            throw labelQueryFailure
        }
        return entries
            .filter { $0.label == label }
            .map { SystemKeychainCertificate(reference: $0.derData as NSData, derData: $0.derData) }
    }

    func hasAdminTrustSettings(derData: Data) throws -> Bool {
        if let trustCopyFailure {
            throw trustCopyFailure
        }
        return trustedDERs.contains(derData)
    }

    func removeAdminTrustSettings(derData: Data) throws {
        trustRemovalDERs.append(derData)
        if let failure = trustRemovalFailures[derData] ?? trustRemovalFailure {
            throw failure
        }
        guard !trustRemovalLeavesResidue else {
            return
        }
        trustedDERs.removeAll { $0 == derData }
    }

    func deleteSystemCertificates(_ certificates: [SystemKeychainCertificate]) throws {
        deletedDERs.append(contentsOf: certificates.map(\.derData))
        if let deletionFailure {
            throw deletionFailure
        }
        guard !deletionIsNoOp else {
            return
        }
        let removed = Set(certificates.map(\.derData))
        entries.removeAll { removed.contains($0.derData) }
    }
}

// MARK: - Shared Helpers

private func serialNumber(of derData: Data) throws -> Data {
    let certificate = try #require(SecCertificateCreateWithData(nil, derData as CFData))
    return try #require(SecCertificateCopySerialNumberData(certificate, nil) as Data?)
}

private func certificateDER(_ certificate: Certificate) throws -> Data {
    var serializer = DER.Serializer()
    try certificate.serialize(into: &serializer)
    return Data(serializer.serializedBytes)
}

private func makeRockxyRootDER() throws -> Data {
    try certificateDER(RootCAGenerator.generate().certificate)
}

/// A self-signed CA that is simply not Rockxy's.
private func makeSelfSignedCertificateDER(commonName: String) throws -> Data {
    let key = P256.Signing.PrivateKey()
    let name = try DistinguishedName { CommonName(commonName) }
    let certificate = try Certificate(
        version: .v3,
        serialNumber: Certificate.SerialNumber(),
        publicKey: Certificate.PublicKey(key.publicKey),
        notValidBefore: Date().addingTimeInterval(-3_600),
        notValidAfter: Date().addingTimeInterval(3_600),
        issuer: name,
        subject: name,
        signatureAlgorithm: .ecdsaWithSHA256,
        extensions: Certificate.Extensions {
            Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil))
        },
        issuerPrivateKey: Certificate.PrivateKey(key)
    )
    return try certificateDER(certificate)
}

/// Carries Rockxy's common name but was issued by somebody else, so it is not a root of ours.
private func makeImpostorCertificateDER() throws -> Data {
    let issuerKey = P256.Signing.PrivateKey()
    let subjectKey = P256.Signing.PrivateKey()
    let issuerName = try DistinguishedName { CommonName("Some Other Root CA") }
    let subjectName = try DistinguishedName { CommonName(RootCertificateRemover.expectedCommonName) }
    let certificate = try Certificate(
        version: .v3,
        serialNumber: Certificate.SerialNumber(),
        publicKey: Certificate.PublicKey(subjectKey.publicKey),
        notValidBefore: Date().addingTimeInterval(-3_600),
        notValidAfter: Date().addingTimeInterval(3_600),
        issuer: issuerName,
        subject: subjectName,
        signatureAlgorithm: .ecdsaWithSHA256,
        extensions: Certificate.Extensions {
            Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil))
        },
        issuerPrivateKey: Certificate.PrivateKey(issuerKey)
    )
    return try certificateDER(certificate)
}
