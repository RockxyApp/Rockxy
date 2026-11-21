import Foundation
import Testing

/// Pins that the helper's proxy backup and apply-debt readers go through the trust gate.
///
/// The helper target is not linked into the test target, so these read the helper sources, the
/// same approach `HelperEditionNeutralityTests` takes. The gate's behavior (wrong owner,
/// group/other writable, symlink, oversized, out-of-range port, empty service list, and a
/// legitimate owner-only file still loading) is exercised against the real
/// `ProxyBackupFileTrust.swift` by compiling it standalone; these tests keep the readers from
/// quietly going back to an unchecked `Data(contentsOf:)`.
struct HelperProxyBackupTrustWiringTests {
    // MARK: Internal

    @Test("Backup loader reads through the trust gate and validates content")
    func backupLoaderUsesTrustGate() throws {
        let source = try Self.stripped("CrashRecovery.swift")
        #expect(source.contains("ProxyBackupFileTrust.readTrustedFile(at:url)"))
        #expect(source.contains("ProxyBackupContentValidation.failure("))
        #expect(source.contains("allowsEmptyServices:index==0"))
        #expect(!source.contains("Data(contentsOf:url)"))
    }

    @Test("Backup directory creation verifies an existing directory")
    func existingBackupDirectoryIsVerified() throws {
        let source = try Self.stripped("CrashRecovery.swift")
        #expect(source.contains("ProxyBackupFileTrust.verifyDirectory(at:dir)"))
    }

    @Test("Apply-debt store reads through the trust gate and treats refusal as unreadable")
    func debtStoreUsesTrustGate() throws {
        let source = try Self.stripped("ProxyApplyDebtFileStore.swift")
        #expect(source.contains("ProxyBackupFileTrust.readTrustedFile(at:url)"))
        #expect(source.contains("ProxyBackupContentValidation.failure("))
        #expect(source.contains("ProxyBackupFileTrust.verifyDirectory(at:directory)"))
        #expect(!source.contains("Data(contentsOf:url)"))
    }

    @Test("Direct-proxy watchdog reads its backup through the trust gate as its own user")
    func watchdogUsesTrustGate() throws {
        let source = try Self.stripped("main.swift")
        #expect(source.contains("ProxyBackupFileTrust.readTrustedFile(at:backupURL,trustedOwner:geteuid())"))
        #expect(source.contains("ProxyBackupContentValidation.failure("))
        #expect(!source.contains("Data(contentsOf:"))
    }

    @Test("No helper source reads a file outside the trust gate")
    func helperHasNoUngatedFileReads() throws {
        for file in [
            "CrashRecovery.swift",
            "ProxyApplyDebtFileStore.swift",
            "main.swift",
            "HelperService.swift",
            "ProxyConfigurator.swift",
            "ProxySystemConfigurationWriter.swift",
            "IdleExitMonitor.swift",
            "HelperDelegate.swift",
            "BinaryValidator.swift"
        ] {
            let source = try Self.stripped(file)
            #expect(!source.contains("Data(contentsOf:"), "\(file) reads a file outside the trust gate")
            #expect(!source.contains("contentsOfFile:"), "\(file) reads a file outside the trust gate")
        }
    }

    // MARK: Private

    private static func stripped(_ helperFile: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        let path = url.deletingLastPathComponent()
            .appendingPathComponent("RockxyHelperTool")
            .appendingPathComponent(helperFile)
        let text = try String(contentsOf: path, encoding: .utf8)
        return text.filter { !$0.isWhitespace }
    }
}
