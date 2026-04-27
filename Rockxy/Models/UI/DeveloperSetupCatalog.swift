import Foundation

// MARK: - SetupTarget Catalog

extension SetupTarget {
    static let python = SetupTarget(
        id: .python,
        title: "Python",
        category: .runtime,
        iconName: "terminal",
        manualSupport: .availableNow,
        automationSupport: .runtimeTerminal,
        shortSummary: String(localized: "Manual Python setup is available."),
        manualSummary: String(
            localized: "Use Rockxy's local proxy address and root certificate with your Python HTTP client."
        ),
        currentSupportSummary: String(
            localized: "Rockxy ships manual setup snippets for requests, httpx, aiohttp, and urllib3."
        )
    )

    static let nodeJS = SetupTarget(
        id: .nodeJS,
        title: "Node.js",
        category: .runtime,
        iconName: "server.rack",
        manualSupport: .availableNow,
        automationSupport: .runtimeTerminal,
        shortSummary: String(localized: "Manual Node.js setup is supported with runtime-specific snippets."),
        manualSummary: String(
            localized: "Point your Node.js client at Rockxy's local proxy and trust the exported root certificate."
        ),
        currentSupportSummary: String(
            localized: "Rockxy ships manual snippets for axios, https, and got."
        )
    )

    static let ruby = SetupTarget(
        id: .ruby,
        title: "Ruby",
        category: .runtime,
        iconName: "rhombus.fill",
        manualSupport: .availableNow,
        automationSupport: .runtimeTerminal,
        shortSummary: String(localized: "Manual Ruby setup is supported with common HTTP client examples."),
        manualSummary: String(
            localized: "Use Rockxy's local proxy address and exported root certificate with your Ruby client."
        ),
        currentSupportSummary: String(
            localized: "Rockxy ships manual snippets for net/http, http, and Faraday."
        )
    )

    static let golang = SetupTarget(
        id: .golang,
        title: "Golang",
        category: .runtime,
        iconName: "bolt.horizontal.circle",
        manualSupport: .availableNow,
        automationSupport: .runtimeTerminal,
        shortSummary: String(localized: "Manual Golang setup is supported for common HTTP stacks."),
        manualSummary: String(
            localized: "Configure Rockxy as the local proxy and load the exported root certificate in your Go client."
        ),
        currentSupportSummary: String(
            localized: "Rockxy ships manual snippets for net/http and Resty."
        )
    )

    static let rust = SetupTarget(
        id: .rust,
        title: "Rust",
        category: .runtime,
        iconName: "gearshape.2",
        manualSupport: .availableNow,
        automationSupport: .runtimeTerminal,
        shortSummary: String(localized: "Manual Rust setup is supported for reqwest-based traffic."),
        manualSummary: String(
            localized: "Configure reqwest to use Rockxy as the proxy and trust the exported root certificate."
        ),
        currentSupportSummary: String(
            localized: "Rockxy ships a manual reqwest snippet for HTTPS interception."
        )
    )

    static let javaVMs = SetupTarget(
        id: .javaVMs,
        title: String(localized: "Java VMs"),
        category: .runtime,
        iconName: "cup.and.saucer",
        manualSupport: .availableNow,
        automationSupport: .none,
        shortSummary: String(
            localized: "Java/Kotlin ships a manual keystore + HttpClient workflow when a local JDK is installed."
        ),
        manualSummary: String(
            localized: """
            Import the Rockxy root CA into the active JVM's cacerts with keytool, then route traffic
            through 127.0.0.1 on Rockxy's port. This flow requires a locally installed JDK.
            """
        ),
        currentSupportSummary: String(
            localized: "Rockxy ships a keytool import command and a Java HttpClient sample for a manual capture check on machines with a local JDK."
        )
    )

    static let curl = SetupTarget(
        id: .curl,
        title: "cURL",
        category: .runtime,
        iconName: "chevron.left.forwardslash.chevron.right",
        manualSupport: .availableNow,
        automationSupport: .runtimeTerminal,
        shortSummary: String(localized: "Manual cURL setup is supported with direct command and env examples."),
        manualSummary: String(
            localized: "Use Rockxy's local proxy address with --proxy or HTTP_PROXY / HTTPS_PROXY and trust the exported root certificate."
        ),
        currentSupportSummary: String(
            localized: "Rockxy ships manual cURL examples for direct proxy flags and session environment variables."
        )
    )

