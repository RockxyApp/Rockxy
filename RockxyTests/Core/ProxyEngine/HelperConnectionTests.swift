import Foundation
@testable import Rockxy
import Testing

// Regression tests for `HelperConnection` in the core proxy engine layer.

// MARK: - HelperConnectionErrorTests

struct HelperConnectionErrorTests {
    @Test("connectionFailed has descriptive message")
    func connectionFailedDescription() {
        let error = HelperConnectionError.connectionFailed
        let description = error.errorDescription ?? ""
        #expect(description.contains("XPC connection"))
    }

    @Test("proxyOverrideFailed includes the reason")
    func proxyOverrideFailedDescription() {
        let error = HelperConnectionError.proxyOverrideFailed("port already in use")
        let description = error.errorDescription ?? ""
        #expect(description.contains("port already in use"))
    }

    @Test("proxyRestoreFailed includes the reason")
    func proxyRestoreFailedDescription() {
        let error = HelperConnectionError.proxyRestoreFailed("no saved settings")
        let description = error.errorDescription ?? ""
        #expect(description.contains("no saved settings"))
    }

    @Test("uninstallFailed has descriptive message")
    func uninstallFailedDescription() {
        let error = HelperConnectionError.uninstallFailed
        let description = error.errorDescription ?? ""
        #expect(description.contains("uninstall"))
    }

    @Test("xpcTimeout has descriptive message")
    func xpcTimeoutDescription() {
        let error = HelperConnectionError.xpcTimeout
        let description = error.errorDescription ?? ""
        #expect(description.contains("timed out"))
    }

    @Test("appSignatureInvalid includes detail in description")
    func appSignatureInvalidDescription() {
        let error = HelperConnectionError.appSignatureInvalid("stale build")
        let description = error.errorDescription ?? ""
        #expect(description.contains("code signature"))
        #expect(description.contains("stale build"))
    }

    @Test("signingIdentityMismatch includes signer names in description")
    func signingIdentityMismatchDescription() {
        let error = HelperConnectionError.signingIdentityMismatch(app: "Dev", helper: "Prod")
        let description = error.errorDescription ?? ""
        #expect(description.contains("Dev"))
        #expect(description.contains("Prod"))
    }

    @Test("All cases conform to LocalizedError with non-nil descriptions")
    func allCasesHaveDescriptions() {
        let cases: [HelperConnectionError] = [
            .connectionFailed,
            .proxyOverrideFailed("test"),
            .proxyRestoreFailed("test"),
            .uninstallFailed,
            .xpcTimeout,
            .appSignatureInvalid("test"),
            .signingIdentityMismatch(app: "test", helper: "test"),
        ]

        for error in cases {
            let description = error.errorDescription
            #expect(description != nil)
            #expect(description?.isEmpty == false)
        }
    }
}
