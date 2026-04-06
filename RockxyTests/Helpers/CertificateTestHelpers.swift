import Foundation
@testable import Rockxy

/// Shared lock ensuring CertificateStore override-based tests do not race across suites.
/// All test suites that modify `CertificateStore.keychainKeyLabelOverride` or
/// `CertificateStore.storageDirectoryOverride` must acquire this lock.
let sharedCertificateTestLock = NSLock()

/// Sets CertificateStore overrides for test isolation: test-specific Keychain label
/// and a unique temp directory for filesystem operations. Acquires the shared lock
/// to prevent concurrent override mutations across test suites.
/// Returns a cleanup closure that MUST be called (typically via `defer`).
func installSharedTestOverrides() -> (label: String, storageDir: URL, cleanup: () -> Void) {
    sharedCertificateTestLock.lock()

    let testLabel = TestIdentity.keychainProbeLabel + ".\(UUID().uuidString)"
    let testDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("RockxyTests-\(UUID().uuidString)", isDirectory: true)

    CertificateStore.keychainKeyLabelOverride = testLabel
    CertificateStore.storageDirectoryOverride = testDir

    let cleanup = {
        CertificateStore.keychainKeyLabelOverride = nil
        CertificateStore.storageDirectoryOverride = nil
        try? KeychainHelper.deletePrivateKey(label: testLabel)
        try? FileManager.default.removeItem(at: testDir)
        sharedCertificateTestLock.unlock()
    }

    return (testLabel, testDir, cleanup)
}