    static let firefox = SetupTarget(
        id: .firefox,
        title: "Firefox",
        category: .browserClient,
        iconName: "globe",
        manualSupport: .availableNow,
        automationSupport: .none,
        shortSummary: String(localized: "Firefox ships a manual proxy + certificate-import workflow."),
        manualSummary: String(
            localized: "Paste Rockxy's host and port into Firefox Network Settings, import the root certificate into the browser authority store, then load a page to confirm."
        ),
        currentSupportSummary: String(
            localized: "Rockxy ships a Firefox settings snippet plus a cURL preflight step so you can confirm the proxy path before touching the browser."
        )
    )

    static let postman = SetupTarget(
        id: .postman,
        title: "Postman",
        category: .browserClient,
        iconName: "paperplane",
        manualSupport: .availableNow,
        automationSupport: .none,
        shortSummary: String(localized: "Postman ships a manual proxy + CA configuration snippet."),
        manualSummary: String(
            localized: "Paste Rockxy's host and port into Postman's Proxy settings, trust the exported PEM, and send one HTTPS request to confirm capture."
        ),
        currentSupportSummary: String(
            localized: "Rockxy ships a Postman settings block plus a cURL preflight so you can confirm the proxy path before touching the app."
        )
    )

    static let insomnia = SetupTarget(
        id: .insomnia,
        title: "Insomnia",
        category: .browserClient,
        iconName: "moon.zzz",
        manualSupport: .availableNow,
        automationSupport: .none,
        shortSummary: String(localized: "Insomnia ships a manual proxy + CA configuration snippet."),
        manualSummary: String(
            localized: "Enable Insomnia's proxy toggle, paste Rockxy's host and port, and trust the exported PEM."
        ),
        currentSupportSummary: String(
            localized: "Rockxy ships an Insomnia settings block plus a cURL preflight step so you can confirm the proxy path before sending from the app."
        )
    )

    static let paw = SetupTarget(
        id: .paw,
        title: "Paw",
        category: .browserClient,
        iconName: "pawprint",
        manualSupport: .availableNow,
        automationSupport: .none,
        shortSummary: String(localized: "Paw ships a manual system-proxy + CA snippet."),
        manualSummary: String(
            localized: "Point the macOS system proxy at Rockxy (Paw follows it) and trust the exported PEM in the login keychain."
        ),
        currentSupportSummary: String(
            localized: "Rockxy ships a Paw settings block plus a cURL preflight step so you can confirm the proxy path before sending from Paw."
        )
    )

    static let iosDevice = SetupTarget(
        id: .iosDevice,
        title: String(localized: "iOS Device"),
        category: .device,
        iconName: "iphone.gen3",
        manualSupport: .availableNow,
        automationSupport: .none,
        shortSummary: String(localized: "Physical iOS devices use a manual proxy and certificate trust flow."),
        manualSummary: String(
            localized: """
            Set a manual HTTP proxy on the active Wi-Fi, scan the temporary Rockxy certificate link, \
            install the profile, and enable full trust under Certificate Trust Settings.
            """
        ),
        currentSupportSummary: String(
            localized: "Rockxy can share this Mac's public Root CA over a temporary local link, while iOS still requires you to install and trust it manually on the device."
        )
    )

    static let iosSimulator = SetupTarget(
        id: .iosSimulator,
        title: String(localized: "iOS Simulator"),
        category: .device,
        iconName: "ipad",
        manualSupport: .availableNow,
        automationSupport: .none,
        shortSummary: String(localized: "iOS Simulator uses the Mac network path with simulator-local certificate trust."),
        manualSummary: String(
            localized: """
            The simulator shares the Mac's network stack, so loopback is reachable; export or share \
            the Rockxy PEM, install it in the simulator, and enable full trust for it.
            """
        ),
        currentSupportSummary: String(
            localized: "Rockxy does not drive simctl or inject the certificate into a simulator; reinstall or cold-launch the target app after the certificate is trusted."
        )
    )

