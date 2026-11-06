import Foundation

// MARK: - SetupTargetCategory

enum SetupTargetCategory: String, CaseIterable, Identifiable {
    case pinned
    case runtime
    case browserClient
    case device
    case framework
    case environment

    // MARK: Internal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .pinned:
            String(localized: "Pinned", bundle: RockxyLocalization.bundle)
        case .runtime:
            String(localized: "Runtimes", bundle: RockxyLocalization.bundle)
        case .browserClient:
            String(localized: "Browsers & Clients", bundle: RockxyLocalization.bundle)
        case .device:
            String(localized: "Devices", bundle: RockxyLocalization.bundle)
        case .framework:
            String(localized: "Frameworks", bundle: RockxyLocalization.bundle)
        case .environment:
            String(localized: "Environments", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - SetupTargetSection

struct SetupTargetSection: Identifiable, Equatable {
    let category: SetupTargetCategory
    let targets: [SetupTarget]

    var id: String {
        category.id
    }
}

// MARK: - SetupSupportStatus

enum SetupSupportStatus: String, Equatable {
    case availableNow
    case guideOnly

    // MARK: Internal

    var title: String {
        switch self {
        case .availableNow:
            String(localized: "Available now", bundle: RockxyLocalization.bundle)
        case .guideOnly:
            String(localized: "Guide only", bundle: RockxyLocalization.bundle)
        }
    }

    var bannerTitle: String {
        switch self {
        case .availableNow:
            String(localized: "Setup guide available", bundle: RockxyLocalization.bundle)
        case .guideOnly:
            String(localized: "Guide-only target", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - SetupAutomationSupport

enum SetupAutomationSupport: String, Equatable {
    case none
    case runtimeTerminal

    // MARK: Internal

    var title: String {
        switch self {
        case .none:
            String(localized: "Manual Setup", bundle: RockxyLocalization.bundle)
        case .runtimeTerminal:
            String(localized: "Automatic Setup", bundle: RockxyLocalization.bundle)
        }
    }

    var badgeTitle: String {
        switch self {
        case .none:
            String(localized: "Manual Setup", bundle: RockxyLocalization.bundle)
        case .runtimeTerminal:
            String(localized: "Automatic Setup", bundle: RockxyLocalization.bundle)
        }
    }

    var isAvailable: Bool {
        self != .none
    }

    var entryActionTitle: String {
        switch self {
        case .none:
            String(localized: "Use Manual Setup", bundle: RockxyLocalization.bundle)
        case .runtimeTerminal:
            String(localized: "Automatic Setup…", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - SetupDetailTab

enum SetupDetailTab: String, CaseIterable, Identifiable, Hashable {
    case overview
    case setup
    case snippets
    case validate
    case troubleshooting

    // MARK: Internal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .overview:
            String(localized: "Overview", bundle: RockxyLocalization.bundle)
        case .setup:
            String(localized: "Guide", bundle: RockxyLocalization.bundle)
        case .snippets:
            String(localized: "Snippets", bundle: RockxyLocalization.bundle)
        case .validate:
            String(localized: "Check", bundle: RockxyLocalization.bundle)
        case .troubleshooting:
            String(localized: "Help", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - SetupActionKind

enum SetupActionKind: Equatable {
    case verifyProxy
    case openCertificate
    case copySnippet
    case runValidation
}

// MARK: - SetupModeSelection

enum SetupModeSelection: String, CaseIterable, Identifiable, Equatable {
    case manual
    case automatic

    // MARK: Internal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .manual:
            String(localized: "Manual Setup", bundle: RockxyLocalization.bundle)
        case .automatic:
            String(localized: "Automatic Setup", bundle: RockxyLocalization.bundle)
        }
    }

    var systemImage: String {
        switch self {
        case .manual:
            "list.bullet.rectangle"
        case .automatic:
            "bolt.fill"
        }
    }
}

// MARK: - SetupModeActionState

struct SetupModeActionState: Equatable {
    // MARK: Lifecycle

    init(target: SetupTarget) {
        preferredMode = target.automationSupport.isAvailable ? .automatic : .manual
        manualTitle = String(localized: "Manual Setup", bundle: RockxyLocalization.bundle)
        manualCaption = String(
            localized: "Follow the proxy, certificate, snippet, device, or runtime guide.",
            bundle: RockxyLocalization.bundle
        )
        automaticTitle = String(localized: "Automatic Setup", bundle: RockxyLocalization.bundle)
        isAutomaticEnabled = target.automationSupport.isAvailable
        automaticCaption = target.automationSupport.isAvailable
            ? String(
                localized: "Open a scoped Rockxy-prepared session for this target.",
                bundle: RockxyLocalization.bundle
            )
            : String(
                localized: "Automatic Setup applies to terminal runtimes. Use Manual Setup for this target.",
                bundle: RockxyLocalization.bundle
            )
    }

    // MARK: Internal

    let preferredMode: SetupModeSelection
    let manualTitle: String
    let manualCaption: String
    let automaticTitle: String
    let automaticCaption: String
    let isAutomaticEnabled: Bool
}

// MARK: - SetupIssue

enum SetupIssue: String, CaseIterable, Equatable, Identifiable {
    case runtimeNotInstalled
    case proxyStopped
    case recordingPaused
    case certificateNotTrusted
    case certificateExportUnavailable
    case deviceProxyUnreachable
    case noTrafficDetected
    case localProbeUnavailable
    case localProbeNotCaptured
    case allowListBlockedValidation
    case wrongSnippetChosen
    case manualValidationOnly
    case targetIsGuideOnly

    // MARK: Internal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .runtimeNotInstalled:
            String(localized: "Runtime not installed", bundle: RockxyLocalization.bundle)
        case .proxyStopped:
            String(localized: "Proxy stopped", bundle: RockxyLocalization.bundle)
        case .recordingPaused:
            String(localized: "Recording paused", bundle: RockxyLocalization.bundle)
        case .certificateNotTrusted:
            String(localized: "Certificate not trusted", bundle: RockxyLocalization.bundle)
        case .certificateExportUnavailable:
            String(localized: "Certificate export/setup incomplete", bundle: RockxyLocalization.bundle)
        case .deviceProxyUnreachable:
            String(localized: "Device proxy unreachable", bundle: RockxyLocalization.bundle)
        case .noTrafficDetected:
            String(localized: "No traffic detected", bundle: RockxyLocalization.bundle)
        case .localProbeUnavailable:
            String(localized: "Local probe unavailable", bundle: RockxyLocalization.bundle)
        case .localProbeNotCaptured:
            String(localized: "Local probe not captured", bundle: RockxyLocalization.bundle)
        case .allowListBlockedValidation:
            String(localized: "Allow List hides the validation probe", bundle: RockxyLocalization.bundle)
        case .wrongSnippetChosen:
            String(localized: "Wrong snippet chosen", bundle: RockxyLocalization.bundle)
        case .manualValidationOnly:
            String(localized: "Manual validation only", bundle: RockxyLocalization.bundle)
        case .targetIsGuideOnly:
            String(localized: "Guide-only target", bundle: RockxyLocalization.bundle)
        }
    }

    var message: String {
        switch self {
        case .runtimeNotInstalled:
            String(
                localized: "Install the selected runtime, toolchain, or client on this Mac before validating this manual flow.",
                bundle: RockxyLocalization.bundle
            )
        case .proxyStopped:
            String(
                localized: "Start the Rockxy proxy before validating captured traffic.",
                bundle: RockxyLocalization.bundle
            )
        case .recordingPaused:
            String(
                localized: "Resume recording so new requests appear in the traffic list.",
                bundle: RockxyLocalization.bundle
            )
        case .certificateNotTrusted:
            String(
                localized: "Install and trust the Rockxy root certificate before validating HTTPS traffic.",
                bundle: RockxyLocalization.bundle
            )
        case .certificateExportUnavailable:
            String(
                localized: "Generate and export the Rockxy root certificate so the selected client can trust it.",
                bundle: RockxyLocalization.bundle
            )
        case .deviceProxyUnreachable:
            String(
                localized: """
                Physical devices cannot reach Rockxy while the proxy only listens on localhost. \
                Turn off Only listen on localhost in Settings > General > Advanced Proxy Setting…, \
                restart the proxy, and use the Device Proxy host plus active port.
                """, bundle: RockxyLocalization.bundle
            )
        case .noTrafficDetected:
            String(
                localized: "Run the test request again and make sure it points at the Rockxy proxy port.",
                bundle: RockxyLocalization.bundle
            )
        case .localProbeUnavailable:
            String(
                localized: "Rockxy could not start the local validation probe. Reopen Developer Setup, then try again.",
                bundle: RockxyLocalization.bundle
            )
        case .localProbeNotCaptured:
            String(
                localized: "Run the local probe again and make sure the selected runtime sends it through Rockxy's proxy port.",
                bundle: RockxyLocalization.bundle
            )
        case .allowListBlockedValidation:
            String(
                localized: "Allow List is active and does not allow the local validation probe URL, so Rockxy forwards it but does not record it.",
                bundle: RockxyLocalization.bundle
            )
        case .wrongSnippetChosen:
            String(
                localized: "Switch to the snippet that matches the runtime, library, or tool you are using.",
                bundle: RockxyLocalization.bundle
            )
        case .manualValidationOnly:
            String(
                localized: "Use the manual validation steps in this Dev Hub guide.",
                bundle: RockxyLocalization.bundle
            )
        case .targetIsGuideOnly:
            String(localized: "This target currently ships as guidance only.", bundle: RockxyLocalization.bundle)
        }
    }

    var actionTitle: String {
        switch self {
        case .runtimeNotInstalled:
            String(localized: "View Setup", bundle: RockxyLocalization.bundle)
        case .proxyStopped:
            String(localized: "Start Proxy", bundle: RockxyLocalization.bundle)
        case .recordingPaused:
            String(localized: "Resume Recording", bundle: RockxyLocalization.bundle)
        case .certificateNotTrusted,
             .certificateExportUnavailable:
            String(localized: "Open Certificate Guide", bundle: RockxyLocalization.bundle)
        case .deviceProxyUnreachable:
            String(localized: "Open Proxy Settings", bundle: RockxyLocalization.bundle)
        case .noTrafficDetected:
            String(localized: "Run Test Again", bundle: RockxyLocalization.bundle)
        case .localProbeUnavailable:
            String(localized: "Retry", bundle: RockxyLocalization.bundle)
        case .localProbeNotCaptured:
            String(localized: "Run Probe Again", bundle: RockxyLocalization.bundle)
        case .allowListBlockedValidation:
            String(localized: "Open Allow List", bundle: RockxyLocalization.bundle)
        case .wrongSnippetChosen:
            String(localized: "View Snippets", bundle: RockxyLocalization.bundle)
        case .manualValidationOnly:
            String(localized: "View Validation", bundle: RockxyLocalization.bundle)
        case .targetIsGuideOnly:
            String(localized: "View Overview", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - SetupStep

struct SetupStep: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let actionTitle: String
    let actionKind: SetupActionKind
    let isComplete: Bool
    let isEnabled: Bool
}

// MARK: - VerificationState

enum VerificationState: Equatable {
    case idle
    case readinessFailed
    case readyToVerify
    case waitingForTraffic
    case success
    case timedOut
    case cancelled

    // MARK: Internal

    var title: String {
        switch self {
        case .idle:
            String(localized: "Idle", bundle: RockxyLocalization.bundle)
        case .readinessFailed:
            String(localized: "Fix setup first", bundle: RockxyLocalization.bundle)
        case .readyToVerify:
            String(localized: "Ready to verify", bundle: RockxyLocalization.bundle)
        case .waitingForTraffic:
            String(localized: "Waiting for local probe", bundle: RockxyLocalization.bundle)
        case .success:
            String(localized: "Local probe captured", bundle: RockxyLocalization.bundle)
        case .timedOut:
            String(localized: "Timed out", bundle: RockxyLocalization.bundle)
        case .cancelled:
            String(localized: "Cancelled", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - SetupSnapshot

struct SetupSnapshot: Equatable {
    // MARK: Lifecycle

    init(
        supportStatus: SetupSupportStatus,
        runtimeReady: Bool = true,
        runtimeStatusNote: String? = nil,
        proxyRunning: Bool,
        recordingEnabled: Bool,
        activePort: Int,
        effectiveListenAddress: String,
        reachableLANAddress: String? = nil,
        certificateGenerated: Bool,
        certificateTrusted: Bool,
        certificateExportable: Bool,
        certificateFileReady: Bool = false,
        proxyMode: ProxyMode,
        readinessWarningMessage: String?,
        selectedSnippetID: SetupSnippetID?,
        verificationState: VerificationState,
        matchedTransactionID: UUID?,
        matchedHost: String?,
        matchedMethod: String?,
        matchedPath: String?
    ) {
        self.supportStatus = supportStatus
        self.runtimeReady = runtimeReady
        self.runtimeStatusNote = runtimeStatusNote
        self.proxyRunning = proxyRunning
        self.recordingEnabled = recordingEnabled
        self.activePort = activePort
        self.effectiveListenAddress = effectiveListenAddress
        self.reachableLANAddress = reachableLANAddress
        self.certificateGenerated = certificateGenerated
        self.certificateTrusted = certificateTrusted
        self.certificateExportable = certificateExportable
        self.certificateFileReady = certificateFileReady
        self.proxyMode = proxyMode
        self.readinessWarningMessage = readinessWarningMessage
        self.selectedSnippetID = selectedSnippetID
        self.verificationState = verificationState
        self.matchedTransactionID = matchedTransactionID
        self.matchedHost = matchedHost
        self.matchedMethod = matchedMethod
        self.matchedPath = matchedPath
    }

    // MARK: Internal

    var supportStatus: SetupSupportStatus
    var runtimeReady: Bool
    var runtimeStatusNote: String?
    var proxyRunning: Bool
    var recordingEnabled: Bool
    var activePort: Int
    var effectiveListenAddress: String
    var reachableLANAddress: String?
    /// Every LAN address devices could use, best first. More than one means the person should
    /// choose which network the device is on.
    var lanCandidates: [LANIPv4AddressCandidate] = []
    var certificateGenerated: Bool
    var certificateTrusted: Bool
    var certificateExportable: Bool
    var certificateFileReady: Bool
    var proxyMode: ProxyMode
    var readinessWarningMessage: String?
    var selectedSnippetID: SetupSnippetID?
    var verificationState: VerificationState
    var matchedTransactionID: UUID?
    var matchedHost: String?
    var matchedMethod: String?
    var matchedPath: String?

    var proxyStepActionTitle: String {
        if !proxyRunning {
            return String(localized: "Start Proxy", bundle: RockxyLocalization.bundle)
        }
        return recordingEnabled
            ? String(localized: "Refresh Status", bundle: RockxyLocalization.bundle)
            : String(localized: "Resume Recording", bundle: RockxyLocalization.bundle)
    }
}

// MARK: - SetupTarget

struct SetupTarget: Identifiable, Hashable {
    enum ID: String, CaseIterable, Hashable, Identifiable {
        case python
        case nodeJS
        case ruby
        case golang
        case rust
        case javaVMs
        case curl
        case firefox
        case postman
        case insomnia
        case paw
        case iosDevice
        case iosSimulator
        case androidDevice
        case androidEmulator
        case tvOSWatchOS
        case visionPro
        case flutter
        case reactNative
        case nextJS
        case electronJS
        case docker

        // MARK: Internal

        var id: String {
            rawValue
        }
    }

    let id: ID
    let title: String
    let category: SetupTargetCategory
    let iconName: String
    let manualSupport: SetupSupportStatus
    let automationSupport: SetupAutomationSupport
    let shortSummary: String
    let manualSummary: String
    let currentSupportSummary: String

    var supportStatus: SetupSupportStatus {
        manualSupport
    }

    /// True only for shipped terminal-runtime targets, i.e. the targets for
    /// which Automatic Setup can prepare a scoped shell session.
    var isRuntimeTerminalTarget: Bool {
        automationSupport == .runtimeTerminal
    }

    var supportsCertificateSharing: Bool {
        switch id {
        case .iosDevice,
             .iosSimulator,
             .androidDevice,
             .androidEmulator,
             .tvOSWatchOS,
             .visionPro,
             .flutter,
             .reactNative:
            true
        default:
            false
        }
    }

    var requiresReachableLANProxy: Bool {
        switch id {
        case .iosDevice,
             .androidDevice,
             .tvOSWatchOS,
             .visionPro:
            true
        default:
            false
        }
    }
}
