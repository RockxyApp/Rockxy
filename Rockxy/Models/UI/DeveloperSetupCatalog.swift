import Foundation

// MARK: - SetupTarget Catalog

extension SetupTarget {
    static var python: SetupTarget {
        SetupTarget(
            id: .python,
            title: "Python",
            category: .runtime,
            iconName: "terminal",
            manualSupport: .availableNow,
            automationSupport: .runtimeTerminal,
            shortSummary: String(localized: "Manual Python setup is available.", bundle: RockxyLocalization.bundle),
            manualSummary: String(
                localized: "Use Rockxy's local proxy address and root certificate with your Python HTTP client.",
                bundle: RockxyLocalization.bundle
            ),
            currentSupportSummary: String(
                localized: "Rockxy ships manual setup snippets for requests, httpx, aiohttp, and urllib3.",
                bundle: RockxyLocalization.bundle
            )
        )
    }

    static var nodeJS: SetupTarget {
        SetupTarget(
            id: .nodeJS,
            title: "Node.js",
            category: .runtime,
            iconName: "server.rack",
            manualSupport: .availableNow,
            automationSupport: .runtimeTerminal,
            shortSummary: String(
                localized: "Manual Node.js setup is supported with runtime-specific snippets.",
                bundle: RockxyLocalization.bundle
            ),
            manualSummary: String(
                localized: "Point your Node.js client at Rockxy's local proxy and trust the exported root certificate.",
                bundle: RockxyLocalization.bundle
            ),
            currentSupportSummary: String(
                localized: "Rockxy ships manual snippets for axios, Node core, and got.",
                bundle: RockxyLocalization.bundle
            )
        )
    }

    static var ruby: SetupTarget {
        SetupTarget(
            id: .ruby,
            title: "Ruby",
            category: .runtime,
            iconName: "rhombus.fill",
            manualSupport: .availableNow,
            automationSupport: .runtimeTerminal,
            shortSummary: String(
                localized: "Manual Ruby setup is supported with common HTTP client examples.",
                bundle: RockxyLocalization.bundle
            ),
            manualSummary: String(
                localized: "Use Rockxy's local proxy address and exported root certificate with your Ruby client.",
                bundle: RockxyLocalization.bundle
            ),
            currentSupportSummary: String(
                localized: "Rockxy ships manual snippets for net/http, http, and Faraday.",
                bundle: RockxyLocalization.bundle
            )
        )
    }

    static var golang: SetupTarget {
        SetupTarget(
            id: .golang,
            title: "Golang",
            category: .runtime,
            iconName: "bolt.horizontal.circle",
            manualSupport: .availableNow,
            automationSupport: .runtimeTerminal,
            shortSummary: String(
                localized: "Manual Golang setup is supported for common HTTP stacks.",
                bundle: RockxyLocalization.bundle
            ),
            manualSummary: String(
                localized: "Configure Rockxy as the local proxy and load the exported root certificate in your Go client.",
                bundle: RockxyLocalization.bundle
            ),
            currentSupportSummary: String(
                localized: "Rockxy ships manual snippets for net/http and Resty.", bundle: RockxyLocalization.bundle
            )
        )
    }

    static var rust: SetupTarget {
        SetupTarget(
            id: .rust,
            title: "Rust",
            category: .runtime,
            iconName: "gearshape.2",
            manualSupport: .availableNow,
            automationSupport: .runtimeTerminal,
            shortSummary: String(
                localized: "Manual Rust setup is supported for reqwest-based traffic.",
                bundle: RockxyLocalization.bundle
            ),
            manualSummary: String(
                localized: "Configure reqwest to use Rockxy as the proxy and trust the exported root certificate.",
                bundle: RockxyLocalization.bundle
            ),
            currentSupportSummary: String(
                localized: "Rockxy ships a manual reqwest snippet for HTTPS interception.",
                bundle: RockxyLocalization.bundle
            )
        )
    }

