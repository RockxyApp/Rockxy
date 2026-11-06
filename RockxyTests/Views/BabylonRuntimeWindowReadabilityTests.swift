import Foundation
@testable import Rockxy
import Testing

// MARK: - BabylonRuntimeWindowReadabilityTests

/// Source-level contracts for the redesigned Babylon Runtime tool window: the
/// shared tool-window scene conventions, a native selectable Table + scrollable
/// detail inspector, exact-kind/source filters with Cmd-F search, a truthful
/// readiness banner with a pairing handoff, a global in-memory clear, and the
/// receiver-side runtime batching and clear-barrier seams that cannot be injected
/// without broad architecture changes.
struct BabylonRuntimeWindowReadabilityTests {
    // MARK: Internal

    @Test("Babylon Runtime scene uses the approved tool-window conventions")
    func babylonRuntimeSceneUsesToolWindowConventions() throws {
        let app = try readProjectFile("Rockxy/RockxyApp.swift")

        let sceneStart = try #require(
            app
                .range(
                    of: "String(localized: \"Babylon Runtime\", bundle: RockxyLocalization.bundle)"
                )
        )
        let scenesAfter = app[sceneStart.lowerBound...]
        let nextScene = try #require(
            scenesAfter
                .range(
                    of: "String(localized: \"Developer Setup\", bundle: RockxyLocalization.bundle)"
                )
        )
        let sceneSource = scenesAfter[..<nextScene.lowerBound]

        #expect(sceneSource.contains("ToolWindowDisplayMetricsProvider"))
        #expect(sceneSource.contains("BabylonRuntimeView(coordinator: mainCoordinator)"))
        #expect(sceneSource.contains(".commandsRemoved()"))
        #expect(sceneSource.contains(".windowResizability(.contentSize)"))
        #expect(sceneSource.contains(".defaultPosition(.center)"))
        #expect(sceneSource.contains(".windowToolbarStyle(.unifiedCompact)"))
        #expect(sceneSource.contains(".defaultSize(width: 920, height: 660)"))
    }

    @Test("Babylon Runtime view uses a native table, detail inspector, filters, and search")
    func babylonRuntimeViewUsesNativeWorkspace() throws {
        let source = try readProjectFile("Rockxy/Views/BabylonCapture/BabylonRuntimeView.swift")

        // Shared tool-window metrics + scalable min frame.
        require(source, [
            "ToolWindowDisplayMetrics",
            "@Environment(\\.appUIDisplayMetrics)",
            "toolMetrics.font(",
            "toolMetrics.tableHeaderFont()",
            "minWidth: max(900, min(1_120, toolMetrics.bodyFontSize * 15 + 720))",
            "minHeight: max(640, min(820, toolMetrics.bodyFontSize * 12 + 500))",
        ])

        // Native selectable Table over newest-first filtered arrivals, replacing the flat List.
        require(source, [
            "Table(filteredEvents, selection: $selection)",
            "filter.apply(to: Array(store.events.reversed()))",
            "String(localized: \"Kind\", bundle: RockxyLocalization.bundle)",
            "String(localized: \"Name\", bundle: RockxyLocalization.bundle)",
            "String(localized: \"Source\", bundle: RockxyLocalization.bundle)",
            "String(localized: \"Received\", bundle: RockxyLocalization.bundle)",
            "String(localized: \"Duration\", bundle: RockxyLocalization.bundle)",
            "String(localized: \"Outcome\", bundle: RockxyLocalization.bundle)",
            ".truncationMode(.middle)",
        ])
        forbid(source, [
            "List(store.events",
            ".frame(minWidth: 720, minHeight: 420)",
        ])

        // Scrollable detail inspector for the selected event.
        require(source, [
            "HSplitView",
            "private var detailInspector",
            "ScrollView(.vertical)",
            "String(localized: \"Overview\", bundle: RockxyLocalization.bundle)",
            "String(localized: \"Identifiers\", bundle: RockxyLocalization.bundle)",
            "String(localized: \"Timing\", bundle: RockxyLocalization.bundle)",
            "String(localized: \"Metadata\", bundle: RockxyLocalization.bundle)",
            "event.packageID",
            "event.receivedAt",
            "event.isContentTruncated",
            "event.truncatedFields",
            "event.sortedMetadata",
            ".textSelection(.enabled)",
            "String(localized: \"No Event Selected\", bundle: RockxyLocalization.bundle)",
        ])

        // Exact-kind + source filters and Cmd-F search.
        require(source, [
            "BabylonRuntimeEventFilter(",
            "BabylonRuntimePackageDTO.Kind.displayOrder",
            "String(localized: \"All Kinds\", bundle: RockxyLocalization.bundle)",
            "String(localized: \"All Sources\", bundle: RockxyLocalization.bundle)",
            "@FocusState private var searchIsFocused",
            ".keyboardShortcut(\"f\", modifiers: .command)",
            "TextField(String(localized: \"Search names, IDs, errors\", bundle: RockxyLocalization.bundle)",
        ])

        // Truthful raw vs filtered empty states + stable selection reconciliation.
        require(source, [
            "String(localized: \"No Runtime Events\", bundle: RockxyLocalization.bundle)",
            "String(localized: \"No Matching Events\", bundle: RockxyLocalization.bundle)",
            "filter.isActive",
            "reconcileSelection(with:",
            ".onChange(of: filteredEventIDs)",
            "reconcileSourceFilter(with:",
            ".onChange(of: availableSourceClientIDs)",
        ])

        // Compact readiness banner reusing pairing availability + an Open Pairing handoff.
        require(source, [
            "BabylonPairingAvailability(",
            "listenerStatus: receiver.listenerStatus",
            "hasToken: !pairingStore.token.isEmpty",
            "String(localized: \"Open Pairing\", bundle: RockxyLocalization.bundle)",
            "openWindow(id: \"babylonPairing\")",
        ])

        // Explicit global in-memory clear that routes through the receiver barrier
        // and never touches traffic or pairing.
        require(source, [
            "String(localized: \"Clear Runtime Events?\", bundle: RockxyLocalization.bundle)",
            "String(localized: \"Clear Events\", bundle: RockxyLocalization.bundle)",
            "receiver.clearRuntimeEvents()",
            "HTTP traffic and Babylon pairing are not affected.",
            "store.evictedEventCount",
        ])

        // No legacy hardcoded font ladder.
        forbid(source, [
            ".font(.headline)",
            ".font(.caption",
            "event.kind.rawValue",
            "String(localized: \"Running\", bundle: RockxyLocalization.bundle)",
        ])

        let commands = try readProjectFile("Rockxy/Views/BabylonCapture/BabylonCaptureCommands.swift")
        #expect(commands.contains("String(localized: \"Runtime Events…\", bundle: RockxyLocalization.bundle)"))
        #expect(!commands.contains("String(localized: \"Runtime Timeline…\", bundle: RockxyLocalization.bundle)"))
    }

    @Test("Receiver batches runtime events on its queue instead of one task per event")
    func receiverBatchesRuntimeEvents() throws {
        let source = try readProjectFile("Rockxy/Core/BabylonCapture/BabylonCaptureReceiver.swift")

        // Validated mapping before retention through the existing throwing path.
        #expect(source.contains("try BabylonRuntimeEvent(validating: package, source: identity)"))
        #expect(source.contains("enqueueRuntimeEvent(event)"))

        // Serial-queue batching seam.
        #expect(source.contains("private func enqueueRuntimeEvent"))
        #expect(source.contains("private func scheduleRuntimeFlush"))
        #expect(source.contains("private func flushRuntimeEvents"))
        #expect(source.contains("private func cancelRuntimeFlush"))
        #expect(source.contains("runtimeIntake"))
        #expect(source.contains("BabylonRuntimeIntakeBuffer(batchSize: BabylonCaptureReceiver.runtimeBatchSize)"))
        #expect(source.contains("dispatchPrecondition(condition: .onQueue(queue))"))
        #expect(source.contains("BabylonRuntimeEventStore.shared.appendBatch(batch)"))

        // No unstructured per-event MainActor task for runtime events.
        #expect(!source.contains("Task { @MainActor in\n            BabylonRuntimeEventStore.shared.append(event)"))

        // Bounded batch size + short max latency constants.
        #expect(source.contains("private static let runtimeBatchSize = 128"))
        #expect(source.contains("runtimeFlushMaxLatency: DispatchTimeInterval = .milliseconds(100)"))
        #expect(source.contains("static let maximumRuntimePayloadSize = 2 * 1_024 * 1_024"))
        #expect(source.contains("try Self.validateRuntimePayloadSize(payload.content.count)"))
        #expect(source.contains("runtimeFlushWorkItem?.cancel()"))
        #expect(source.contains("runtimePublicationGate.isCurrent(publicationGeneration)"))
    }

    @Test("Receiver clear forms an ingestion barrier and stays runtime-only")
    func receiverClearFormsIngestionBarrier() throws {
        let source = try readProjectFile("Rockxy/Core/BabylonCapture/BabylonCaptureReceiver.swift")

        let clearStart = try #require(source.range(of: "func clearRuntimeEvents()"))
        let clearBody = source[clearStart.lowerBound...]
        let nextMember = try #require(clearBody.range(of: "// MARK: Private"))
        let clearSource = clearBody[..<nextMember.lowerBound]

        // Serialized on the capture queue, discards pending, then clears the store.
        #expect(clearSource.contains("queue.async"))
        #expect(clearSource.contains("runtimeIntake.discardPending()"))
        #expect(clearSource.contains("cancelRuntimeFlush()"))
        #expect(clearSource.contains("runtimePublicationGate.advance()"))
        #expect(clearSource.contains("BabylonRuntimeEventStore.shared.clear()"))
        #expect(clearSource.contains("DispatchQueue.main.async"))
        // Runtime-only: it must not tear down connections/sessions or the listener.
        #expect(!clearSource.contains("disconnectAllClients()"))
        #expect(!clearSource.contains("stopInternal()"))
        #expect(!clearSource.contains("listener"))
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
