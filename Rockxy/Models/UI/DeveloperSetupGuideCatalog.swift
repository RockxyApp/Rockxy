import Foundation

// MARK: - SetupGuideTip

struct SetupGuideTip: Identifiable, Equatable {
    let id: String
    let title: String
    let message: String
}

// MARK: - SetupGuideContent

struct SetupGuideContent: Equatable {
    let setupTips: [SetupGuideTip]
    let validationTips: [SetupGuideTip]
    let troubleshootingTips: [SetupGuideTip]
}

// MARK: - DeveloperSetupGuideCatalog

enum DeveloperSetupGuideCatalog {
    // MARK: Internal

    static func content(for targetID: SetupTarget.ID) -> SetupGuideContent? {
        switch targetID {
        case .iosDevice:
            iosDeviceGuide()
        case .iosSimulator:
            iosSimulatorGuide()
        case .androidDevice:
            androidDeviceGuide()
        case .androidEmulator:
            androidEmulatorGuide()
        case .tvOSWatchOS:
            tvOSWatchOSGuide()
        case .visionPro:
            visionProGuide()
        case .flutter:
            flutterGuide()
        case .reactNative:
            reactNativeGuide()
        case .python,
             .nodeJS,
             .ruby,
             .golang,
             .rust,
             .curl,
             .javaVMs,
             .firefox,
             .postman,
             .insomnia,
             .paw,
             .docker,
             .electronJS,
             .nextJS:
            nil
        }
    }

    // MARK: Private

    private static func iosDeviceGuide() -> SetupGuideContent {
        SetupGuideContent(
            setupTips: [
                tip(
                    "ios-device-reachable",
                    "Make Rockxy reachable from the device",
                    "Bind the proxy to a listen address the device can reach (usually the LAN IP) and keep the Mac firewall open for that port."
                ),
                tip(
                    "ios-device-proxy",
                    "Set a manual HTTP proxy on the device",
                    "In Settings > Wi-Fi, edit the active network and set a manual HTTP proxy pointing at the Mac's LAN IP and Rockxy's port."
                ),
                tip(
                    "ios-device-cert",
                    "Scan the temporary certificate link",
                    """
                    In Developer Setup Hub, choose Share Certificate, scan the QR code in Safari, install \
                    the downloaded profile, then enable full trust under Settings > General > About > \
                    Certificate Trust Settings.
                    """
                ),
                tip(
                    "ios-device-cleanup",
                    "Clean up when debugging ends",
                    "Remove the manual Wi-Fi proxy and remove the Rockxy certificate profile from the device when you are done debugging."
                ),
            ],
            validationTips: [
                tip(
                    "ios-device-validate",
                    "Send a single HTTPS request to confirm",
                    """
                    Load an HTTPS page in Safari or run the target app's login flow once and confirm \
                    Rockxy captures the request. A VPN may bypass the Wi-Fi proxy, so disable it while validating.
                    """
                ),
            ],
            troubleshootingTips: [
                tip(
                    "ios-device-no-traffic",
                    "No traffic usually means the proxy is not set on the active Wi-Fi",
                    "Re-check the manual proxy entry on the current Wi-Fi; iOS does not use the proxy on cellular or when a VPN bypasses it."
                ),
                tip(
                    "ios-device-full-trust",
                    "Installing the profile is not enough",
                    """
                    After installing the profile, iOS still requires Full Trust under Settings > General > \
                    About > Certificate Trust Settings before HTTPS traffic can be decrypted.
                    """
                ),
                tip(
                    "ios-device-pinning",
                    "Certificate pinning blocks HTTPS interception",
                    "If the app pins its own certificates, Rockxy cannot decrypt its traffic until the app is built with pinning relaxed."
                ),
            ]
        )
    }

    private static func iosSimulatorGuide() -> SetupGuideContent {
        SetupGuideContent(
            setupTips: [
                tip(
                    "ios-sim-loopback",
                    "Loopback reaches the simulator by default",
                    "The iOS Simulator shares the Mac's network stack, so Rockxy's loopback listen address is typically reachable without LAN configuration."
                ),
                tip(
                    "ios-sim-proxy",
                    "Prefer the macOS system proxy for simulator apps",
                    "Set the macOS system proxy to Rockxy so simulator apps inherit it; simctl does not have a first-party proxy switch today."
                ),
                tip(
                    "ios-sim-cert",
                    "Trust the root certificate inside the simulator",
                    """
                    Use Share Certificate in Developer Setup Hub or export the Rockxy PEM, install it in \
                    the simulator, then enable full trust under Settings > General > About > Certificate Trust Settings.
                    """
                ),
                tip(
                    "ios-sim-simctl",
                    "Command-line install remains manual",
                    "If you prefer Terminal, export the public PEM and run xcrun simctl keychain <udid> add-root-cert <path-to-pem> for a prepared simulator."
                ),
            ],
            validationTips: [
                tip(
                    "ios-sim-validate",
                    "Reinstall the app after the certificate is trusted",
                    "iOS caches trust decisions per app launch; rebuild or cold-launch the target app once the certificate is trusted, then re-run its HTTPS flow."
                ),
            ],
            troubleshootingTips: [
                tip(
                    "ios-sim-erase",
                    "Stale simulator state can hide certificate trust",
                    "If HTTPS still fails, use Device > Erase All Content and Settings on the simulator and reinstall the certificate before retrying."
                ),
            ]
        )
    }

