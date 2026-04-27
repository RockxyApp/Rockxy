import Foundation
@testable import Rockxy
import ServiceManagement
import Testing

// MARK: - HelperManagerTests

struct HelperManagerTests {
    @Test("install disposition preserves approval-required state")
    @MainActor
    func installDispositionRequiresApproval() {
        #expect(HelperManager.installDisposition(for: .requiresApproval) == .requiresApproval)
    }

    @Test("install disposition does not re-register already enabled helpers")
    @MainActor
    func installDispositionAlreadyEnabled() {
        #expect(HelperManager.installDisposition(for: .enabled) == .alreadyEnabled)
    }

    @Test("install disposition registers when helper is absent")
    @MainActor
    func installDispositionRegistersMissingHelper() {
        #expect(HelperManager.installDisposition(for: .notRegistered) == .register)
        #expect(HelperManager.installDisposition(for: .notFound) == .register)
    }

    @Test("approval-required detection accepts SMAppService approval errors")
    @MainActor
    func approvalRequiredErrorsAreRecognized() {
        let operationNotPermitted = NSError(domain: NSOSStatusErrorDomain, code: 1)
        let userDenied = NSError(domain: NSOSStatusErrorDomain, code: kSMErrorLaunchDeniedByUser)

        #expect(HelperManager.requiresApproval(error: operationNotPermitted, serviceStatus: .notRegistered))
        #expect(HelperManager.requiresApproval(error: userDenied, serviceStatus: .notRegistered))
    }

    @Test("approval-required detection accepts requiresApproval service state")
    @MainActor
    func approvalRequiredStatusIsRecognized() {
        let unrelatedError = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)

