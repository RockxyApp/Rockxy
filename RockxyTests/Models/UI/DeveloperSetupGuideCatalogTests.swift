import Foundation
@testable import Rockxy
import Testing

/// Support-truth tests for Developer Setup Hub copy.
///
/// These tests pin concrete, practical landmarks in the catalog and guide text
/// so vague placeholder language does not silently re-enter the hub. If any
/// assertion fails, either the copy drifted into marketing-speak or the
/// underlying platform guidance changed and the landmark needs to move with it.
struct DeveloperSetupGuideCatalogTests {
    // MARK: - Catalog landmarks for guide-backed targets

    @Test("iOS Device copy names the Certificate Trust Settings step")
    func iosDeviceCatalogCopyIsSpecific() {
        let summary = SetupTarget.iosDevice.manualSummary

        #expect(summary.contains("manual HTTP proxy"))
        #expect(summary.contains("Certificate Trust Settings"))
    }

    @Test("Device and app-stack targets expose certificate sharing in Dev Hub")
    func deviceTargetsExposeCertificateSharing() {
        let shareTargets: [SetupTarget] = [
            .iosDevice,
            .iosSimulator,
            .androidDevice,
            .androidEmulator,
            .tvOSWatchOS,
            .visionPro,
            .flutter,
            .reactNative,
        ]

        for target in shareTargets {
            #expect(target.supportsCertificateSharing, "\(target.id.rawValue) should expose Dev Hub certificate sharing")
        }

        #expect(!SetupTarget.python.supportsCertificateSharing)
        #expect(!SetupTarget.firefox.supportsCertificateSharing)
    }

