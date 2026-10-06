import Foundation
import Observation

// MARK: - DeveloperSetupViewModel

@MainActor @Observable
final class DeveloperSetupViewModel {
    // MARK: Lifecycle

    convenience init(coordinator: MainContentCoordinator) {
        self.init(coordinator: coordinator, pinnedStore: .shared)
    }

    init(
        coordinator: MainContentCoordinator,
        pinnedStore: DeveloperSetupPinnedStore
    ) {
        let settings = AppSettingsManager.shared.settings
        let runtimeReadiness = DeveloperSetupRuntimeTooling.readiness(for: .python)

        self.coordinator = coordinator
        self.pinnedStore = pinnedStore
        pinnedTargetIDs = pinnedStore.pinnedTargetIDs
        selectedTargetID = .python
        selectedSnippetID = .pythonRequests
        snapshot = SetupSnapshot(
            supportStatus: .availableNow,
            runtimeReady: runtimeReadiness.isSatisfied,
            runtimeStatusNote: runtimeReadiness.note,
            proxyRunning: coordinator.isProxyRunning,
            recordingEnabled: coordinator.isRecording,
            activePort: coordinator.activeProxyPort,
            effectiveListenAddress: settings.effectiveListenAddress,
            reachableLANAddress: Self.reachableLANAddress(for: settings.effectiveListenAddress),
            certificateGenerated: false,
            certificateTrusted: false,
            certificateExportable: false,
            certificateFileReady: Self.exportedCertificateFileReady(from: settings),
            proxyMode: ReadinessCoordinator.shared.proxyMode,
            readinessWarningMessage: ReadinessCoordinator.shared.activeWarning?.message,
            selectedSnippetID: .pythonRequests,
            verificationState: .idle,
            matchedTransactionID: nil,
            matchedHost: nil,
            matchedMethod: nil,
            matchedPath: nil
        )
    }

    // MARK: Internal

    let coordinator: MainContentCoordinator

    /// The selection is tracked by stable identity so it survives a runtime language
    /// switch; `selectedTarget` re-derives from the catalog on every read, presenting
    /// freshly localized title/summary values for the same logical target.
    var selectedTargetID: SetupTarget.ID
    var pinnedTargetIDs: Set<SetupTarget.ID>
    var selectedTab: SetupDetailTab = .overview
    var sourceListSearchText = ""
    var snapshot: SetupSnapshot
    var activeIssue: SetupIssue?

    var selectedSnippetID: SetupSnippetID = .pythonRequests {
        didSet {
            snapshot.selectedSnippetID = selectedSnippetID
        }
    }

    /// The currently selected target, re-derived from `selectedTargetID` so its
    /// localized presentation reflects the current app language. Falls back to
    /// Python if the catalog ever lacks the stored identifier.
    var selectedTarget: SetupTarget {
        get { SetupTarget.target(for: selectedTargetID) ?? .python }
        set { selectedTargetID = newValue.id }
    }

    var filteredTargetSections: [SetupTargetSection] {
        let sections = SetupTarget.filteredSections(
            matching: sourceListSearchText,
            pinnedTargetIDs: pinnedTargetIDs
        )
        return sections.compactMap { section in
            guard section.category != .pinned else {
                return section
            }
            let uniqueTargets = section.targets.filter { !pinnedTargetIDs.contains($0.id) }
            guard !uniqueTargets.isEmpty else {
                return nil
            }
            return SetupTargetSection(category: section.category, targets: uniqueTargets)
        }
    }

    var currentWorkflow: SetupWorkflow {
        DeveloperSetupWorkflowCatalog.workflow(for: selectedTarget.id)
    }

    var currentSnippetOptions: [SetupSnippet] {
        currentWorkflow.snippets
    }