    static let androidDevice = SetupTarget(
        id: .androidDevice,
        title: String(localized: "Android Device"),
        category: .device,
        iconName: "iphone.gen2.radiowaves.left.and.right",
        manualSupport: .availableNow,
        automationSupport: .none,
        shortSummary: String(localized: "Physical Android devices use a manual proxy, user CA, and debug app trust flow."),
        manualSummary: String(
            localized: """
            Set a manual proxy on the active Wi-Fi, share or install the Rockxy PEM as a user CA, \
            and rely on a debug build whose network-security-config trusts user CAs.
            """
        ),
        currentSupportSummary: String(
            localized: """
            Rockxy can share this Mac's public Root CA over a temporary local link, while Android \
            still requires manual proxy, user CA, and debug trust configuration; release builds generally will not trust user CAs.
            """
        )
    )

    static let androidEmulator = SetupTarget(
        id: .androidEmulator,
        title: String(localized: "Android Emulator"),
        category: .device,
        iconName: "ipad.landscape",
        manualSupport: .availableNow,
        automationSupport: .none,
        shortSummary: String(localized: "Android Emulator uses manual proxy and user CA setup."),
        manualSummary: String(
            localized: """
            Inside the stock emulator the Mac is reachable at 10.0.2.2; set the emulator proxy to \
            that address plus Rockxy's port, then share or install the PEM as a user CA.
            """
        ),
        currentSupportSummary: String(
            localized: "Rockxy provides the Dev Hub guide and temporary certificate share link; app-level TLS still depends on a debug network-security-config."
        )
    )

    static let tvOSWatchOS = SetupTarget(
        id: .tvOSWatchOS,
        title: String(localized: "tvOS / watchOS"),
        category: .device,
        iconName: "appletv",
        manualSupport: .availableNow,
        automationSupport: .none,
        shortSummary: String(localized: "tvOS and watchOS follow the iOS device and simulator paths."),
        manualSummary: String(
            localized: "These platforms reuse the iOS device and simulator setup: a reachable listen address plus the Rockxy root certificate trusted inside the runtime."
        ),
        currentSupportSummary: String(
            localized: "Rockxy does not automate tvOS or watchOS pairing today; use this page for the same prerequisites that apply to iOS devices and simulators."
        )
    )

    static let visionPro = SetupTarget(
        id: .visionPro,
        title: String(localized: "Vision Pro"),
        category: .device,
        iconName: "visionpro",
        manualSupport: .availableNow,
        automationSupport: .none,
        shortSummary: String(localized: "Vision Pro follows the iOS device class of setup."),
        manualSummary: String(
            localized: "Treat Vision Pro as an iOS-class target: reach Rockxy across the local network, install the root certificate on the device, and trust it in the settings."
        ),
        currentSupportSummary: String(
            localized: "Rockxy does not ship a dedicated Vision Pro pairing flow; follow the iOS Device page for the same manual steps."
        )
    )

    static let flutter = SetupTarget(
        id: .flutter,
        title: "Flutter",
        category: .framework,
        iconName: "square.stack.3d.forward.dottedline",
        manualSupport: .availableNow,
        automationSupport: .none,
        shortSummary: String(localized: "Flutter is available through framework guidance plus the underlying device setup."),
        manualSummary: String(
            localized: "Use a proxy-aware HTTP client such as HttpClient or dio; Rockxy then captures traffic from whichever iOS or Android target runs the app."
        ),
        currentSupportSummary: String(
            localized: "Rockxy does not configure Flutter tooling for you — the iOS or Android device/emulator page owns the real setup."
        )
    )

