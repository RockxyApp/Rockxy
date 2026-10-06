import AppKit
import Foundation
@testable import Rockxy
import Testing

// MARK: - BabylonPairingWindowReadabilityTests

/// Source-level and behavior contracts for the redesigned Babylon Pairing tool window.
/// These assert the shared tool-window shell, truthful (token-aware) readiness, honest
/// open-connection terminology, a real listener-only retry action, listener-generation
/// guards, one-time observer installation, a scrollable card body, an accessible reveal
/// affordance, and the conditional pasteboard privacy clean-up.
@MainActor
struct BabylonPairingWindowReadabilityTests {
    // MARK: Internal

    @Test("Babylon Pairing scene uses the approved tool-window conventions")
    func babylonPairingSceneUsesToolWindowConventions() throws {
        let app = try readProjectFile("Rockxy/RockxyApp.swift")

        let sceneStart = try #require(
            app
                .range(
                    of: "Window(String(localized: \"Babylon Pairing\", bundle: RockxyLocalization.bundle), id: \"babylonPairing\")"
                )
        )
        let scenesAfter = app[sceneStart.lowerBound...]
        let nextScene = try #require(
            scenesAfter
                .range(
                    of: "Window(String(localized: \"Babylon Runtime\", bundle: RockxyLocalization.bundle), id: \"babylonRuntime\")"
                )
        )
        let sceneSource = scenesAfter[..<nextScene.lowerBound]

        #expect(sceneSource.contains("ToolWindowDisplayMetricsProvider"))
        #expect(sceneSource.contains("BabylonPairingView()"))
        #expect(sceneSource.contains(".commandsRemoved()"))
        #expect(sceneSource.contains(".windowResizability(.contentSize)"))
        #expect(sceneSource.contains(".defaultPosition(.center)"))
        #expect(sceneSource.contains(".windowToolbarStyle(.unifiedCompact)"))
        #expect(sceneSource.contains(".defaultSize(width: 460, height: 420)"))
    }

    @Test("Babylon Pairing view uses shared metrics, truthful readiness, and honest affordances")
    func babylonPairingViewUsesSharedMetricsAndLiveState() throws {
        let source = try readProjectFile("Rockxy/Views/BabylonCapture/BabylonPairingView.swift")

        // Shared tool-window metrics and a native header/body/footer hierarchy.
        require(source, [
            "ToolWindowDisplayMetrics",
            "@Environment(\\.appUIDisplayMetrics)",
            "toolMetrics.font(",
            "toolMetrics.tableHeaderFont()",
            "minWidth: max(440, toolMetrics.bodyFontSize * 22 + 154)",
            "minHeight: max(400, toolMetrics.bodyFontSize * 18 + 166)",
        ])

        // No legacy grouped Form or hardcoded font ladder.
        forbid(source, [
            "Form {",
            ".formStyle(.grouped)",
            ".font(.headline",
            ".font(.body",
            ".font(.caption",
            ".font(.footnote",
            ".font(.system(.body",
            ".frame(minWidth: 540, minHeight: 320)",
        ])

        // Live typed receiver state composed with token presence into a
        // token-aware availability.
        require(source, [
            "BabylonCaptureReceiver.shared",
            "receiver.listenerStatus",
            "receiver.openConnectionCount",
            "BabylonPairingAvailability(",
            "listenerStatus: receiver.listenerStatus",
            "hasToken: !store.token.isEmpty",
            "localized: \"Stopped\"",
            "localized: \"Starting…\"",
            "localized: \"Waiting for Network\"",
            "localized: \"Ready\"",
            "localized: \"Not Ready\"",
            "localized: \"Unavailable\"",
            "case .tokenMissing",
        ])
        // Ready copy is scoped to accepting local-network connections — it must not
        // promise discovery/pairing reachability.
        require(source, [
            "The listener is accepting local-network connections on this Mac.",
        ])
        forbid(source, [
            "Babylon clients on this network can pair with this Mac.",
            "receiver.connectedClientCount",
        ])

        // Bonjour service + port + honest open-connection terminology.
        require(source, [
            "localized: \"Bonjour Service\"",
            "BabylonCaptureProtocol.serviceType",
            // The port shown is the one actually bound, which differs when the fixed port is taken.
            "receiver.listeningPort ?? receiver.preferredPort",
            "fallbackPortRow",
            "receiver.advertisedServiceName",
            "localized: \"Open Connections\"",
            "Open connections may still be authenticating.",
        ])
        forbid(source, [
            "Paired Clients",
            "Authenticated Clients",
            "paired client",
            "authenticated client",
        ])

        // Real listener-only Retry action wired to the receiver seam.
        require(source, [
            "localized: \"Retry Listener\"",
            "receiver.retryListener()",
        ])

        // Masked-by-default token with an accessible reveal control that has a
        // compact hit frame and a decorative icon hidden from accessibility.
        require(source, [
            "isTokenRevealed",
            "eye.slash",
            "Image(systemName: isTokenRevealed ? \"eye.slash\" : \"eye\")",
            ".textSelection(.enabled)",
            ".textSelection(.disabled)",
            "localized: \"Show Token\"",
            "localized: \"Hide Token\"",
            ".accessibilityLabel(String(localized: \"Pairing token\", bundle: RockxyLocalization.bundle))",
            ".frame(width: toolMetrics.compactButtonSize, height: toolMetrics.compactButtonSize)",
            ".accessibilityHidden(true)",
        ])

        // The card body scrolls (large fonts / long errors) while header and footer stay fixed.
        require(source, [
            "ScrollView(.vertical)",
        ])

        // Equal-dimension Copy / Regenerate footer buttons + local copy feedback.
        require(source, [
            "didCopyToken ? String(localized: \"Copied\", bundle: RockxyLocalization.bundle) : String(",
            "localized: \"Copy\"",
            "actionButtonLabel(String(localized: \"Regenerate…\", bundle: RockxyLocalization.bundle))",
            "private func actionButtonLabel",
            "didCopyToken",
            "String(localized: \"Copied\", bundle: RockxyLocalization.bundle)",
            ".disabled(store.token.isEmpty)",
            "String(localized: \"Pairing token copied\", bundle: RockxyLocalization.bundle)",
            ".privacySensitive()",
        ])

        // Destructive regeneration with an explicit consequence message.
        require(source, [
            "role: .destructive",
            "Existing connections disconnect immediately",
            "must be updated with the new token before it can reconnect",
        ])

        // Regenerate stays available even while the token is empty: only Copy is
        // gated by token emptiness.
        let actionsStart = try #require(source.range(of: "private var tokenActions: some View {"))
        let actionsBody = source[actionsStart.lowerBound...]
        let actionsEnd = try #require(actionsBody.range(of: "private var tokenUnavailableRow"))
        let actionsSource = actionsBody[..<actionsEnd.lowerBound]
        #expect(actionsSource
            .contains("actionButtonLabel(String(localized: \"Regenerate…\", bundle: RockxyLocalization.bundle))"))
        #expect(
            actionsSource.components(separatedBy: ".disabled(store.token.isEmpty)").count - 1 == 1,
            "Regenerate must not be disabled by an empty token"
        )

        // Conditional pasteboard privacy clean-up: concealed/transient markers,
        // expiry, and termination cleanup never destroy newer clipboard content.
        require(source, [
            "BabylonPairingClipboard.shared.copy(token)",
            "org.nspasteboard.TransientType",
            "org.nspasteboard.ConcealedType",
            "NSApplication.willTerminateNotification",
            "try? await Task.sleep(for: .seconds(60))",
            "pasteboard.changeCount == copiedChangeCount",
            "pasteboard.string(forType: .string) == copiedToken",
            "copyResetTask = nil",
            "didCopyToken = false",
            "isTokenRevealed = false",
        ])

        // Regenerate only resets reveal/copy state when the token actually changed.
        require(source, [
            "let previousToken = store.token",
            "guard store.token != previousToken else",
        ])
    }

    @Test("Babylon receiver retry restarts only the listener without a full teardown")
    func babylonReceiverRetryRestartsListenerOnly() throws {
        let source = try readProjectFile("Rockxy/Core/BabylonCapture/BabylonCaptureReceiver.swift")

        let retryStart = try #require(source.range(of: "func retryListener()"))
        let retryBody = source[retryStart.lowerBound...]
        let nextMember = try #require(retryBody.range(of: "// MARK: Private"))
        let retrySource = retryBody[..<nextMember.lowerBound]

        #expect(retrySource.contains("queue.async"))
        #expect(retrySource.contains("restartListener()"))
        // Retry must not fully tear down connections/sessions/observer.
        #expect(!retrySource.contains("stopInternal()"))
        #expect(!retrySource.contains("startListenerIfNeeded()"))
        #expect(!retrySource.contains("disconnectAllClients()"))
    }

    @Test("Babylon receiver guards listener generations and installs the observer once")
    func babylonReceiverGuardsListenerGeneration() throws {
        let source = try readProjectFile("Rockxy/Core/BabylonCapture/BabylonCaptureReceiver.swift")

        // Stale-listener callbacks are ignored before any state is published.
        #expect(source.contains("guard self.listener === listener else"))
        // New connections from a stale listener are cancelled before accept.
        #expect(source.contains("guard let self, let listener, self.listener === listener else"))
        // Pairing observer is installed once per lifetime, not per listener bind.
        #expect(source.contains("func installPairingObserverIfNeeded()"))
        #expect(source.contains("guard pairingObserver == nil else"))
        // Retry uses the listener-only restart path.
        #expect(source.contains("func restartListener()"))
        // An unexpected cancellation of the current listener is retryable Unavailable.
        #expect(source.contains("The Babylon listener stopped unexpectedly."))
        // Waiting is represented truthfully while the listener stays alive to recover.
        #expect(source.contains("case let .waiting(error)"))
        #expect(source.contains("publishListenerStatus(.waiting(error.localizedDescription))"))
        // Main-queue dispatch from the serial receiver queue preserves publication order.
        #expect(source.contains("dispatchPrecondition(condition: .onQueue(queue))"))
        #expect(source.contains("DispatchQueue.main.async"))
        #expect(!source.contains("Task { @MainActor [weak self] in"))
        // Honest, pre-authentication open-connection count.
        #expect(source.contains("openConnectionCount"))
        #expect(!source.contains("connectedClientCount"))
    }

    @Test("Pairing availability composes listener lifecycle with token presence")
    func availabilityComposesTokenPresence() {
        // A deliberate receiver stop is not a retryable failure.
        #expect(BabylonPairingAvailability(listenerStatus: .stopped, hasToken: true) == .stopped)
        #expect(BabylonPairingAvailability.stopped.listenerErrorMessage == nil)
        // Listener still coming up, token present → Starting.
        #expect(BabylonPairingAvailability(listenerStatus: .starting, hasToken: true) == .starting)
        // A waiting listener remains recoverable without presenting Retry.
        #expect(
            BabylonPairingAvailability(listenerStatus: .waiting("No viable network"), hasToken: true)
                == .waiting("No viable network")
        )
        // Listener ready + token present → Ready.
        #expect(BabylonPairingAvailability(listenerStatus: .ready, hasToken: true) == .ready)
        // A ready listener with no token would reject every frame → not Ready.
        #expect(BabylonPairingAvailability(listenerStatus: .ready, hasToken: false) == .tokenMissing)
        // A listener error dominates everything — including a missing token.
        #expect(
            BabylonPairingAvailability(listenerStatus: .failed("Bind failed"), hasToken: false)
                == .unavailable("Bind failed")
        )
        // Only a listener failure offers Retry.
        #expect(
            BabylonPairingAvailability(listenerStatus: .failed("Bind failed"), hasToken: true)
                .listenerErrorMessage == "Bind failed"
        )
        #expect(BabylonPairingAvailability.ready.listenerErrorMessage == nil)
        #expect(BabylonPairingAvailability.tokenMissing.listenerErrorMessage == nil)
        #expect(BabylonPairingAvailability.starting.listenerErrorMessage == nil)
        #expect(BabylonPairingAvailability.waiting("No network").listenerErrorMessage == nil)
        #expect(BabylonPairingAvailability.waiting("No network").waitingMessage == "No network")
    }

    @Test("Pairing clipboard clears only the token it copied")
    func pairingClipboardPreservesNewerContent() {
        let pasteboard = NSPasteboard(name: .init("BabylonPairingWindowReadabilityTests"))
        let clipboard = BabylonPairingClipboard(
            pasteboard: pasteboard,
            notificationCenter: NotificationCenter()
        )

        #expect(clipboard.copy("pairing-secret"))
        #expect(pasteboard.string(forType: .string) == "pairing-secret")
        #expect(pasteboard.data(forType: .init("org.nspasteboard.TransientType")) != nil)
        #expect(pasteboard.data(forType: .init("org.nspasteboard.ConcealedType")) != nil)

        pasteboard.clearContents()
        #expect(pasteboard.setString("newer-content", forType: .string))
        clipboard.clearCopiedTokenIfCurrent()
        #expect(pasteboard.string(forType: .string) == "newer-content")

        #expect(clipboard.copy("second-secret"))
        clipboard.clearCopiedTokenIfCurrent()
        #expect(pasteboard.string(forType: .string) == nil)
    }

    // MARK: Private

    private func require(_ source: String, _ needles: [String]) {
        for needle in needles {
            #expect(source.contains(needle), "missing \(needle)")
        }
    }

    private func forbid(_ source: String, _ needles: [String]) {
        for needle in needles {
            #expect(!source.contains(needle), "kept \(needle)")
        }
    }

    private func readProjectFile(_ relativePath: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        url.deleteLastPathComponent()
        return try String(contentsOf: url.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