    @Test("Guide-backed Dev Hub targets advertise available manual support")
    func guideBackedDevHubTargetsAdvertiseAvailableManualSupport() {
        let guideBackedTargets: [SetupTarget] = [
            .iosDevice,
            .iosSimulator,
            .androidDevice,
            .androidEmulator,
            .tvOSWatchOS,
            .visionPro,
            .flutter,
            .reactNative,
        ]

        for target in guideBackedTargets {
            #expect(
                target.manualSupport == .availableNow,
                "\(target.id.rawValue) should show Available now in the Dev Hub sidebar"
            )
        }
    }

    @Test("Current Dev Hub catalog has no guide-only sidebar targets")
    func currentDevHubCatalogHasNoGuideOnlySidebarTargets() {
        let uniqueTargets = Dictionary(
            SetupTarget.allSections.flatMap(\.targets).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for target in uniqueTargets.values {
            #expect(
                target.manualSupport != .guideOnly,
                "\(target.id.rawValue) should not show Guide only in the Dev Hub sidebar"
            )
        }
    }

    @Test("iOS Simulator copy mentions loopback reachability and PEM install")
    func iosSimulatorCatalogCopyIsSpecific() {
        let summary = SetupTarget.iosSimulator.manualSummary

        #expect(summary.contains("loopback"))
        #expect(summary.contains("PEM"))
    }

    @Test("Android Device copy calls out user CA + network-security-config")
    func androidDeviceCatalogCopyIsSpecific() {
        let summary = SetupTarget.androidDevice.manualSummary
        let currentSupport = SetupTarget.androidDevice.currentSupportSummary

        #expect(summary.contains("user CA"))
        #expect(summary.contains("network-security-config"))
        #expect(currentSupport.contains("release builds"))
    }

    @Test("Android Emulator copy pins 10.0.2.2 host guidance")
    func androidEmulatorCatalogCopyIsSpecific() {
        let summary = SetupTarget.androidEmulator.manualSummary

        #expect(summary.contains("10.0.2.2"))
        #expect(summary.contains("user CA"))
    }

    @Test("Vision Pro copy points at iOS Device instead of promising its own workflow")
    func visionProCatalogCopyIsHonest() {
        let currentSupport = SetupTarget.visionPro.currentSupportSummary

        #expect(currentSupport.contains("iOS Device"))
        #expect(currentSupport.contains("pairing flow"))
    }

    @Test("Flutter copy names a proxy-aware client instead of generic promises")
    func flutterCatalogCopyIsSpecific() {
        let summary = SetupTarget.flutter.manualSummary

        #expect(summary.contains("proxy-aware"))
        #expect(summary.contains("dio") || summary.contains("HttpClient"))
    }

    @Test("React Native copy points at the underlying iOS or Android stack")
    func reactNativeCatalogCopyIsSpecific() {
        let summary = SetupTarget.reactNative.manualSummary

        #expect(summary.contains("fetch"))
        #expect(summary.contains("iOS") || summary.contains("Android"))
        #expect(summary.contains("Metro"))
    }

    // MARK: - Catalog landmarks for manual-snippet availableNow targets

    @Test("Manual-snippet runtime and GUI client targets advertise availableNow manual support")
    func promotedTargetsAdvertiseAvailableNow() {
        let manualSnippetTargets: [SetupTarget] = [
            .javaVMs,
            .firefox,
            .postman,
            .insomnia,
            .paw,
            .docker,
            .electronJS,
            .nextJS,
        ]
        for target in manualSnippetTargets {
            #expect(
                target.manualSupport == .availableNow,
                "\(target.id.rawValue) must remain availableNow for the manual snippet path"
            )
        }
    }

    @Test("Firefox currentSupportSummary references the cURL preflight step")
    func firefoxSupportCopyIsConcrete() {
        let currentSupport = SetupTarget.firefox.currentSupportSummary

        #expect(currentSupport.contains("Firefox settings snippet"))
        #expect(currentSupport.contains("cURL preflight"))
    }

    @Test("Docker currentSupportSummary references the docker run probe against httpbin")
    func dockerSupportCopyIsConcrete() {
        let currentSupport = SetupTarget.docker.currentSupportSummary

        #expect(currentSupport.contains("docker run"))
        #expect(currentSupport.contains("httpbin.org"))
    }

    @Test("Electron currentSupportSummary mentions both the CLI flag and session.setProxy variants")
    func electronSupportCopyIsConcrete() {
        let currentSupport = SetupTarget.electronJS.currentSupportSummary

        #expect(currentSupport.contains("shell-launch command"))
        #expect(currentSupport.contains("session.setProxy"))
    }

    @Test("Next.js currentSupportSummary references the route handler + env vars")
    func nextJSSupportCopyIsConcrete() {
        let currentSupport = SetupTarget.nextJS.currentSupportSummary

        #expect(currentSupport.contains("route handler"))
        #expect(currentSupport.contains("next dev"))
        #expect(currentSupport.contains("NODE_USE_ENV_PROXY"))
    }

    @Test("Java currentSupportSummary references keytool + HttpClient")
    func javaSupportCopyIsConcrete() {
        let currentSupport = SetupTarget.javaVMs.currentSupportSummary

        #expect(currentSupport.contains("keytool"))
        #expect(currentSupport.contains("HttpClient"))
    }

    // MARK: - Guide catalog coverage

    @Test("Guide catalog covers every guide-backed device + framework target")
    func guideCatalogCoversEveryGuideBackedTarget() {
        let guideBacked: [SetupTarget.ID] = [
            .iosDevice,
            .iosSimulator,
            .androidDevice,
            .androidEmulator,
            .tvOSWatchOS,
            .visionPro,
            .flutter,
            .reactNative,
        ]

        for targetID in guideBacked {
            let guide = DeveloperSetupGuideCatalog.content(for: targetID)
            #expect(guide != nil, "\(targetID.rawValue) guide must not be nil")
            #expect(guide?.setupTips.isEmpty == false, "\(targetID.rawValue) needs setup tips")
            #expect(guide?.validationTips.isEmpty == false, "\(targetID.rawValue) needs validation tips")
            #expect(
                guide?.troubleshootingTips.isEmpty == false,
                "\(targetID.rawValue) needs troubleshooting tips"
            )
        }
    }

    @Test("Manual-snippet targets never return a guide-only content bundle")
    func guideCatalogSkipsValidatedTargets() {
        let manualSnippetTargets: [SetupTarget.ID] = [
            .python, .nodeJS, .ruby, .golang, .rust, .curl,
            .javaVMs, .firefox, .postman, .insomnia, .paw,
            .docker, .electronJS, .nextJS,
        ]

        for targetID in manualSnippetTargets {
            #expect(
                DeveloperSetupGuideCatalog.content(for: targetID) == nil,
                "\(targetID.rawValue) should use the manual snippet path, not the guide catalog"
            )
        }
    }

    // MARK: - Remaining guide catalog landmarks

    @Test("Android Emulator guide pins the 10.0.2.2 host and network-security-config warning")
    func androidEmulatorGuidePinsKeyLandmarks() throws {
        let guide = try #require(DeveloperSetupGuideCatalog.content(for: .androidEmulator))

        #expect(
            guide.setupTips.contains(where: { $0.message.contains("10.0.2.2") }),
            "Emulator guide must mention 10.0.2.2"
        )
        #expect(
            guide.setupTips.contains(where: { $0.message.contains("network-security-config") }),
            "Emulator guide must mention network-security-config"
        )
    }

    @Test("iOS Simulator guide explains that apps must be cold-launched after trust changes")
    func iosSimulatorGuideCallsOutRelaunchSemantics() throws {
        let guide = try #require(DeveloperSetupGuideCatalog.content(for: .iosSimulator))

        let anyTipMentionsRelaunch = (guide.setupTips + guide.validationTips).contains { tip in
            let lowercase = tip.message.lowercased()
            return lowercase.contains("reinstall") || lowercase.contains("cold-launch") || lowercase
                .contains("relaunch")
        }
        #expect(anyTipMentionsRelaunch, "Simulator guide must call out relaunch / cold-launch / reinstall")
    }

    @Test("iOS guides point certificate sharing at Developer Setup Hub")
    func iosGuidesUseDeveloperSetupHubShareAction() throws {
        let deviceGuide = try #require(DeveloperSetupGuideCatalog.content(for: .iosDevice))
        let simulatorGuide = try #require(DeveloperSetupGuideCatalog.content(for: .iosSimulator))
        let combinedTips = deviceGuide.setupTips + simulatorGuide.setupTips

        #expect(combinedTips.contains(where: { $0.message.contains("Developer Setup Hub") }))
        #expect(combinedTips.contains(where: { $0.message.contains("Share Certificate") }))
        #expect(!combinedTips.contains(where: { $0.message.contains("certificate panel") }))
    }

    @Test("tvOS / watchOS + Vision Pro guides explicitly defer to the iOS paths")
    func iosClassGuidesDeferToiOSPath() throws {
        let tvOS = try #require(DeveloperSetupGuideCatalog.content(for: .tvOSWatchOS))
        let vision = try #require(DeveloperSetupGuideCatalog.content(for: .visionPro))

        #expect(tvOS.setupTips.contains(where: { $0.message.contains("iOS") }))
        #expect(vision.setupTips.contains(where: { $0.message.contains("iOS") }))
    }
}