    static let reactNative = SetupTarget(
        id: .reactNative,
        title: String(localized: "React Native"),
        category: .framework,
        iconName: "cube.transparent",
        manualSupport: .availableNow,
        automationSupport: .none,
        shortSummary: String(localized: "React Native is available through framework guidance plus the underlying device setup."),
        manualSummary: String(
            localized: "fetch runs through the iOS or Android network stack, so fix the underlying device or emulator setup first, then restart Metro and the app."
        ),
        currentSupportSummary: String(
            localized: "Rockxy captures React Native traffic when the underlying platform trusts the root certificate; there is no dedicated framework-level flow."
        )
    )

    static let nextJS = SetupTarget(
        id: .nextJS,
        title: String(localized: "Next.js"),
        category: .framework,
        iconName: "square.stack.3d.up",
        manualSupport: .availableNow,
        automationSupport: .none,
        shortSummary: String(localized: "Next.js ships a manual App Router route-handler snippet."),
        manualSummary: String(
            localized: """
            Add the /api/rockxy-check route handler and start next dev with NODE_USE_ENV_PROXY plus
            HTTP_PROXY / HTTPS_PROXY and NODE_EXTRA_CA_CERTS so server-side fetch trusts the Rockxy CA.
            """
        ),
        currentSupportSummary: String(
            localized: "Rockxy ships a dynamic route handler plus the next dev env block, including NODE_USE_ENV_PROXY, so server-side fetch can then route through Rockxy."
        )
    )

    static let electronJS = SetupTarget(
        id: .electronJS,
        title: "ElectronJS",
        category: .framework,
        iconName: "desktopcomputer",
        manualSupport: .availableNow,
        automationSupport: .none,
        shortSummary: String(localized: "ElectronJS ships manual CLI-flag + session.setProxy snippets."),
        manualSummary: String(
            localized: "Launch with --proxy-server and NODE_EXTRA_CA_CERTS, or call session.setProxy in the main process; both variants make Electron honor Rockxy."
        ),
        currentSupportSummary: String(
            localized: "Rockxy ships one shell-launch command and one main-process session.setProxy snippet, both pointed at 127.0.0.1 on the active port."
        )
    )

    static let docker = SetupTarget(
        id: .docker,
        title: "Docker",
        category: .environment,
        iconName: "shippingbox",
        manualSupport: .availableNow,
        automationSupport: .none,
        shortSummary: String(localized: "Docker ships a manual host.docker.internal + mounted-CA command."),
        manualSummary: String(
            localized: "Run one throwaway curlimages/curl container with HTTP_PROXY pointed at host.docker.internal and the PEM mounted in, then let Rockxy catch the probe."
        ),
        currentSupportSummary: String(
            localized: "Rockxy ships a single docker run command that mounts the Rockxy PEM and probes capture against httpbin.org."
        )
    )

    static let defaultPinnedTargetIDs: [SetupTarget.ID] = [.python, .nodeJS, .curl]
    static let runtimeTargets: [SetupTarget] = [.python, .nodeJS, .ruby, .golang, .rust, .javaVMs, .curl]
    static let browserClientTargets: [SetupTarget] = [.firefox, .postman, .insomnia, .paw]
    static let deviceTargets: [SetupTarget] = [
        .iosDevice,
        .iosSimulator,
        .androidDevice,
        .androidEmulator,
        .tvOSWatchOS,
        .visionPro,
    ]
    static let frameworkTargets: [SetupTarget] = [.flutter, .reactNative, .nextJS, .electronJS]
    static let environmentTargets: [SetupTarget] = [.docker]

    private static let allTargetsByID: [SetupTarget.ID: SetupTarget] = (
        runtimeTargets +
            browserClientTargets +
            deviceTargets +
            frameworkTargets +
            environmentTargets
    ).reduce(into: [:]) { partialResult, target in
        partialResult[target.id] = target
    }

    static var allSections: [SetupTargetSection] {
        allSections(pinnedTargetIDs: Set(defaultPinnedTargetIDs))
    }

    static func target(for id: SetupTarget.ID) -> SetupTarget? {
        allTargetsByID[id]
    }

    static func targets(for ids: Set<SetupTarget.ID>) -> [SetupTarget] {
        defaultPinnedTargetIDs
            .compactMap { id in
                guard ids.contains(id) else {
                    return nil
                }
                return target(for: id)
            } +
            ids.subtracting(Set(defaultPinnedTargetIDs))
            .sorted { $0.rawValue < $1.rawValue }
            .compactMap { id in
                target(for: id)
            }
    }