    var currentValidationSpec: SetupValidationSpec? {
        guard let template = currentWorkflow.validation else {
            return nil
        }
        guard let probeSession, probeSession.targetID == selectedTarget.id else {
            return template
        }
        return DeveloperSetupWorkflowCatalog.validationSpec(
            for: selectedTarget.id,
            runtimeName: selectedTarget.title,
            preferredSnippetID: template.preferredSnippetID,
            probeSession: probeSession
        )
    }

    var currentGuideContent: SetupGuideContent? {
        DeveloperSetupGuideCatalog.content(for: selectedTarget.id)
    }

    var setupModeActions: SetupModeActionState {
        SetupModeActionState(target: selectedTarget)
    }

    var supportsValidation: Bool {
        selectedTarget.supportStatus == .availableNow && currentWorkflow.supportsValidation
    }

    var usesGuideSetupContent: Bool {
        selectedTarget.supportStatus == .availableNow
            && currentGuideContent != nil
            && !currentWorkflow.supportsSnippets
    }

    var supportsAutomation: Bool {
        selectedTarget.automationSupport.isAvailable
    }

    var toolbarCopyEnabled: Bool {
        switch selectedTab {
        case .snippets:
            currentSnippetText != nil
        case .validate:
            currentValidationSnippetText != nil || currentSnippetText != nil
        case .overview,
             .setup,
             .troubleshooting:
            false
        }
    }

    var toolbarVerifyEnabled: Bool {
        supportsValidation
    }

    var hasValidationProbeForSelectedTarget: Bool {
        probeSession?.targetID == selectedTarget.id
    }

    var infoBannerText: String {
        if selectedTarget.supportStatus == .availableNow {
            if selectedTarget.automationSupport.isAvailable {
                return [
                    selectedTarget.currentSupportSummary,
                    String(
                        localized: "Automatic Setup can prepare a scoped session for this target; Manual Setup remains available.",
                        bundle: RockxyLocalization.bundle
                    ),
                ].joined(separator: " ")
            }

            return selectedTarget.currentSupportSummary
        }

        return [
            selectedTarget.manualSummary,
            selectedTarget.currentSupportSummary,
        ].joined(separator: " ")
    }

    var bottomStatusText: String {
        let snippetTitle: String = if selectedTarget.supportStatus != .availableNow {
            String(localized: "Guide only", bundle: RockxyLocalization.bundle)
        } else if currentWorkflow.supportsSnippets {
            selectedSnippetTitle
        } else {
            String(localized: "Manual guide", bundle: RockxyLocalization.bundle)
        }

        let automationTitle = selectedTarget.automationSupport.isAvailable
            ? selectedTarget.automationSupport.badgeTitle
            : String(localized: "Manual Setup", bundle: RockxyLocalization.bundle)

        return [
            selectedTarget.title,
            snapshot.supportStatus.title,
            snippetTitle,
            automationTitle,
            snapshot.verificationState.title,
        ].joined(separator: "  •  ")
    }

    var currentSnippetTitle: String {
        selectedSnippetTitle
    }