    static var javaVMs: SetupTarget {
        SetupTarget(
            id: .javaVMs,
            title: String(localized: "Java VMs", bundle: RockxyLocalization.bundle),
            category: .runtime,
            iconName: "cup.and.saucer",
            manualSupport: .availableNow,
            automationSupport: .runtimeTerminal,
            shortSummary: String(
                localized: "Java VMs support a scoped Automatic Setup session plus a manual keystore workflow.",
                bundle: RockxyLocalization.bundle
            ),
            manualSummary: String(
                localized: """
                Import the Rockxy root CA into the active JVM's cacerts with keytool, then route traffic
                through 127.0.0.1 on Rockxy's port. This flow requires a locally installed JDK.
                """, bundle: RockxyLocalization.bundle
            ),
            currentSupportSummary: String(
                localized: """
                Automatic Setup prepares a scoped shell that sets JAVA_TOOL_OPTIONS proxy properties for the \
                JVM. For a GUI development tool, quit it and use Choose & Open Developer App so Rockxy can \
                apply the scoped environment and prepare recognized app-level proxy settings. For HTTPS \
                interception, import the Rockxy root CA into the exact JVM or IDE trust store with keytool, \
                add a Decrypt rule for the target application or host, then run the HttpClient sample to \
                confirm capture.
                """, bundle: RockxyLocalization.bundle
            )
        )
    }

    static var curl: SetupTarget {
        SetupTarget(
            id: .curl,
            title: "cURL",
            category: .runtime,
            iconName: "chevron.left.forwardslash.chevron.right",
            manualSupport: .availableNow,
            automationSupport: .runtimeTerminal,
            shortSummary: String(
                localized: "Manual cURL setup is supported with direct command and env examples.",
                bundle: RockxyLocalization.bundle
            ),
            manualSummary: String(
                localized: "Use Rockxy's local proxy address with --proxy or HTTP_PROXY / HTTPS_PROXY and trust the exported root certificate.",
                bundle: RockxyLocalization.bundle
            ),
            currentSupportSummary: String(
                localized: "Rockxy ships manual cURL examples for direct proxy flags and session environment variables.",
                bundle: RockxyLocalization.bundle
            )
        )
    }

    static var firefox: SetupTarget {
        SetupTarget(
            id: .firefox,
            title: "Firefox",
            category: .browserClient,
            iconName: "globe",
            manualSupport: .availableNow,
            automationSupport: .none,
            shortSummary: String(
                localized: "Firefox ships a manual proxy + certificate-import workflow.",
                bundle: RockxyLocalization.bundle
            ),
            manualSummary: String(
                localized: "Paste Rockxy's host and port into Firefox Network Settings, import the root certificate into the browser authority store, then load a page to confirm.",
                bundle: RockxyLocalization.bundle
            ),
            currentSupportSummary: String(
                localized: "Rockxy ships a Firefox settings snippet plus a cURL preflight step so you can confirm the proxy path before touching the browser.",
                bundle: RockxyLocalization.bundle
            )
        )
    }

    static var postman: SetupTarget {
        SetupTarget(
            id: .postman,
            title: "Postman",
            category: .browserClient,
            iconName: "paperplane",
            manualSupport: .availableNow,
            automationSupport: .none,
            shortSummary: String(
                localized: "Postman ships a manual proxy + CA configuration snippet.",
                bundle: RockxyLocalization.bundle
            ),
            manualSummary: String(
                localized: "Paste Rockxy's host and port into Postman's Proxy settings, trust the exported PEM, and send one HTTPS request to confirm capture.",
                bundle: RockxyLocalization.bundle
            ),
            currentSupportSummary: String(
                localized: "Rockxy ships a Postman settings block plus a cURL preflight so you can confirm the proxy path before touching the app.",
                bundle: RockxyLocalization.bundle
            )
        )
    }

    static var insomnia: SetupTarget {
        SetupTarget(
            id: .insomnia,
            title: "Insomnia",
            category: .browserClient,
            iconName: "moon.zzz",
            manualSupport: .availableNow,
            automationSupport: .none,
            shortSummary: String(
                localized: "Insomnia ships a manual proxy + CA configuration snippet.",
                bundle: RockxyLocalization.bundle
            ),
            manualSummary: String(
                localized: "Enable Insomnia's proxy toggle, paste Rockxy's host and port, and trust the exported PEM.",
                bundle: RockxyLocalization.bundle
            ),
            currentSupportSummary: String(
                localized: "Rockxy ships an Insomnia settings block plus a cURL preflight step so you can confirm the proxy path before sending from the app.",
                bundle: RockxyLocalization.bundle
            )
        )
    }

