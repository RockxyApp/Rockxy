import Foundation
@testable import Rockxy
import Testing

struct RockxyIdentityTests {
    // MARK: - Display Name

    @Test("displayName resolves from CFBundleDisplayName")
    func displayNameFromBundleDisplayName() {
        let identity = RockxyIdentity(infoDictionary: [
            "CFBundleDisplayName": "Rockxy",
            "CFBundleName": "FallbackName",
        ])
        #expect(identity.displayName == "Rockxy")
    }

    @Test("displayName falls back to CFBundleName")
    func displayNameFallbackToBundleName() {
        let identity = RockxyIdentity(infoDictionary: [
            "CFBundleName": "Rockxy App",
        ])
        #expect(identity.displayName == "Rockxy App")
    }

    @Test("displayName falls back to Rockxy when both keys missing")
    func displayNameFallbackToDefault() {
        let identity = RockxyIdentity(infoDictionary: [:])
        #expect(identity.displayName == "Rockxy")
    }

    // MARK: - Allowlist Parsing

    @Test("allowedCallerIdentifiers parses space-separated list")
    func allowlistParsesSpaceSeparated() {
        let identity = RockxyIdentity(infoDictionary: [
            "RockxyAllowedCallerIdentifiers": "com.a com.b com.c",
        ])
        #expect(identity.allowedCallerIdentifiers == ["com.a", "com.b", "com.c"])
    }

    @Test("Default allowlist includes both community and bare identifiers")
    func defaultAllowlist() {
        let identity = RockxyIdentity(infoDictionary: [
            "RockxyAllowedCallerIdentifiers": "com.amunx.rockxy.community com.amunx.rockxy",
        ])
        #expect(identity.allowedCallerIdentifiers.contains("com.amunx.rockxy.community"))
        #expect(identity.allowedCallerIdentifiers.contains("com.amunx.rockxy"))
    }

    @Test("Unknown identifier is not in allowlist")
    func unknownIdentifierNotInAllowlist() {
        let identity = RockxyIdentity(infoDictionary: [
            "RockxyAllowedCallerIdentifiers": "com.amunx.rockxy.community com.amunx.rockxy",
        ])
        #expect(!identity.allowedCallerIdentifiers.contains("com.evil.app"))
    }

    @Test("Single-ID allowlist contains only that identifier")
    func singleIdAllowlist() {
        let identity = RockxyIdentity(infoDictionary: [
            "RockxyAllowedCallerIdentifiers": "com.solo.app",
        ])
        #expect(identity.allowedCallerIdentifiers == ["com.solo.app"])
        #expect(!identity.allowedCallerIdentifiers.contains("com.amunx.rockxy"))
    }

    @Test("Missing allowlist key falls back to app bundle identifier")
    func allowlistFallbackToAppBundleId() {
        let identity = RockxyIdentity(infoDictionary: [:])
        #expect(identity.allowedCallerIdentifiers == ["com.amunx.rockxy"])
    }

    // MARK: - Namespace Defaults

    @Test("Missing keys resolve to expected defaults")
    func defaultValues() {
        let identity = RockxyIdentity(infoDictionary: [:])
        #expect(identity.familyNamespace == "com.amunx.rockxy")
        #expect(identity.appBundleIdentifier == "com.amunx.rockxy")
        #expect(identity.helperBundleIdentifier == "com.amunx.rockxy.helper")
        #expect(identity.helperMachServiceName == "com.amunx.rockxy.helper")
        #expect(identity.sharedCertificateLabelPrefix == "com.amunx.rockxy.rootCA")
    }

    @Test("Custom keys override defaults")
    func customValues() {
        let identity = RockxyIdentity(infoDictionary: [
            "RockxyFamilyNamespace": "com.test.custom",
            "CFBundleIdentifier": "com.test.custom.app",
        ])
        #expect(identity.familyNamespace == "com.test.custom")
        #expect(identity.appBundleIdentifier == "com.test.custom.app")
    }

    // MARK: - Live Config (TEST_HOST = real app process)

    @Test("Live displayName resolves to Rockxy")
    func liveDisplayName() {
        #expect(RockxyIdentity.current.displayName == "Rockxy")
    }

    @Test("Live familyNamespace resolves to com.amunx.rockxy")
    func liveFamilyNamespace() {
        #expect(RockxyIdentity.current.familyNamespace == "com.amunx.rockxy")
    }

    @Test("Live helperBundleIdentifier resolves to com.amunx.rockxy.helper")
    func liveHelperBundleIdentifier() {
        #expect(RockxyIdentity.current.helperBundleIdentifier == "com.amunx.rockxy.helper")
    }

    @Test("Live allowedCallerIdentifiers contains both expected IDs")
    func liveAllowedCallerIdentifiers() {
        let ids = RockxyIdentity.current.allowedCallerIdentifiers
        for expected in TestIdentity.expectedAllowedCallerIdentifiers {
            #expect(ids.contains(expected))
        }
    }

    @Test("Live appBundleIdentifier is non-empty")
    func liveAppBundleIdentifier() {
        #expect(!RockxyIdentity.current.appBundleIdentifier.isEmpty)
    }

    @Test("Live test-host appSupportDirectory uses temporary storage")
    func liveTestHostAppSupportDirectoryUsesTemporaryStorage() {
        let path = RockxyIdentity.current.appSupportDirectory()
        #expect(path.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        #expect(path.lastPathComponent == RockxyIdentity.current.appSupportDirectoryName)
    }

    @Test("Live test-host sharedSupportDirectory uses temporary storage")
    func liveTestHostSharedSupportDirectoryUsesTemporaryStorage() {
        let path = RockxyIdentity.current.sharedSupportDirectory()
        #expect(path.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        #expect(path.lastPathComponent == RockxyIdentity.current.sharedSupportDirectoryName)
    }

    // MARK: - Derived Properties

    @Test("defaultsKey prefixes correctly")
    func defaultsKeyPrefix() {
        let identity = RockxyIdentity(infoDictionary: [
            "RockxyDefaultsPrefix": "com.test",
        ])
        #expect(identity.defaultsKey("favorites") == "com.test.favorites")
    }

    @Test("notificationName uses notification prefix")
    func notificationNamePrefix() {
        let identity = RockxyIdentity(infoDictionary: [
            "RockxyNotificationPrefix": "com.test.notify",
        ])
        #expect(identity.notificationName("rulesChanged").rawValue == "com.test.notify.rulesChanged")
    }
}