        #expect(HelperManager.requiresApproval(error: unrelatedError, serviceStatus: .requiresApproval))
    }

    @Test("approval message stays user-facing for direct approval flows")
    @MainActor
    func approvalMessageUsesStandardPromptForApprovalState() {
        let unrelatedError = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        let message = HelperManager.approvalMessage(error: unrelatedError, serviceStatus: .requiresApproval)

        #expect(message.contains("System Settings"))
        #expect(!message.contains("stale"))
    }

    @Test("approval message explains stale helper state when registration is blocked early")
    @MainActor
    func approvalMessageExplainsEarlyRegistrationBlock() {
        let operationNotPermitted = NSError(domain: NSOSStatusErrorDomain, code: 1)
        let message = HelperManager.approvalMessage(error: operationNotPermitted, serviceStatus: .notRegistered)

        #expect(message.contains("blocked helper registration"))
        #expect(message.contains("stale Rockxy helper registrations"))
    }

    @Test("approval-required detection ignores unrelated failures")
    @MainActor
    func unrelatedErrorsDoNotLookLikeApproval() {
        let unrelatedError = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)

        #expect(!HelperManager.requiresApproval(error: unrelatedError, serviceStatus: .notRegistered))
    }

    @Test("valid helper plist passes launchd preflight validation")
    func validHelperPlistPassesValidation() throws {
        let data = try makeHelperLaunchdPlistData()

        try HelperManager.validateBundledHelperLaunchdPlistData(
            data,
            expectedLabel: TestIdentity.helperMachServiceName,
            expectedBundleProgram: expectedHelperBundleProgram,
            expectedMachServiceName: TestIdentity.helperMachServiceName
        )
    }

    @Test("helper install resources require executable helper file")
    func helperInstallResourcesRequireExecutableHelperFile() throws {
        let fixture = try makeHelperInstallResourceFixture(helperKind: .regularFile(permissions: 0o755))
        defer { try? FileManager.default.removeItem(at: fixture.temporaryDirectory) }

        try HelperManager.validateBundledHelperInstallResources(bundle: fixture.bundle)
    }

    @Test("helper install resources reject helper directory")
    func helperInstallResourcesRejectHelperDirectory() throws {
        let fixture = try makeHelperInstallResourceFixture(helperKind: .directory)
        defer { try? FileManager.default.removeItem(at: fixture.temporaryDirectory) }

        do {
            try HelperManager.validateBundledHelperInstallResources(bundle: fixture.bundle)
            Issue.record("Expected helper install resource validation to reject a helper directory")
        } catch let error as HelperManager.HelperInstallPreflightError {
            #expect(error == .missingBundledHelperBinary(path: fixture.helperBinaryURL.path))
        } catch {
            Issue.record("Unexpected helper install preflight error: \(error)")
        }
    }

    @Test("helper install resources reject non-executable helper file")
    func helperInstallResourcesRejectNonExecutableHelperFile() throws {
        let fixture = try makeHelperInstallResourceFixture(helperKind: .regularFile(permissions: 0o644))
        defer { try? FileManager.default.removeItem(at: fixture.temporaryDirectory) }

        do {
            try HelperManager.validateBundledHelperInstallResources(bundle: fixture.bundle)
            Issue.record("Expected helper install resource validation to reject a non-executable helper file")
        } catch let error as HelperManager.HelperInstallPreflightError {
            #expect(error == .missingBundledHelperBinary(path: fixture.helperBinaryURL.path))
        } catch {
            Issue.record("Unexpected helper install preflight error: \(error)")
        }
    }

    @Test("missing Label fails helper plist validation")
    func missingLabelFailsValidation() throws {
        let data = try makeHelperLaunchdPlistData(label: nil)

        do {
            try HelperManager.validateBundledHelperLaunchdPlistData(
                data,
                expectedLabel: TestIdentity.helperMachServiceName,
                expectedBundleProgram: expectedHelperBundleProgram,
                expectedMachServiceName: TestIdentity.helperMachServiceName
            )
            Issue.record("Expected helper plist validation to fail for missing Label")
        } catch let error as HelperManager.HelperPlistValidationError {
            #expect(error == .missingLabel)
        } catch {
            Issue.record("Unexpected helper plist validation error: \(error)")
        }
    }

    @Test("wrong BundleProgram fails helper plist validation")
    func wrongBundleProgramFailsValidation() throws {
        let data = try makeHelperLaunchdPlistData(bundleProgram: "Contents/MacOS/RockxyHelperTool")

        do {
            try HelperManager.validateBundledHelperLaunchdPlistData(
                data,
                expectedLabel: TestIdentity.helperMachServiceName,
                expectedBundleProgram: expectedHelperBundleProgram,
                expectedMachServiceName: TestIdentity.helperMachServiceName
            )
            Issue.record("Expected helper plist validation to fail for wrong BundleProgram")
        } catch let error as HelperManager.HelperPlistValidationError {
            #expect(error == .unexpectedBundleProgram("Contents/MacOS/RockxyHelperTool"))
        } catch {
            Issue.record("Unexpected helper plist validation error: \(error)")
        }
    }

    @Test("missing MachServices entry fails helper plist validation")
    func missingMachServicesEntryFailsValidation() throws {
        let data = try makeHelperLaunchdPlistData(machServices: [:])

        do {
            try HelperManager.validateBundledHelperLaunchdPlistData(
                data,
                expectedLabel: TestIdentity.helperMachServiceName,
                expectedBundleProgram: expectedHelperBundleProgram,
                expectedMachServiceName: TestIdentity.helperMachServiceName
            )
            Issue.record("Expected helper plist validation to fail for missing MachServices entry")
        } catch let error as HelperManager.HelperPlistValidationError {
            #expect(error == .missingMachService(TestIdentity.helperMachServiceName))
        } catch {
            Issue.record("Unexpected helper plist validation error: \(error)")
        }
    }

    @Test("disabled MachServices entry fails helper plist validation")
    func disabledMachServicesEntryFailsValidation() throws {
        let data = try makeHelperLaunchdPlistData(
            machServices: [TestIdentity.helperMachServiceName: false]
        )

        do {
            try HelperManager.validateBundledHelperLaunchdPlistData(
                data,
                expectedLabel: TestIdentity.helperMachServiceName,
                expectedBundleProgram: expectedHelperBundleProgram,
                expectedMachServiceName: TestIdentity.helperMachServiceName
            )
            Issue.record("Expected helper plist validation to fail for disabled MachServices entry")
        } catch let error as HelperManager.HelperPlistValidationError {
            #expect(error == .disabledMachService(TestIdentity.helperMachServiceName))
        } catch {
            Issue.record("Unexpected helper plist validation error: \(error)")
        }
    }

    @Test("malformed helper plist data fails validation")
    func malformedHelperPlistDataFailsValidation() {
        let malformedData = Data("not-a-plist".utf8)

        do {
            try HelperManager.validateBundledHelperLaunchdPlistData(
                malformedData,
                expectedLabel: TestIdentity.helperMachServiceName,
                expectedBundleProgram: expectedHelperBundleProgram,
                expectedMachServiceName: TestIdentity.helperMachServiceName
            )
            Issue.record("Expected helper plist validation to fail for malformed data")
        } catch let error as HelperManager.HelperPlistValidationError {
            #expect(error == .malformedPlist)
        } catch {
            Issue.record("Unexpected helper plist validation error: \(error)")
        }
    }

    @Test("helper package failure messaging guides reinstall instead of Login Items approval")
    func helperPackageFailureMessagingIsReinstallOriented() {
        let error = HelperManager.HelperInstallPreflightError.missingBundledLaunchdPlist(
            path: "/Applications/Rockxy.app/Contents/Library/LaunchDaemons/\(TestIdentity.helperPlistName)"
        )
        let message = error.localizedDescription

        #expect(message.localizedLowercase.contains("app package is incomplete"))
        #expect(message.localizedLowercase.contains("reinstall"))
        #expect(message.contains("Homebrew"))
        #expect(!message.contains("Login Items"))
        #expect(!message.contains("System Settings"))
    }

    // MARK: - Probe Error Classification

    @Test("classifyProbeError maps appSignatureInvalid")
    @MainActor
    func classifyProbeErrorAppSignature() {
        let probe = HelperManager.classifyProbeError(.appSignatureInvalid("stale build"))
        #expect(probe == .appSignatureInvalid(detail: "stale build"))
    }

    @Test("classifyProbeError maps signingIdentityMismatch")
    @MainActor
    func classifyProbeErrorSigningMismatch() {
        let probe = HelperManager.classifyProbeError(
            .signingIdentityMismatch(app: "Dev", helper: "Prod")
        )
        #expect(probe == .signingIdentityMismatch(appSigner: "Dev", helperSigner: "Prod"))
    }

    @Test("classifyProbeError maps xpcTimeout to xpcFailure")
    @MainActor
    func classifyProbeErrorTimeout() {
        let probe = HelperManager.classifyProbeError(.xpcTimeout)
        #expect(probe == .xpcFailure)
    }

    @Test("classifyProbeError maps connectionFailed to xpcFailure")
    @MainActor
    func classifyProbeErrorConnectionFailed() {
        let probe = HelperManager.classifyProbeError(.connectionFailed)
        #expect(probe == .xpcFailure)
    }

    @Test("decideRecovery returns attemptReRegistration for xpcFailure")
    @MainActor
    func decideRecoveryXpcFailure() {
        let action = HelperManager.decideRecovery(probe: .xpcFailure)
        #expect(action == .attemptReRegistration)
    }

    // MARK: - Subtype-Only Change Detection

    @Test("signing issue change without status change is detected")
    @MainActor
    func signingIssueOnlyChangeDetected() {
        let changed = HelperManager.helperStateDidChange(
            previousStatus: .signingMismatch, currentStatus: .signingMismatch,
            previousReachable: false, currentReachable: false,
            previousInfo: nil, currentInfo: nil,
            previousSigningIssue: .appSignatureInvalid(detail: "stale"),
            currentSigningIssue: .identityMismatch(appSigner: "Dev", helperSigner: "Prod")
        )
        #expect(changed == true)
    }

    @Test("identical signing issue is not a change")
    @MainActor
    func identicalSigningIssueNotChanged() {
        let changed = HelperManager.helperStateDidChange(
            previousStatus: .signingMismatch, currentStatus: .signingMismatch,
            previousReachable: false, currentReachable: false,
            previousInfo: nil, currentInfo: nil,
            previousSigningIssue: .appSignatureInvalid(detail: "stale"),
            currentSigningIssue: .appSignatureInvalid(detail: "stale")
        )
        #expect(changed == false)
    }

    // MARK: - Action Label and Warning Reason

    @Test("appSignatureInvalid produces no action label")
    @MainActor
    func appSignatureInvalidNoActionLabel() {
        let label = HelperManager.helperActionLabel(
            status: .signingMismatch,
            signingIssue: .appSignatureInvalid(detail: "stale")
        )
        #expect(label == nil)
    }

    @Test("identityMismatch produces reinstall action label")
    @MainActor
    func identityMismatchReinstallLabel() {
        let label = HelperManager.helperActionLabel(
            status: .signingMismatch,
            signingIssue: .identityMismatch(appSigner: "Dev", helperSigner: "Prod")
        )
        #expect(label == String(localized: "Reinstall"))
    }

    @Test("installedCompatible produces no action label")
    @MainActor
    func installedCompatibleNoLabel() {
        let label = HelperManager.helperActionLabel(
            status: .installedCompatible,
            signingIssue: nil
        )
        #expect(label == nil)
    }

    @Test("appSignatureInvalid warning mentions clean build")
    func appSignatureInvalidWarning() {
        let reason = HelperManager.signingMismatchWarningReason(
            issue: .appSignatureInvalid(detail: "stale")
        )
        #expect(reason.localizedLowercase.contains("clean"))
    }

    @Test("identityMismatch warning mentions reinstall")
    func identityMismatchWarning() {
        let reason = HelperManager.signingMismatchWarningReason(
            issue: .identityMismatch(appSigner: "Dev", helperSigner: "Prod")
        )
        #expect(reason.localizedLowercase.contains("reinstall"))
    }

    // MARK: - Re-registration Approval Detection

    @Test("requiresApproval recognizes kSMErrorLaunchDeniedByUser during re-registration")
    func reRegistrationApprovalDetected() {
        let deniedError = NSError(domain: NSOSStatusErrorDomain, code: kSMErrorLaunchDeniedByUser)
        #expect(HelperManager.requiresApproval(error: deniedError, serviceStatus: .requiresApproval))
    }

    @Test("approval message is user-facing for requiresApproval service state")
    func reRegistrationApprovalMessage() {
        let deniedError = NSError(domain: NSOSStatusErrorDomain, code: kSMErrorLaunchDeniedByUser)
        let message = HelperManager.approvalMessage(error: deniedError, serviceStatus: .requiresApproval)
        #expect(message.contains("System Settings"))
        #expect(message.contains("Login Items"))
    }

    // MARK: - Uninstall Registration Status Reset

    @Test("injecting notInstalled state resets registrationStatus via injectHelperStateForTests")
    @MainActor
    func uninstallResetsRegistrationStatus() {
        let manager = HelperManager.shared

        manager.injectHelperStateForTests(
            status: .installedCompatible,
            signingIssue: nil,
            isReachable: true
        )
        #expect(manager.status == .installedCompatible)

        manager.injectHelperStateForTests(
            status: .notInstalled,
            signingIssue: nil,
            isReachable: false
        )
        #expect(manager.status == .notInstalled)
        #expect(manager.isReachable == false)
        #expect(manager.installedInfo == nil)
    }
}