    static var paw: SetupTarget {
        SetupTarget(
            id: .paw,
            title: "Paw",
            category: .browserClient,
            iconName: "pawprint",
            manualSupport: .availableNow,
            automationSupport: .none,
            shortSummary: String(
                localized: "Paw ships a manual system-proxy + CA snippet.",
                bundle: RockxyLocalization.bundle
            ),
            manualSummary: String(
                localized: "Point the macOS system proxy at Rockxy (Paw follows it) and trust the exported PEM in the login keychain.",
                bundle: RockxyLocalization.bundle
            ),
            currentSupportSummary: String(
                localized: "Rockxy ships a Paw settings block plus a cURL preflight step so you can confirm the proxy path before sending from Paw.",
                bundle: RockxyLocalization.bundle
            )
        )
    }

    static var iosDevice: SetupTarget {
        SetupTarget(
            id: .iosDevice,
            title: String(localized: "iOS Device", bundle: RockxyLocalization.bundle),
            category: .device,
            iconName: "iphone.gen3",
            manualSupport: .availableNow,
            automationSupport: .none,
            shortSummary: String(
                localized: "Physical iOS devices use a manual proxy and certificate trust flow.",
                bundle: RockxyLocalization.bundle
            ),
            manualSummary: String(
                localized: """
                Set a manual HTTP proxy on the active Wi-Fi, scan the temporary Rockxy certificate link, \
                install the profile, and enable full trust under Certificate Trust Settings.
                """, bundle: RockxyLocalization.bundle
            ),
            currentSupportSummary: String(
                localized: "Rockxy can share this Mac's public Root CA over a temporary local link, while iOS still requires you to install and trust it manually on the device.",
                bundle: RockxyLocalization.bundle
            )
        )
    }

    static var iosSimulator: SetupTarget {
        SetupTarget(
            id: .iosSimulator,
            title: String(localized: "iOS Simulator", bundle: RockxyLocalization.bundle),
            category: .device,
            iconName: "ipad",
            manualSupport: .availableNow,
            automationSupport: .none,
            shortSummary: String(
                localized: "iOS Simulator uses the Mac network path with simulator-local certificate trust.",
                bundle: RockxyLocalization.bundle
            ),
            manualSummary: String(
                localized: """
                The simulator shares the Mac's network stack, so loopback is reachable; export or share \
                the Rockxy PEM, install it in the simulator, and enable full trust for it.
                """, bundle: RockxyLocalization.bundle
            ),
            currentSupportSummary: String(
                localized: "Rockxy does not drive simctl or inject the certificate into a simulator; reinstall or cold-launch the target app after the certificate is trusted.",
                bundle: RockxyLocalization.bundle
            )
        )
    }

    static var androidDevice: SetupTarget {
        SetupTarget(
            id: .androidDevice,
            title: String(localized: "Android Device", bundle: RockxyLocalization.bundle),
            category: .device,
            iconName: "iphone.gen2.radiowaves.left.and.right",
            manualSupport: .availableNow,
            automationSupport: .none,
            shortSummary: String(
                localized: "Physical Android devices use a manual proxy, user CA, and debug app trust flow.",
                bundle: RockxyLocalization.bundle
            ),
            manualSummary: String(
                localized: """
                Set a manual proxy on the active Wi-Fi, share or install the Rockxy PEM as a user CA, \
                and rely on a debug build whose network-security-config trusts user CAs.
                """, bundle: RockxyLocalization.bundle
            ),
            currentSupportSummary: String(
                localized: """
                Rockxy can share this Mac's public Root CA over a temporary local link, while Android \
                still requires manual proxy, user CA, and debug trust configuration; release builds generally will not trust user CAs.
                """, bundle: RockxyLocalization.bundle
            )
        )
    }

    static var androidEmulator: SetupTarget {
        SetupTarget(
            id: .androidEmulator,
            title: String(localized: "Android Emulator", bundle: RockxyLocalization.bundle),
            category: .device,
            iconName: "ipad.landscape",
            manualSupport: .availableNow,
            automationSupport: .none,
            shortSummary: String(
                localized: "Android Emulator uses manual proxy and user CA setup.",
                bundle: RockxyLocalization.bundle
            ),
            manualSummary: String(
                localized: """
                Inside the stock emulator the Mac is reachable at 10.0.2.2; set the emulator proxy to \
                that address plus Rockxy's port, then share or install the PEM as a user CA.
                """, bundle: RockxyLocalization.bundle
            ),
            currentSupportSummary: String(
                localized: "Rockxy provides the Dev Hub guide and temporary certificate share link; app-level TLS still depends on a debug network-security-config.",
                bundle: RockxyLocalization.bundle
            )
        )
    }

