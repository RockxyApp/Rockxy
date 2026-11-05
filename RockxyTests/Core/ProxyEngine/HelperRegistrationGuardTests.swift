import Foundation
@testable import Rockxy
import Testing

// MARK: - HelperRegistrationGuardTests

struct HelperRegistrationGuardTests {
    @Test("a plain launch is not a test host")
    func plainLaunchIsNotATestHost() {
        #expect(!HelperRegistrationGuard.isTestHost(environment: [:], isTestFrameworkLoaded: false))
        #expect(!HelperRegistrationGuard.isTestHost(
            environment: ["PATH": "/usr/bin", "HOME": "/Users/example"],
            isTestFrameworkLoaded: false
        ))
    }

    @Test("a loaded test framework marks a test host")
    func loadedFrameworkIsATestHost() {
        #expect(HelperRegistrationGuard.isTestHost(environment: [:], isTestFrameworkLoaded: true))
    }

    @Test("each test-runner environment variable marks a test host")
    func runnerEnvironmentIsATestHost() {
        for key in HelperRegistrationGuard.testRunnerEnvironmentKeys {
            #expect(HelperRegistrationGuard.isTestHost(
                environment: [key: "/tmp/value"],
                isTestFrameworkLoaded: false
            ))
        }
    }

    @Test("an empty or blank runner variable does not mark a test host")
    func blankRunnerEnvironmentIsIgnored() {
        for key in HelperRegistrationGuard.testRunnerEnvironmentKeys {
            #expect(!HelperRegistrationGuard.isTestHost(environment: [key: ""], isTestFrameworkLoaded: false))
            #expect(!HelperRegistrationGuard.isTestHost(environment: [key: "  \n"], isTestFrameworkLoaded: false))
        }
    }

    @Test("launch arguments never disable the helper")
    func argumentsAreNotConsulted() {
        // The detection has no argument input at all, so opening "XCTest-notes.har" in a shipped
        // app cannot trip it. Pin that the signature stays environment plus framework only.
        #expect(!HelperRegistrationGuard.isTestHost(
            environment: ["CFFIXED_USER_HOME": "/Users/example"],
            isTestFrameworkLoaded: false
        ))
    }

    @Test("the decision refuses only for a test host")
    func decisionFollowsTestHost() {
        #expect(HelperRegistrationGuard.refuses(operation: "install", isTestHost: true))
        #expect(!HelperRegistrationGuard.refuses(operation: "install", isTestHost: false))
    }

    @Test("the running test process is detected as a test host")
    func currentProcessIsATestHost() {
        #expect(HelperRegistrationGuard.isCurrentProcessTestHost)
        #expect(throws: HelperRegistrationGuard.RefusedUnderTestError.self) {
            try HelperRegistrationGuard.refuseIfTestHost(operation: "install")
        }
    }

    @Test("every registration mutation is refused before touching SMAppService")
    @MainActor
    func registrationMutationsAreRefusedUnderTest() async {
        let manager = HelperManager.shared
        await #expect(throws: HelperRegistrationGuard.RefusedUnderTestError.self) {
            try await manager.performInstall()
        }
        await #expect(throws: HelperRegistrationGuard.RefusedUnderTestError.self) {
            try await manager.performUninstall()
        }
        await #expect(throws: HelperRegistrationGuard.RefusedUnderTestError.self) {
            try await manager.ensureHelperMutationCanProceed()
        }
        await #expect(throws: HelperRegistrationGuard.RefusedUnderTestError.self) {
            try await manager.install()
        }
        await #expect(throws: HelperRegistrationGuard.RefusedUnderTestError.self) {
            try await manager.forceResetRegistration()
        }
    }
}