    private static func androidDeviceGuide() -> SetupGuideContent {
        SetupGuideContent(
            setupTips: [
                tip(
                    "android-device-reachable",
                    "Make Rockxy reachable from the device",
                    "Bind the proxy to a listen address the device can reach (usually the LAN IP) and ensure the Mac firewall allows connections on Rockxy's port."
                ),
                tip(
                    "android-device-proxy",
                    "Set a manual proxy on the active Wi-Fi",
                    "Long-press the connected Wi-Fi, choose Modify, and enter a manual proxy with the Mac's LAN IP and Rockxy's port."
                ),
                tip(
                    "android-device-user-ca",
                    "Install the certificate as a user CA",
                    "Copy the Rockxy PEM to the device and install it under Settings > Security > Encryption & credentials > Install a certificate > CA certificate."
                ),
                tip(
                    "android-device-nsc",
                    "Most apps do not trust user CAs by default",
                    "From Android 7, apps only trust user CAs when their network-security-config opts in; you usually need a debug build that does so."
                ),
            ],
            validationTips: [
                tip(
                    "android-device-validate",
                    "Open an HTTPS page in Chrome first",
                    "Chrome trusts user CAs, so loading an HTTPS page there confirms the proxy and certificate are wired correctly before you debug app traffic."
                ),
            ],
            troubleshootingTips: [
                tip(
                    "android-device-nsc-error",
                    "SSL failures usually trace to network-security-config",
                    "If an app still fails TLS, its network-security-config probably does not trust user CAs; a debug build with a relaxed config is required."
                ),
            ]
        )
    }

    private static func androidEmulatorGuide() -> SetupGuideContent {
        SetupGuideContent(
            setupTips: [
                tip(
                    "android-emu-host",
                    "Reach the host via 10.0.2.2",
                    "Inside the stock Android emulator, the Mac is reachable at 10.0.2.2, so set the emulator proxy to 10.0.2.2 and Rockxy's port."
                ),
                tip(
                    "android-emu-proxy",
                    "Configure the proxy on the emulator",
                    "Use Extended Controls > Settings > Proxy, or start the emulator with -http-proxy, so the Android system picks up Rockxy."
                ),
                tip(
                    "android-emu-user-ca",
                    "Install the certificate inside the emulator",
                    "Copy the Rockxy PEM into the emulator and install it as a user CA under Settings > Security > Encryption & credentials."
                ),
                tip(
                    "android-emu-nsc",
                    "Apps still need network-security-config to trust it",
                    "Production emulator images behave like real devices: apps only trust user CAs when their network-security-config allows it."
                ),
            ],
            validationTips: [
                tip(
                    "android-emu-validate",
                    "Try Chrome before the target app",
                    "Open an HTTPS page in Chrome first to confirm the proxy and certificate are correct before debugging app traffic."
                ),
            ],
            troubleshootingTips: [
                tip(
                    "android-emu-system-cert",
                    "System certificate installation requires a writable image",
                    "Rockxy does not automate system-level certificate installation; if you need it, use a writable emulator image and the standard adb remount flow yourself."
                ),
            ]
        )
    }

    private static func tvOSWatchOSGuide() -> SetupGuideContent {
        SetupGuideContent(
            setupTips: [
                tip(
                    "tvos-ios-class",
                    "Treat these as iOS-class devices",
                    "tvOS and watchOS reuse the iOS device or simulator path: Rockxy must be reachable and the root certificate must be trusted on the runtime."
                ),
                tip(
                    "tvos-simulator",
                    "Prefer the simulator for watchOS and tvOS",
                    "The Xcode simulators for watchOS and tvOS share the Mac's networking, so Rockxy's loopback is usually reachable without LAN setup."
                ),
                tip(
                    "tvos-device",
                    "Physical devices need LAN reachability and manual proxy",
                    "For a real Apple TV or Apple Watch, use a reachable LAN address and set the manual HTTP proxy in the device settings where available."
                ),
            ],
            validationTips: [
                tip(
                    "tvos-validate",
                    "Trigger a single HTTPS request",
                    "Run one known HTTPS flow from the app or system UI and confirm Rockxy captures it before debugging deeper flows."
                ),
            ],
            troubleshootingTips: [
                tip(
                    "tvos-limitations",
                    "Rockxy does not automate tvOS or watchOS pairing",
                    "There is no dedicated device-pairing workflow today; treat this page as honest guidance rather than a one-click setup."
                ),
            ]
        )
    }