    static var tvOSWatchOS: SetupTarget {
        SetupTarget(
            id: .tvOSWatchOS,
            title: String(localized: "tvOS / watchOS", bundle: RockxyLocalization.bundle),
            category: .device,
            iconName: "appletv",
            manualSupport: .availableNow,
            automationSupport: .none,
            shortSummary: String(
                localized: "tvOS and watchOS follow the iOS device and simulator paths.",
                bundle: RockxyLocalization.bundle
            ),
            manualSummary: String(
                localized: "These platforms reuse the iOS device and simulator setup: a reachable listen address plus the Rockxy root certificate trusted inside the runtime.",
                bundle: RockxyLocalization.bundle
            ),
            currentSupportSummary: String(
                localized: "Rockxy does not automate tvOS or watchOS pairing today; use this page for the same prerequisites that apply to iOS devices and simulators.",
                bundle: RockxyLocalization.bundle
            )
        )
    }

    static var visionPro: SetupTarget {
        SetupTarget(
            id: .visionPro,
            title: String(localized: "Vision Pro", bundle: RockxyLocalization.bundle),
            category: .device,
            iconName: "visionpro",
            manualSupport: .availableNow,
            automationSupport: .none,
            shortSummary: String(
                localized: "Vision Pro follows the iOS device class of setup.",
                bundle: RockxyLocalization.bundle
            ),
            manualSummary: String(
                localized:
                "Treat Vision Pro as an iOS-class target: reach Rockxy across the local network, install the root certificate on the device, and trust it in the settings.",
                bundle: RockxyLocalization.bundle
            ),
            currentSupportSummary: String(
                localized: "Rockxy does not ship a dedicated Vision Pro pairing flow; follow the iOS Device page for the same manual steps.",
                bundle: RockxyLocalization.bundle
            )
        )
    }

    static var flutter: SetupTarget {
        SetupTarget(
            id: .flutter,
            title: "Flutter",
            category: .framework,
            iconName: "square.stack.3d.forward.dottedline",
            manualSupport: .availableNow,
            automationSupport: .none,
            shortSummary: String(
                localized: "Flutter ships manual client snippets plus the underlying iOS or Android setup guide.",
                bundle: RockxyLocalization.bundle
            ),
            manualSummary: String(
                localized: """
                Use a proxy-aware Flutter client such as HttpClient, package:http, or Dio, then keep the \
                iOS or Android device/emulator trust and proxy setup aligned with where the app runs.
                """, bundle: RockxyLocalization.bundle
            ),
            currentSupportSummary: String(
                localized: """
                Rockxy ships manual Flutter snippets and a local capture check. The check confirms the probe \
                reached Rockxy, not which device, emulator, simulator, or Dart runtime emitted it. Android \
                Emulator no-code routing through a local VPN companion is not part of this manual flow.
                """, bundle: RockxyLocalization.bundle
            )
        )
    }

    static var reactNative: SetupTarget {
        SetupTarget(
            id: .reactNative,
            title: String(localized: "React Native", bundle: RockxyLocalization.bundle),
            category: .framework,
            iconName: "cube.transparent",
            manualSupport: .availableNow,
            automationSupport: .none,
            shortSummary: String(
                localized: "React Native ships platform guidance, a fetch probe, Android debug XML, and Metro troubleshooting.",
                bundle: RockxyLocalization.bundle
            ),
            manualSummary: String(
                localized: """
                React Native traffic runs through the native iOS or Android network stack. Set up that \
                device or simulator first, then restart Metro and use the fetch probe, Android debug \
                trust XML, or Metro checklist.
                """, bundle: RockxyLocalization.bundle
            ),
            currentSupportSummary: String(
                localized: """
                Rockxy ships a React Native fetch validation probe, Android network-security-config guidance, \
                and Metro troubleshooting; proxy and certificate trust still belong to the underlying platform.
                """, bundle: RockxyLocalization.bundle
            )
        )
    }