    static func allSections(pinnedTargetIDs: Set<SetupTarget.ID>) -> [SetupTargetSection] {
        [
            SetupTargetSection(category: .pinned, targets: targets(for: pinnedTargetIDs)),
            SetupTargetSection(category: .runtime, targets: runtimeTargets),
            SetupTargetSection(category: .browserClient, targets: browserClientTargets),
            SetupTargetSection(category: .device, targets: deviceTargets),
            SetupTargetSection(category: .framework, targets: frameworkTargets),
            SetupTargetSection(category: .environment, targets: environmentTargets),
            SetupTargetSection(category: .savedProfile, targets: []),
        ]
    }

    static func filteredSections(
        matching rawQuery: String,
        pinnedTargetIDs: Set<SetupTarget.ID>
    )
        -> [SetupTargetSection]
    {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let sections = allSections(pinnedTargetIDs: pinnedTargetIDs)
        guard !query.isEmpty else {
            return sections
        }

        let normalizedQuery = query.localizedLowercase

        return sections.compactMap { section in
            let categoryMatches = section.category.title.localizedLowercase.contains(normalizedQuery)

            if section.category == .savedProfile {
                return categoryMatches ? section : nil
            }

            let filteredTargets = categoryMatches
                ? section.targets
                : section.targets.filter { $0.matchesSearchQuery(normalizedQuery) }

            guard !filteredTargets.isEmpty else {
                return nil
            }

            return SetupTargetSection(category: section.category, targets: filteredTargets)
        }
    }

    private func matchesSearchQuery(_ query: String) -> Bool {
        [
            title,
            shortSummary,
            manualSummary,
            currentSupportSummary,
            automationSupport.title,
        ].contains { value in
            value.localizedLowercase.contains(query)
        }
    }

    static func automationPreview(for target: SetupTarget) -> SetupAutomationPreview? {
        guard target.automationSupport.isAvailable else {
            return nil
        }

        switch target.automationSupport {
        case .none:
            return nil
        case .runtimeTerminal:
            return SetupAutomationPreview(
                title: String(localized: "Automatic Setup"),
                summary: String(
                    localized: """
                    Automatic Setup prepares a terminal session for supported runtimes.
                    It keeps the same target model, but opens a prepared shell before you run your app or script.
                    """
                ),
                primaryActionTitle: target.automationSupport.sheetPrimaryActionTitle,
                supplementaryNote: String(
                    localized: "Manual setup remains the baseline path. This preview does not replace the step-by-step workflow."
                ),
                steps: [
                    SetupAutomationStep(
                        id: "runtime",
                        title: String(localized: "Confirm the runtime target"),
                        description: String(
                            localized: "Use the current target to choose the shell and runtime behavior that Automatic Setup would prepare."
                        )
                    ),
                    SetupAutomationStep(
                        id: "access",
                        title: String(localized: "Prepare a terminal session"),
                        description: String(
                            localized: "Rockxy prepares the proxy settings, trust hints, and runtime-specific shell behavior for this target."
                        )
                    ),
                    SetupAutomationStep(
                        id: "launch",
                        title: String(localized: "Launch the prepared shell"),
                        description: String(
                            localized: "The terminal would open with the runtime session already pointed at Rockxy."
                        )
                    ),
                    SetupAutomationStep(
                        id: "validate",
                        title: String(localized: "Return to Validate"),
                        description: String(
                            localized: "After the app or script starts in that shell, come back here and confirm the first matching request appears."
                        )
                    ),
                ]
            )
        case .deviceAutomation:
            return SetupAutomationPreview(
                title: String(localized: "Automatic Device Setup"),
                summary: String(
                    localized: "This preview describes a future device-specific automation route from the same target detail."
                ),
                primaryActionTitle: target.automationSupport.sheetPrimaryActionTitle,
                supplementaryNote: String(localized: "Manual setup remains the source of truth."),
                steps: []
            )
        }
    }
}
