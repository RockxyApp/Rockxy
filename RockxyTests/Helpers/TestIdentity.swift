import Foundation
@testable import Rockxy
import Security

enum TestIdentity {
    static let familyNamespace = "com.amunx.rockxy"
    static let communityBundleIdentifier = "com.amunx.rockxy.community"
    static let helperBundleIdentifier = "com.amunx.rockxy.helper"
    static let helperMachServiceName = "com.amunx.rockxy.helper"
    static let helperPlistName = "com.amunx.rockxy.helper.plist"
    static let defaultsPrefix = communityBundleIdentifier
    static let notificationPrefix = communityBundleIdentifier
    static let logSubsystem = communityBundleIdentifier
    static let appSupportDirectoryName = communityBundleIdentifier
    static let sharedSupportDirectoryName = familyNamespace
    static let sharedCertificateLabelPrefix = "\(familyNamespace).rootCA"
    static let sharedUTTypePrefix = familyNamespace
    static let keychainProbeLabel = "\(familyNamespace).test.probe"

    static let appSettingsKeys = [
        "proxyPort",
        "autoStart",
        "recordOnLaunch",
        "automaticallySetSystemProxy",
        "onlyListenOnLocalhost",
        "listenIPv6",
        "autoSelectPort",
        "appTheme",
        "appearance.fontSize",
        "appearance.tabWidth",
        "appearance.useMonospacedFont",
        "appearance.bodyWordWrap",
        "appearance.bodyShowInvisibles",
        "appearance.bodyShowMinimap",
        "appearance.bodyScrollBeyondLastLine",
        "appearance.useAlternatingRowBackgroundColors",
        "certificate.lastExportedRootCAPath",
    ].map { "\(defaultsPrefix).\($0)" }

    static let previewTabStorageKey = "\(defaultsPrefix).previewTabs"
    static let previewTabBeautifyKey = "\(defaultsPrefix).previewAutoBeautify"
    static let headerColumnStorageKey = "\(defaultsPrefix).headerColumns"
    static let discoveredRequestHeadersKey = "\(defaultsPrefix).discoveredReqHeaders"
    static let discoveredResponseHeadersKey = "\(defaultsPrefix).discoveredResHeaders"
    static let hiddenBuiltInColumnsKey = "\(defaultsPrefix).hiddenBuiltInColumns"
    static let visibleDefaultHiddenBuiltInColumnsKey = "\(defaultsPrefix).visibleDefaultHiddenBuiltInColumns"
    static let showAlertOnQuitKey = "\(defaultsPrefix).showAlertOnQuit"
    static let recordOnLaunchKey = "\(defaultsPrefix).recordOnLaunch"
    static let autoSelectPortKey = "\(defaultsPrefix).autoSelectPort"
    static let pluginStoragePrefix = "\(defaultsPrefix).plugin"

    static let helperBackupDirectory = "/Library/Application Support/\(sharedSupportDirectoryName)"
    static let applicationSupportDirectory = "Application Support/\(appSupportDirectoryName)"
    static let rulesPathComponent = "rules.json"
    static let rootCAKeyFilename = "rootCA-key.pem"
    static let rootCABackupFilename = "rootCA-key.pem.bak"

    /// Bundle identifiers the XPC caller validator must accept. Drives cross-file
    /// assertions in `ConnectionValidatorTests`, `CallerValidationTests`, and
    /// `RockxyIdentityTests` so a change to the allowlist contract only updates one place.
    static let expectedAllowedCallerIdentifiers = [
        communityBundleIdentifier,
        familyNamespace,
    ]

    static var isRunningUnderRawXCTestTool: Bool {
        RockxyIdentity.current.appBundleIdentifier == "com.apple.dt.xctest.tool"
            || RockxyIdentity.current.displayName == "xctest"
    }

    /// True when the running test host carries an ad-hoc signature. An ad-hoc
    /// signature passes `SecCodeCheckValidity`, so a `validateAppSignature() == .valid`
    /// check alone does not establish that a certificate chain exists — ad-hoc embeds
    /// no certificates at all. Any test asserting a chain is extractable has no
    /// precondition to stand on here, which is the case for a host built with
    /// `CODE_SIGN_IDENTITY=-`.
    static var isAdHocSigned: Bool {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return false
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode
        else {
            return false
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
            let dictionary = information as? [String: Any],
            let flags = dictionary[kSecCodeInfoFlags as String] as? UInt32
        else {
            return false
        }
        return flags & UInt32(kSecCodeSignatureAdhoc) != 0
    }
}