    static var nextJS: SetupTarget {
        SetupTarget(
            id: .nextJS,
            title: String(localized: "Next.js", bundle: RockxyLocalization.bundle),
            category: .framework,
            iconName: "square.stack.3d.up",
            manualSupport: .availableNow,
            automationSupport: .none,
            shortSummary: String(
                localized: "Next.js ships a manual App Router route-handler snippet.",
                bundle: RockxyLocalization.bundle
            ),
            manualSummary: String(
                localized: """
                Add the /api/rockxy-check route handler and start next dev with NODE_USE_ENV_PROXY plus
                HTTP_PROXY / HTTPS_PROXY and NODE_EXTRA_CA_CERTS so server-side fetch trusts the Rockxy CA.
                """, bundle: RockxyLocalization.bundle
            ),
            currentSupportSummary: String(
                localized: "Rockxy ships a dynamic route handler plus the next dev env block, including NODE_USE_ENV_PROXY, so server-side fetch can then route through Rockxy.",
                bundle: RockxyLocalization.bundle
            )
        )
    }

    static var electronJS: SetupTarget {
        SetupTarget(
            id: .electronJS,
            title: "ElectronJS",
            category: .framework,
            iconName: "desktopcomputer",
            manualSupport: .availableNow,
            automationSupport: .none,
            shortSummary: String(
                localized: "ElectronJS ships manual CLI-flag + session.setProxy snippets.",
                bundle: RockxyLocalization.bundle
            ),
            manualSummary: String(
                localized: "Launch with --proxy-server and NODE_EXTRA_CA_CERTS, or call session.setProxy in the main process; both variants make Electron honor Rockxy.",
                bundle: RockxyLocalization.bundle
            ),
            currentSupportSummary: String(
                localized: "Rockxy ships one shell-launch command and one main-process session.setProxy snippet, both pointed at 127.0.0.1 on the active port.",
                bundle: RockxyLocalization.bundle
            )
        )
    }

    static var docker: SetupTarget {
        SetupTarget(
            id: .docker,
            title: "Docker",
            category: .environment,
            iconName: "shippingbox",
            manualSupport: .availableNow,
            automationSupport: .none,
            shortSummary: String(
                localized: "Docker ships a manual host.docker.internal + mounted-CA command.",
                bundle: RockxyLocalization.bundle
            ),
            manualSummary: String(
                localized: "Run one throwaway curlimages/curl container with HTTP_PROXY pointed at host.docker.internal and the PEM mounted in, then let Rockxy catch the probe.",
                bundle: RockxyLocalization.bundle
            ),
            currentSupportSummary: String(
                localized: "Rockxy ships a single docker run command that mounts the Rockxy PEM and probes capture through the local validation path.",
                bundle: RockxyLocalization.bundle
            )
        )
    }

    static let defaultPinnedTargetIDs: [SetupTarget.ID] = [.python, .nodeJS, .curl]

    static var runtimeTargets: [SetupTarget] {
        [python, nodeJS, ruby, golang, rust, javaVMs, curl]
    }

    static var browserClientTargets: [SetupTarget] {
        [firefox, postman, insomnia, paw]
    }

    static var deviceTargets: [SetupTarget] {
        [
            iosDevice,
            iosSimulator,
            androidDevice,
            androidEmulator,
            tvOSWatchOS,
            visionPro,
        ]
    }

    static var frameworkTargets: [SetupTarget] {
        [flutter, reactNative, nextJS, electronJS]
    }

    static var environmentTargets: [SetupTarget] {
        [docker]
    }

    static var allSections: [SetupTargetSection] {
        allSections(pinnedTargetIDs: Set(defaultPinnedTargetIDs))
    }

    static func target(for id: SetupTarget.ID) -> SetupTarget? {
        // Resolve a single target directly so a frequently read selection does not
        // rebuild (and re-localize) the entire catalog on every access.
        switch id {
        case .python: python
        case .nodeJS: nodeJS
        case .ruby: ruby
        case .golang: golang
        case .rust: rust
        case .javaVMs: javaVMs
        case .curl: curl
        case .firefox: firefox
        case .postman: postman
        case .insomnia: insomnia
        case .paw: paw
        case .iosDevice: iosDevice
        case .iosSimulator: iosSimulator
        case .androidDevice: androidDevice
        case .androidEmulator: androidEmulator
        case .tvOSWatchOS: tvOSWatchOS
        case .visionPro: visionPro
        case .flutter: flutter
        case .reactNative: reactNative
        case .nextJS: nextJS
        case .electronJS: electronJS
        case .docker: docker
        }
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

            let filteredTargets = categoryMatches
                ? section.targets
                : section.targets.filter { $0.matchesSearchQuery(normalizedQuery) }

            guard !filteredTargets.isEmpty else {
                return nil
            }

            return SetupTargetSection(category: section.category, targets: filteredTargets)
        }
    }

    // MARK: Private

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
}
