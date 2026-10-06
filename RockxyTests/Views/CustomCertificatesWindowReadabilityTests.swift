import Foundation
import Testing

// MARK: - CustomCertificatesWindowReadabilityTests

struct CustomCertificatesWindowReadabilityTests {
    // MARK: Internal

    @Test("Custom Certificates uses a compact native hierarchy without a duplicate title")
    func nativeHierarchyHasNoDuplicateTitle() throws {
        let source = try readProjectFile("Rockxy/Views/Certificate/CustomCertificatesView.swift")

        #expect(source.contains("modePicker"))
        #expect(source.contains("Table(entries, selection: selection)"))
        #expect(source.contains("certificateEmptyState("))
        #expect(source.contains("toolMetrics.emptyStateFontSize"))
        #expect(source.contains("ToolWindowDisplayMetrics"))
        #expect(source.contains(".confirmationDialog("))
        #expect(source.contains(".onDeleteCommand"))
        #expect(source.contains("HelpLink(destination: helpURL)"))
        #expect(!source.contains("Text(String(localized: \"Custom Certificates\", bundle: RockxyLocalization.bundle))"))
        #expect(!source.contains("private var toolbar"))
        #expect(!source.contains(".frame(width: 560)"))
        #expect(!source.contains(".font(.title3)"))
        #expect(!source.contains(".font(.headline)"))
        #expect(!source.contains(".font(.callout)"))
        #expect(!source.contains(".font(.caption)"))
    }

    @Test("Import actions are direct buttons, not a pull-down holding one or two items")
    func importActionsAreDirectButtons() throws {
        let source = try readProjectFile("Rockxy/Views/Certificate/CustomCertificatesView.swift")

        // A one-item pull-down hid the only Root import behind an extra click that VoiceOver and
        // accessibility automation could not press directly.
        #expect(source.contains("private var importButtons: some View"))
        #expect(source.contains("importPEMOrDER(kind: viewModel.mode.kind)"))
        #expect(source.contains("importPKCS12(kind: viewModel.mode.kind)"))
        #expect(!source.contains("Menu {"))
        #expect(!source.contains(".menuStyle(.button)"))
    }

    @Test("Selection-safe actions never fall back to newest or delete an entire list")
    func actionsAreSelectionSafe() throws {
        let viewSource = try readProjectFile("Rockxy/Views/Certificate/CustomCertificatesView.swift")
        let modelSource = try readProjectFile("Rockxy/Views/Certificate/CustomCertificatesViewModel.swift")

        #expect(modelSource.contains("selectedServerID"))
        #expect(modelSource.contains("selectedClientID"))
        #expect(modelSource.contains("case certificate(UUID)"))
        #expect(modelSource.contains("try manager.delete(id: id)"))
        #expect(modelSource.contains("reconcileSelection()"))
        #expect(!viewSource.contains("currentEntries.last"))
        #expect(!viewSource.contains("deleteAll(kind: selectedTab.kind)"))
    }

    @Test("Import and refresh work preserve responsive and honest state")
    func importAndRefreshAreBoundedAndStaleSafe() throws {
        let source = try readProjectFile("Rockxy/Views/Certificate/CustomCertificatesViewModel.swift")

        #expect(source.contains("Task.detached(priority: .userInitiated)"))
        #expect(source.contains("readBoundedData"))
        #expect(source.contains("16 * 1_024 * 1_024"))
        #expect(source.contains("rootRefreshGeneration"))
        #expect(source.contains("importGeneration"))
        #expect(source.contains("generation == importGeneration"))
        #expect(source.contains("SSLHostPatternValidation.message"))
        #expect(!source.contains("ensureRootCA()"))
        #expect(source.contains("No Default Root Available"))
    }

    @Test("Custom Certificates scene has predictable native utility geometry")
    func sceneUsesPredictableUtilityGeometry() throws {
        let source = try readProjectFile("Rockxy/RockxyApp.swift")

        #expect(source.contains("CustomCertificatesWindowScene"))
        #expect(source.contains("id: \"customCertificates\""))
        #expect(source.contains(".defaultSize(width: 900, height: 620)"))
        #expect(source.contains(".windowToolbarStyle(.unifiedCompact)"))
        #expect(source.contains(".windowResizability(.contentMinSize)"))
        #expect(source.contains("base.restorationBehavior(.disabled)"))
    }

    // MARK: Private

    private func readProjectFile(_ relativePath: String) throws -> String {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repositoryRoot = testsDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
