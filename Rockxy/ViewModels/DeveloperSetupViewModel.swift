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
        selectedTarget = .python
        selectedSnippetID = .pythonRequests
        snapshot = SetupSnapshot(
            supportStatus: .availableNow,
            runtimeReady: runtimeReadiness.isSatisfied,
            runtimeStatusNote: runtimeReadiness.note,
            proxyRunning: coordinator.isProxyRunning,
            recordingEnabled: coordinator.isRecording,
            activePort: coordinator.activeProxyPort,
            effectiveListenAddress: settings.effectiveListenAddress,
            reachableLANAddress: Self.reachableLANAddress(),
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

    var selectedTarget: SetupTarget
    var pinnedTargetIDs: Set<SetupTarget.ID>
    var selectedTab: SetupDetailTab = .overview
    var sourceListSearchText = ""
    var showsAutomationSheet = false
    var selectedSnippetID: SetupSnippetID = .pythonRequests {
        didSet {
            snapshot.selectedSnippetID = selectedSnippetID
        }
    }

    var snapshot: SetupSnapshot
    var activeIssue: SetupIssue?
    private var validationRunID: UUID?
    private var validationTaskToken: ValidationTaskToken?

    var filteredTargetSections: [SetupTargetSection] {
        SetupTarget.filteredSections(matching: sourceListSearchText, pinnedTargetIDs: pinnedTargetIDs)
    }

    var currentWorkflow: SetupWorkflow {
        DeveloperSetupWorkflowCatalog.workflow(for: selectedTarget.id)
    }

    var currentSnippetOptions: [SetupSnippet] {
        currentWorkflow.snippets
    }

    var currentValidationSpec: SetupValidationSpec? {
        currentWorkflow.validation
    }

    var currentGuideContent: SetupGuideContent? {
        DeveloperSetupGuideCatalog.content(for: selectedTarget.id)
    }

    var currentAutomationPreview: SetupAutomationPreview? {
        SetupTarget.automationPreview(for: selectedTarget)
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
        currentSnippetText != nil
    }

    var toolbarVerifyEnabled: Bool {
        supportsValidation
    }

    var infoBannerText: String {
        if selectedTarget.supportStatus == .availableNow {
            if selectedTarget.automationSupport.isAvailable {
                return [
                    selectedTarget.currentSupportSummary,
                    String(localized: "Automatic Setup is available separately for this runtime."),
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
        let snippetTitle: String
        if selectedTarget.supportStatus != .availableNow {
            snippetTitle = String(localized: "Guide only")
        } else if currentWorkflow.supportsSnippets {
            snippetTitle = selectedSnippetTitle
        } else {
            snippetTitle = String(localized: "Manual guide")
        }

        let automationTitle = selectedTarget.automationSupport.isAvailable
            ? selectedTarget.automationSupport.badgeTitle
            : String(localized: "Manual only")

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
            certificatePath: certificatePathHint
            )
    }

    var currentValidationSnippetText: String? {
        guard supportsValidation else {
            return nil
        }

        return DeveloperSetupWorkflowCatalog.generatedValidationSnippet(
            for: selectedTarget.id,
            workflow: currentWorkflow,
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
              FileManager.default.fileExists(atPath: path)
        else {
            return nil
        }

        return path
    }

    var certificatePathStatusText: String {
        if let path = certificatePathHint {
            return URL(fileURLWithPath: path).lastPathComponent
        }

        return String(localized: "Export required")
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
            ?? String(localized: "Interactive validation is not available for this target.")
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
            issues.append(.noTrafficDetected)
        }
        if currentSnippetOptions.count > 1 {
            issues.append(.wrongSnippetChosen)
        }

        return issues
    }

    func isPinned(_ target: SetupTarget) -> Bool {
        pinnedTargetIDs.contains(target.id)
    }

    func refreshSnapshot() async {
        let settings = AppSettingsManager.shared.settings
        let readiness = ReadinessCoordinator.shared
        let originalTargetID = selectedTarget.id
        let certificateSnapshot = await CertificateManager.shared.rootCAStatusSnapshot(performValidation: false)
        let pem = try? await CertificateManager.shared.getRootCAPEM()
        guard selectedTarget.id == originalTargetID else {
            return
        }

        let runtimeReadiness = DeveloperSetupRuntimeTooling.readiness(for: originalTargetID)
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
        snapshot.reachableLANAddress = Self.reachableLANAddress()
        snapshot.certificateGenerated = certificateSnapshot.hasGeneratedCertificate
        snapshot.certificateTrusted = certificateSnapshot.isSystemTrustValidated || readiness.canInterceptHTTPS
        snapshot.certificateExportable = pem != nil
        snapshot.certificateFileReady = Self.exportedCertificateFileReady(from: settings)
        snapshot.proxyMode = readiness.proxyMode
        snapshot.readinessWarningMessage = readiness.activeWarning?.message
        snapshot.selectedSnippetID = workflow.supportsSnippets ? selectedSnippetID : nil

        let priorVerificationState = snapshot.verificationState
        let isTerminalState = switch priorVerificationState {
        case .success, .timedOut, .cancelled:
            true
        default:
            false
        }
        guard !isTerminalState else {
            return
        }

        let nextIssue = Self.validationIssue(for: target, snapshot: snapshot, workflow: workflow)
        activeIssue = nextIssue
        if workflow.supportsValidation {
            if priorVerificationState != .waitingForTraffic {
                snapshot.verificationState = nextIssue == nil ? .readyToVerify : .readinessFailed
            }
        } else if priorVerificationState != .waitingForTraffic {
            snapshot.verificationState = .idle
        }
    }

    func selectTarget(_ target: SetupTarget) {
        if selectedTarget.id != target.id, snapshot.verificationState == .waitingForTraffic {
            cancelValidation(markCancelled: true)
        }

        showsAutomationSheet = false
        selectedTarget = target
        selectedTab = .overview
        selectedSnippetID = defaultSnippetID(for: target.id)
        let runtimeReadiness = DeveloperSetupRuntimeTooling.readiness(for: target.id)
        snapshot.supportStatus = target.supportStatus
        snapshot.runtimeReady = runtimeReadiness.isSatisfied
        snapshot.runtimeStatusNote = runtimeReadiness.note
        snapshot.selectedSnippetID = currentWorkflow.supportsSnippets ? selectedSnippetID : nil
        snapshot.matchedTransactionID = nil
        snapshot.matchedHost = nil
        snapshot.matchedMethod = nil
        snapshot.matchedPath = nil
        activeIssue = Self.validationIssue(for: target, snapshot: snapshot, workflow: currentWorkflow)

        if supportsValidation {
            snapshot.verificationState = Self.validationIssue(for: target, snapshot: snapshot, workflow: currentWorkflow) == nil
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

    func openAutomationSheet() {
        guard supportsAutomation else {
            return
        }
        showsAutomationSheet = true
    }

    func closeAutomationSheet() {
        showsAutomationSheet = false
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
            guard
                self.selectedTarget.id == capturedTargetID,
                self.validationTaskToken === capturedTaskToken,
                self.validationRunID == validationRunID
            else {
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

            guard let issue = Self.validationIssue(for: self.selectedTarget, snapshot: self.snapshot, workflow: self.currentWorkflow) else {
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
                        guard
                            self.selectedTarget.id == capturedTargetID,
                            self.validationTaskToken === capturedTaskToken,
                            self.validationRunID == validationRunID
                        else {
                            return
                        }
                        self.cancelValidation(markCancelled: true)
                        return
                    }

                    if self.coordinator.sessionGeneration != baselineSessionGeneration
                        || !self.coordinator.isProxyRunning
                        || !self.coordinator.isRecording
                    {
                        guard
                            self.selectedTarget.id == capturedTargetID,
                            self.validationTaskToken === capturedTaskToken,
                            self.validationRunID == validationRunID
                        else {
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
                        self.activeIssue = .noTrafficDetected
                        return
                    }

                    try? await Task.sleep(for: .milliseconds(250))
                }

                guard
                    self.selectedTarget.id == capturedTargetID,
                    self.validationTaskToken === capturedTaskToken,
                    self.validationRunID == validationRunID
                else {
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
            snapshot.verificationState = Self.validationIssue(for: selectedTarget, snapshot: snapshot, workflow: currentWorkflow) == nil
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

    static func resolveSnippetPort(isProxyRunning: Bool, activePort: Int, configuredPort: Int) -> Int {
        isProxyRunning ? activePort : configuredPort
    }

    static func reachableLANAddress() -> String? {
        RootCADownloadServer.lanIPv4Addresses().first
    }

    static func validationIssue(
        for target: SetupTarget,
        snapshot: SetupSnapshot,
        workflow: SetupWorkflow
    ) -> SetupIssue? {
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
        return nil
    }

    static func deviceProxyIssue(for target: SetupTarget, snapshot: SetupSnapshot) -> SetupIssue? {
        guard target.supportStatus == .availableNow,
              target.requiresReachableLANProxy
        else {
            return nil
        }
        guard snapshot.effectiveListenAddress != "127.0.0.1",
              snapshot.reachableLANAddress != nil
        else {
            return .deviceProxyUnreachable
        }
        return nil
    }

    static func matchesValidationTransaction(
        _ transaction: HTTPTransaction,
        baselineSequenceNumber: Int,
        validation: SetupValidationSpec
    ) -> Bool {
        transaction.sequenceNumber > baselineSequenceNumber
            && transaction.request.method == validation.method
            && transaction.request.host == validation.host
            && transaction.request.path == validation.path
    }

    // MARK: Private

    private var validationTask: Task<Void, Never>?
    private let pinnedStore: DeveloperSetupPinnedStore

    private final class ValidationTaskToken {}

    private var selectedSnippetTitle: String {
        currentSnippetOptions.first(where: { $0.id == selectedSnippetID })?.title
            ?? String(localized: "Guide only")
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

    private static func exportedCertificateFileReady(from settings: AppSettings) -> Bool {
        guard let path = settings.lastExportedRootCAPath, !path.isEmpty else {
            return false
        }

        return FileManager.default.fileExists(atPath: path)
    }
}