    var currentSnippetText: String? {
        guard selectedTarget.supportStatus == .availableNow else {
            return nil
        }

        return DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: selectedTarget.id,
            snippetID: selectedSnippetID,
            port: Self.resolveSnippetPort(
                isProxyRunning: snapshot.proxyRunning,
                activePort: snapshot.activePort,
                configuredPort: AppSettingsManager.shared.settings.proxyPort
            ),
            certificatePath: certificatePathHint,
            deviceProxyHost: snapshot.reachableLANAddress
        )
    }

    var currentValidationSnippetText: String? {
        guard supportsValidation else {
            return nil
        }

        return DeveloperSetupWorkflowCatalog.generatedValidationSnippet(
            for: selectedTarget.id,
            workflow: currentWorkflow,
            validation: currentValidationSpec,
            selectedSnippetID: selectedSnippetID,
            port: Self.resolveSnippetPort(
                isProxyRunning: snapshot.proxyRunning,
                activePort: snapshot.activePort,
                configuredPort: AppSettingsManager.shared.settings.proxyPort
            ),
            certificatePath: certificatePathHint
        )
    }

    var certificatePathHint: String? {
        guard snapshot.certificateGenerated else {
            return nil
        }

        guard let path = AppSettingsManager.shared.settings.lastExportedRootCAPath,
              !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else
        {
            return nil
        }

        return path
    }

    var certificatePathStatusText: String {
        if let path = certificatePathHint {
            return URL(fileURLWithPath: path).lastPathComponent
        }

        return String(localized: "Export required", bundle: RockxyLocalization.bundle)
    }

    var currentSetupSteps: [SetupStep] {
        guard selectedTarget.supportStatus == .availableNow else {
            return []
        }

        return DeveloperSetupWorkflowCatalog.steps(
            for: selectedTarget,
            snapshot: snapshot,
            selectedSnippetID: currentWorkflow.supportsSnippets ? selectedSnippetID : nil
        )
    }

    var validationInstruction: String {
        currentValidationSpec?.instruction
            ?? String(
                localized: "Interactive validation is not available for this target.",
                bundle: RockxyLocalization.bundle
            )
    }

    var troubleshootingIssues: [SetupIssue] {
        var issues: [SetupIssue] = []
        if let deviceProxyIssue = Self.deviceProxyIssue(for: selectedTarget, snapshot: snapshot) {
            issues.append(deviceProxyIssue)
        }

        guard supportsValidation else {
            issues.append(selectedTarget.supportStatus == .availableNow ? .manualValidationOnly : .targetIsGuideOnly)
            return issues
        }

        if !snapshot.proxyRunning {
            issues.append(.proxyStopped)
        }
        if !snapshot.recordingEnabled {
            issues.append(.recordingPaused)
        }
        if !snapshot.certificateTrusted {
            issues.append(.certificateNotTrusted)
        }
        if !snapshot.certificateExportable {
            issues.append(.certificateExportUnavailable)
        }
        if snapshot.verificationState == .timedOut {
            issues.append(.localProbeNotCaptured)
        }
        if currentSnippetOptions.count > 1 {
            issues.append(.wrongSnippetChosen)
        }

        return issues
    }

    static func resolveSnippetPort(isProxyRunning: Bool, activePort: Int, configuredPort: Int) -> Int {
        isProxyRunning ? activePort : configuredPort
    }

    static func reachableLANAddress(
        for effectiveListenAddress: String,
        discoverLANAddress: () -> String? = { RootCADownloadServer.lanIPv4Addresses().first }
    )
        -> String?
    {
        let normalizedListenAddress = effectiveListenAddress
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedListenAddress.isEmpty else {
            return nil
        }
        if isWildcardListenAddress(normalizedListenAddress) {
            return discoverLANAddress()
        }
        guard !isLoopbackListenAddress(normalizedListenAddress) else {
            return nil
        }
        return effectiveListenAddress
    }

    static func validationIssue(
        for target: SetupTarget,
        snapshot: SetupSnapshot,
        workflow: SetupWorkflow,
        validation: SetupValidationSpec? = nil
    )
        -> SetupIssue?
    {
        if let deviceProxyIssue = deviceProxyIssue(for: target, snapshot: snapshot) {
            return deviceProxyIssue
        }
        guard target.supportStatus == .availableNow else {
            return .targetIsGuideOnly
        }
        guard workflow.supportsValidation else {
            return .manualValidationOnly
        }
        if !snapshot.runtimeReady {
            return .runtimeNotInstalled
        }
        if !snapshot.proxyRunning {
            return .proxyStopped
        }
        if !snapshot.recordingEnabled {
            return .recordingPaused
        }
        if !snapshot.certificateTrusted {
            return .certificateNotTrusted
        }
        if !snapshot.certificateExportable || !snapshot.certificateFileReady {
            return .certificateExportUnavailable
        }
        if let validation,
           let validationURL = URL(string: validation.urlString),
           AllowListManager.shared.isActive,
           !AllowListManager.shared.isRequestAllowed(method: validation.method, url: validationURL)
        {
            return .allowListBlockedValidation
        }
        return nil
    }

    static func deviceProxyIssue(for target: SetupTarget, snapshot: SetupSnapshot) -> SetupIssue? {
        guard target.supportStatus == .availableNow,
              target.requiresReachableLANProxy else
        {
            return nil
        }
        guard !isLoopbackListenAddress(snapshot.effectiveListenAddress.lowercased()),
              snapshot.reachableLANAddress != nil else
        {
            return .deviceProxyUnreachable
        }
        return nil
    }

    static func matchesValidationTransaction(
        _ transaction: HTTPTransaction,
        baselineSequenceNumber: Int,
        validation: SetupValidationSpec
    )
        -> Bool
    {
        transaction.sequenceNumber > baselineSequenceNumber
            && transaction.request.method == validation.method
            && transaction.request.host == validation.host
            && transaction.request.path == validation.path
    }

    func isPinned(_ target: SetupTarget) -> Bool {
        pinnedTargetIDs.contains(target.id)
    }

    func refreshSnapshot() async {
        snapshotRefreshGeneration += 1
        let refreshGeneration = snapshotRefreshGeneration
        let settings = AppSettingsManager.shared.settings
        let readiness = ReadinessCoordinator.shared
        let generation = targetGeneration
        let originalTargetID = selectedTarget.id
        let certificateSnapshot = await CertificateManager.shared.rootCAStatusSnapshot(performValidation: false)
        guard targetGeneration == generation,
              snapshotRefreshGeneration == refreshGeneration else
        {
            return
        }
        let pem = try? await CertificateManager.shared.getRootCAPEM()
        guard targetGeneration == generation,
              snapshotRefreshGeneration == refreshGeneration,
              selectedTarget.id == originalTargetID else
        {
            return
        }

        let runtimeReadiness = await DeveloperSetupRuntimeTooling.readinessAsync(for: originalTargetID)
        guard targetGeneration == generation,
              snapshotRefreshGeneration == refreshGeneration,
              selectedTarget.id == originalTargetID else
        {
            return
        }
        let workflow = currentWorkflow
        let target = selectedTarget

        ensureSelectedSnippetMatchesCurrentTarget()

        snapshot.supportStatus = target.supportStatus
        snapshot.runtimeReady = runtimeReadiness.isSatisfied
        snapshot.runtimeStatusNote = runtimeReadiness.note
        snapshot.proxyRunning = coordinator.isProxyRunning
        snapshot.recordingEnabled = coordinator.isRecording
        snapshot.activePort = coordinator.isProxyRunning ? coordinator.activeProxyPort : settings.proxyPort
        snapshot.effectiveListenAddress = settings.effectiveListenAddress
        snapshot.reachableLANAddress = Self.reachableLANAddress(for: settings.effectiveListenAddress)
        snapshot.certificateGenerated = certificateSnapshot.hasGeneratedCertificate
        snapshot.certificateTrusted = certificateSnapshot.isSystemTrustValidated || readiness.canInterceptHTTPS
        snapshot.certificateExportable = pem != nil
        snapshot.certificateFileReady = Self.exportedCertificateFileReady(from: settings)
        snapshot.proxyMode = readiness.proxyMode
        snapshot.readinessWarningMessage = readiness.activeWarning?.message
        snapshot.selectedSnippetID = workflow.supportsSnippets ? selectedSnippetID : nil

        let priorVerificationState = snapshot.verificationState
        let isTerminalState = switch priorVerificationState {
        case .success,
             .timedOut,
             .cancelled:
            true
        default:
            false
        }
        let probeReady = await prepareValidationProbe(
            targetID: originalTargetID,
            targetGeneration: generation
        )
        guard targetGeneration == generation,
              snapshotRefreshGeneration == refreshGeneration,
              selectedTarget.id == originalTargetID else
        {
            return
        }
        let validationSpec = probeReady ? currentValidationSpec : nil
        // Only a target that actually validates through the local probe can be blocked by
        // the probe. Guide-only and device targets never start one, so they must surface
        // their real state (manual validation, certificate trust, device endpoint) instead
        // of a "probe unavailable" issue whose Retry can never succeed.
        let nextIssue = probeReady || !supportsValidation
            ? Self.validationIssue(for: target, snapshot: snapshot, workflow: workflow, validation: validationSpec)
            : .localProbeUnavailable
        activeIssue = nextIssue
        if isTerminalState {
            if priorVerificationState == .success, nextIssue != nil {
                snapshot.matchedTransactionID = nil
                snapshot.matchedHost = nil
                snapshot.matchedMethod = nil
                snapshot.matchedPath = nil
            }
            return
        }
        if workflow.supportsValidation {
            if priorVerificationState != .waitingForTraffic {
                snapshot.verificationState = nextIssue == nil ? .readyToVerify : .readinessFailed
            }
        } else if priorVerificationState != .waitingForTraffic {
            snapshot.verificationState = .idle
        }
    }

    func selectTarget(_ target: SetupTarget) async {
        if snapshot.verificationState == .waitingForTraffic {
            cancelValidation(markCancelled: true)
        }

        targetGeneration += 1
        let generation = targetGeneration

        selectedTarget = target
        selectedTab = .overview
        selectedSnippetID = defaultSnippetID(for: target.id)
        snapshot.supportStatus = target.supportStatus
        snapshot.selectedSnippetID = currentWorkflow.supportsSnippets ? selectedSnippetID : nil
        snapshot.matchedTransactionID = nil
        snapshot.matchedHost = nil
        snapshot.matchedMethod = nil
        snapshot.matchedPath = nil
        probeSession = nil

        // Serialize probe lifecycle across a target switch: fully stop the prior
        // target's probe before any later probe can start, so two targets never
        // race the single probe server.
        await probeServer.stop()
        guard targetGeneration == generation else {
            return
        }

        let targetID = target.id
        let runtimeReadiness = await DeveloperSetupRuntimeTooling.readinessAsync(for: targetID)
        guard targetGeneration == generation, selectedTarget.id == targetID else {
            return
        }

        snapshot.runtimeReady = runtimeReadiness.isSatisfied
        snapshot.runtimeStatusNote = runtimeReadiness.note
        activeIssue = Self.validationIssue(for: target, snapshot: snapshot, workflow: currentWorkflow)

        if supportsValidation {
            snapshot.verificationState = Self.validationIssue(
                for: target,
                snapshot: snapshot,
                workflow: currentWorkflow
            ) == nil
                ? .readyToVerify
                : .readinessFailed
        } else {
            snapshot.verificationState = .idle
        }
    }

    func togglePinned(_ target: SetupTarget) {
        pinnedStore.toggle(target.id)
        pinnedTargetIDs = pinnedStore.pinnedTargetIDs
    }

    func selectTab(_ tab: SetupDetailTab) {
        if snapshot.verificationState == .waitingForTraffic, tab != .validate {
            cancelValidation(markCancelled: true)
        }
        selectedTab = tab
    }

    /// Apply a hub route as one awaitable target + tab transition. Consumers can
    /// await completion, while the route generation prevents an older in-flight
    /// transition from committing after a newer one.
    func applyHubRoute(_ route: DeveloperSetupRoute?) async {
        guard let route,
              route.destination == .hub,
              route.generation > lastAppliedHubRouteGeneration,
              let target = SetupTarget.target(for: route.targetID) else
        {
            return
        }
        lastAppliedHubRouteGeneration = route.generation
        await selectTarget(target)
        guard lastAppliedHubRouteGeneration == route.generation,
              selectedTarget.id == route.targetID else
        {
            return
        }
        selectTab(route.tab)
        await refreshSnapshot()
    }

    func copyTextForCurrentContext() -> String? {
        if selectedTab == .validate {
            return currentValidationSnippetText ?? currentSnippetText
        }

        return currentSnippetText
    }

    func performStepAction(_ step: SetupStep) {
        switch step.actionKind {
        case .verifyProxy:
            selectedTab = .overview
        case .openCertificate:
            selectedTab = .setup
        case .copySnippet:
            selectedTab = .snippets
        case .runValidation:
            selectedTab = .validate
        }
    }

    func revealMatchedTransaction() {
        guard let id = snapshot.matchedTransactionID else {
            return
        }
        coordinator.revealTransaction(id: id)
    }

    func startValidation() {
        validationTask?.cancel()
        let capturedTargetID = selectedTarget.id
        let validationRunID = UUID()
        let capturedTaskToken = ValidationTaskToken()
        self.validationRunID = validationRunID
        self.validationTaskToken = capturedTaskToken
        validationTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await self.refreshSnapshot()
            guard self.selectedTarget.id == capturedTargetID,
                  self.validationTaskToken === capturedTaskToken,
                  self.validationRunID == validationRunID else
            {
                return
            }

            guard let validation = self.currentValidationSpec else {
                self.activeIssue = Self.validationIssue(
                    for: self.selectedTarget,
                    snapshot: self.snapshot,
                    workflow: self.currentWorkflow
                )
                self.snapshot.verificationState = .readinessFailed
                self.selectedTab = .validate
                return
            }

            guard self.probeSession?.targetID == capturedTargetID else {
                self.activeIssue = .localProbeUnavailable
                self.snapshot.verificationState = .readinessFailed
                self.selectedTab = .validate
                return
            }

            guard let issue = Self.validationIssue(
                for: self.selectedTarget,
                snapshot: self.snapshot,
                workflow: self.currentWorkflow,
                validation: validation
            ) else {
                let baselineSequenceNumber = self.coordinator.transactions.map(\.sequenceNumber).max() ?? 0
                let baselineSessionGeneration = self.coordinator.sessionGeneration
                self.activeIssue = nil
                self.selectedTab = .validate
                self.snapshot.verificationState = .waitingForTraffic
                self.snapshot.matchedTransactionID = nil
                self.snapshot.matchedHost = nil
                self.snapshot.matchedMethod = nil
                self.snapshot.matchedPath = nil

                let clock = ContinuousClock()
                let timeoutTask = clock.now + .seconds(20)

                while !Task.isCancelled {
                    if !self.supportsValidation {
                        guard self.selectedTarget.id == capturedTargetID,
                              self.validationTaskToken === capturedTaskToken,
                              self.validationRunID == validationRunID else
                        {
                            return
                        }
                        self.cancelValidation(markCancelled: true)
                        return
                    }

                    if self.coordinator.sessionGeneration != baselineSessionGeneration
                        || !self.coordinator.isProxyRunning
                        || !self.coordinator.isRecording
                    {
                        guard self.selectedTarget.id == capturedTargetID,
                              self.validationTaskToken === capturedTaskToken,
                              self.validationRunID == validationRunID else
                        {
                            return
                        }
                        self.cancelValidation(markCancelled: true)
                        return
                    }

                    if let match = self.coordinator.transactions.first(where: {
                        Self.matchesValidationTransaction(
                            $0,
                            baselineSequenceNumber: baselineSequenceNumber,
                            validation: validation
                        )
                    }) {
                        self.snapshot.verificationState = .success
                        self.snapshot.matchedTransactionID = match.id
                        self.snapshot.matchedHost = match.request.host
                        self.snapshot.matchedMethod = match.request.method
                        self.snapshot.matchedPath = match.request.path
                        self.activeIssue = nil
                        return
                    }

                    if clock.now >= timeoutTask {
                        self.snapshot.verificationState = .timedOut
                        self.activeIssue = .localProbeNotCaptured
                        return
                    }

                    try? await Task.sleep(for: .milliseconds(250))
                }

                guard self.selectedTarget.id == capturedTargetID,
                      self.validationTaskToken === capturedTaskToken,
                      self.validationRunID == validationRunID else
                {
                    return
                }
                self.cancelValidation(markCancelled: true)
                return
            }

            self.activeIssue = issue
            self.snapshot.verificationState = .readinessFailed
            self.selectedTab = .validate
        }
    }

    func cancelValidation(markCancelled: Bool) {
        validationTask?.cancel()
        validationTask = nil
        validationRunID = nil
        validationTaskToken = nil

        if markCancelled {
            snapshot.verificationState = .cancelled
        } else if supportsValidation {
            snapshot.verificationState = Self.validationIssue(
                for: selectedTarget,
                snapshot: snapshot,
                workflow: currentWorkflow,
                validation: currentValidationSpec
            ) == nil
                ? .readyToVerify
                : .readinessFailed
        } else {
            snapshot.verificationState = .idle
        }
    }

    func handleSessionCleared() {
        if snapshot.verificationState == .waitingForTraffic {
            cancelValidation(markCancelled: true)
        }
    }

    func stopValidationProbe() async {
        await probeServer.stop()
        probeSession = nil
    }

    // MARK: Private

    private final class ValidationTaskToken {}

    private var validationRunID: UUID?
    private var validationTaskToken: ValidationTaskToken?

    /// Incremented on every target switch. Any async continuation (snapshot
    /// refresh, probe start, route application) captures the generation at its
    /// start and refuses to commit results if the generation has moved on, so a
    /// stale result can never land in a newer target's state.
    private var targetGeneration = 0
    private var lastAppliedHubRouteGeneration = 0
    private var snapshotRefreshGeneration = 0

    private var validationTask: Task<Void, Never>?
    private let pinnedStore: DeveloperSetupPinnedStore
    private let probeServer = DeveloperSetupProbeServer()
    private var probeSession: DeveloperSetupProbeSession?

    private var selectedSnippetTitle: String {
        currentSnippetOptions.first(where: { $0.id == selectedSnippetID })?.title
            ?? String(localized: "Guide only", bundle: RockxyLocalization.bundle)
    }

    private static func exportedCertificateFileReady(from settings: AppSettings) -> Bool {
        guard let path = settings.lastExportedRootCAPath, !path.isEmpty else {
            return false
        }

        return FileManager.default.fileExists(atPath: path)
    }

    private static func isWildcardListenAddress(_ address: String) -> Bool {
        switch address {
        case "0.0.0.0",
             "::",
             "[::]",
             "*":
            true
        default:
            false
        }
    }

    private static func isLoopbackListenAddress(_ address: String) -> Bool {
        switch address {
        case "127.0.0.1",
             "::1",
             "[::1]",
             "localhost":
            true
        default:
            false
        }
    }

    private func ensureSelectedSnippetMatchesCurrentTarget() {
        guard currentWorkflow.supportsSnippets else {
            return
        }

        if !currentSnippetOptions.contains(where: { $0.id == selectedSnippetID }) {
            selectedSnippetID = defaultSnippetID(for: selectedTarget.id)
        }
    }

    private func defaultSnippetID(for targetID: SetupTarget.ID) -> SetupSnippetID {
        DeveloperSetupWorkflowCatalog.workflow(for: targetID).defaultSnippetID ?? .pythonRequests
    }

    @discardableResult
    private func prepareValidationProbe(
        targetID: SetupTarget.ID,
        targetGeneration generation: Int
    )
        async -> Bool
    {
        guard supportsValidation else {
            probeSession = nil
            await probeServer.stop()
            return false
        }

        if probeSession?.targetID == targetID {
            return true
        }

        do {
            let session = try await probeServer.start(targetID: targetID)
            guard targetGeneration == generation, selectedTarget.id == targetID else {
                return false
            }
            probeSession = session
            return true
        } catch {
            guard targetGeneration == generation, selectedTarget.id == targetID else {
                return false
            }
            probeSession = nil
            activeIssue = .localProbeUnavailable
            snapshot.verificationState = .readinessFailed
            return false
        }
    }
}