private let expectedHelperBundleProgram = "Contents/Library/HelperTools/RockxyHelperTool"

private enum HelperBinaryKind {
    case regularFile(permissions: Int)
    case directory
}

private struct HelperInstallResourceFixture {
    let temporaryDirectory: URL
    let helperBinaryURL: URL
    let bundle: Bundle
}

private func makeHelperInstallResourceFixture(helperKind: HelperBinaryKind) throws -> HelperInstallResourceFixture {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("rockxy-helper-fixture-\(UUID().uuidString)", isDirectory: true)
    let appBundleURL = temporaryDirectory.appendingPathComponent("Rockxy.app", isDirectory: true)
    let contentsURL = appBundleURL.appendingPathComponent("Contents", isDirectory: true)
    try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

    let info: [String: Any] = [
        "CFBundleIdentifier": TestIdentity.communityBundleIdentifier,
        "CFBundleName": "Rockxy",
        "RockxyFamilyNamespace": TestIdentity.familyNamespace,
        "RockxyHelperBundleIdentifier": TestIdentity.helperBundleIdentifier,
        "RockxyHelperMachServiceName": TestIdentity.helperMachServiceName,
        "RockxyHelperPlistName": TestIdentity.helperPlistName,
    ]
    let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try infoData.write(to: contentsURL.appendingPathComponent("Info.plist"))

    let helperBinaryURL = appBundleURL.appendingPathComponent(expectedHelperBundleProgram)
    try FileManager.default.createDirectory(at: helperBinaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    switch helperKind {
    case let .regularFile(permissions):
        try Data("helper".utf8).write(to: helperBinaryURL)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: helperBinaryURL.path)
    case .directory:
        try FileManager.default.createDirectory(at: helperBinaryURL, withIntermediateDirectories: true)
    }

    let helperPlistURL = appBundleURL
        .appendingPathComponent("Contents/Library/LaunchDaemons/\(TestIdentity.helperPlistName)")
    try FileManager.default.createDirectory(at: helperPlistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try makeHelperLaunchdPlistData().write(to: helperPlistURL)

    guard let bundle = Bundle(url: appBundleURL) else {
        throw CocoaError(.fileReadUnknown)
    }
    return HelperInstallResourceFixture(
        temporaryDirectory: temporaryDirectory,
        helperBinaryURL: helperBinaryURL,
        bundle: bundle
    )
}

private func makeHelperLaunchdPlistData(
    label: String? = TestIdentity.helperMachServiceName,
    bundleProgram: String? = expectedHelperBundleProgram,
    machServices: [String: Any]? = [TestIdentity.helperMachServiceName: true]
)
    throws -> Data
{
    var plist: [String: Any] = [:]
    if let label {
        plist["Label"] = label
    }
    if let bundleProgram {
        plist["BundleProgram"] = bundleProgram
    }
    if let machServices {
        plist["MachServices"] = machServices
    }

    return try PropertyListSerialization.data(
        fromPropertyList: plist,
        format: .xml,
        options: 0
    )
}
