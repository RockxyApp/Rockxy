import Foundation
@testable import Rockxy
import Testing

// Regression tests for `HelperConnectionBypass` in the core proxy engine layer.

// MARK: - HelperConnectionBypassTests

struct HelperConnectionBypassTests {
    @Test("bypassDomainsFailed has descriptive message")
    func bypassDomainsFailedDescription() {
        let error = HelperConnectionError.bypassDomainsFailed("service not found")
        let description = error.errorDescription ?? ""
        #expect(description.contains("bypass domains"))
        #expect(description.contains("service not found"))
    }

    @Test("bypassDomainsFailed is non-nil and non-empty")
    func bypassDomainsFailedNonEmpty() {
        let error = HelperConnectionError.bypassDomainsFailed("test reason")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.isEmpty == false)
    }

    @Test("All error cases including bypass have non-nil descriptions")
    func allCasesHaveDescriptions() {
        let cases: [HelperConnectionError] = [
            .connectionFailed,
            .proxyOverrideFailed("test"),
            .proxyRestoreFailed("test"),
            .uninstallFailed,
            .xpcTimeout,
            .certInstallFailed("test"),
            .certRemoveFailed("test"),
            .bypassDomainsFailed("test"),
            .executableRefreshUnsupported,
            .executableRefreshDeferred,
        ]

        for error in cases {
            #expect(
                error.errorDescription != nil,
                "Missing description for: \(error)"
            )
            #expect(
                error.errorDescription?.isEmpty == false,
                "Empty description for: \(error)"
            )
        }
    }
}