    private static func visionProGuide() -> SetupGuideContent {
        SetupGuideContent(
            setupTips: [
                tip(
                    "vision-ios-class",
                    "Treat Vision Pro as an iOS-class device",
                    "Apple's headset follows the iOS device path: reach Rockxy across the local network and install the root certificate on the device."
                ),
                tip(
                    "vision-proxy",
                    "Set a manual HTTP proxy on the active Wi-Fi",
                    "Edit the current Wi-Fi network and enter a manual HTTP proxy pointing at the Mac's LAN IP and Rockxy's port."
                ),
                tip(
                    "vision-cert",
                    "Install and trust the Rockxy certificate",
                    "Deliver the PEM to the device, install it as a profile, then enable full trust under the certificate trust settings."
                ),
            ],
            validationTips: [
                tip(
                    "vision-validate",
                    "Trigger a known HTTPS flow once",
                    "Load an HTTPS page or run the app's login flow and confirm Rockxy captures the request before you debug deeper."
                ),
            ],
            troubleshootingTips: [
                tip(
                    "vision-limits",
                    "Vision Pro has no dedicated Rockxy workflow yet",
                    "This row exists for honest guidance; do not expect one-click pairing or automated certificate installation for the headset today."
                ),
            ]
        )
    }

    private static func flutterGuide() -> SetupGuideContent {
        SetupGuideContent(
            setupTips: [
                tip(
                    "flutter-underlying",
                    "Set up the underlying device or emulator first",
                    "Flutter inherits the iOS or Android setup path, so make sure that target can reach Rockxy and trust the root certificate before adding framework code."
                ),
                tip(
                    "flutter-client",
                    "Choose a proxy-aware HTTP client",
                    "Pick an HTTP client (for example HttpClient or dio) where you can set a proxy and a trusted certificate, not one that ignores the system proxy."
                ),
                tip(
                    "flutter-hot-reload",
                    "Full restart beats hot reload after proxy changes",
                    "Hot reload does not always pick up new network settings; do a full restart of the Flutter app after you change the proxy or certificate trust."
                ),
            ],
            validationTips: [
                tip(
                    "flutter-validate",
                    "Send one known HTTPS request from the app",
                    "Call one predictable HTTPS endpoint from your Flutter code and confirm Rockxy captures it before you debug broader flows."
                ),
            ],
            troubleshootingTips: [
                tip(
                    "flutter-no-proxy",
                    "Some HTTP clients bypass the system proxy",
                    "If Rockxy sees nothing, verify the HTTP client you use respects the platform proxy or accepts explicit proxy configuration."
                ),
            ]
        )
    }

    private static func reactNativeGuide() -> SetupGuideContent {
        SetupGuideContent(
            setupTips: [
                tip(
                    "rn-underlying",
                    "Set up the underlying iOS or Android target first",
                    "React Native traffic flows through the native iOS or Android network stack, so Rockxy must already work for that device or emulator."
                ),
                tip(
                    "rn-metro",
                    "Restart Metro and the app after proxy changes",
                    "Stop Metro, change the system proxy and certificate trust, then restart the bundler and the app so the networking layer picks up the new settings."
                ),
                tip(
                    "rn-fetch",
                    "Fetch uses the platform stack",
                    "The global fetch respects the iOS or Android proxy and certificate trust; if it still fails, the problem is almost always at the platform layer."
                ),
            ],
            validationTips: [
                tip(
                    "rn-validate",
                    "Trigger one known HTTPS request",
                    "Call one predictable HTTPS endpoint from your React Native code and confirm Rockxy captures it before you debug deeper flows."
                ),
            ],
            troubleshootingTips: [
                tip(
                    "rn-release",
                    "Release builds may not trust user CAs",
                    "On Android, release builds typically do not trust user CAs; validate with a debug build whose network-security-config allows them."
                ),
            ]
        )
    }

    private static func tip(
        _ id: String,
        _ title: String.LocalizationValue,
        _ message: String.LocalizationValue
    ) -> SetupGuideTip {
        SetupGuideTip(
            id: id,
            title: String(localized: title),
            message: String(localized: message)
        )
    }
}
