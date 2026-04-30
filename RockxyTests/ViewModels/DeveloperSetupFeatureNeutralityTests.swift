import Foundation
import Testing

struct DeveloperSetupFeatureNeutralityTests {
    // MARK: Internal

    @Test("Developer Setup feature files stay free of packaging and entitlement terms")
    func featureFilesStayBounded() throws {
        let root = try resolveProjectRoot()
        let featureFiles = [
            root.appendingPathComponent("Rockxy/Models/UI/DeveloperSetupModels.swift"),
            root.appendingPathComponent("Rockxy/Models/UI/DeveloperSetupCatalog.swift"),
            root.appendingPathComponent("Rockxy/Models/UI/DeveloperSetupPinnedStore.swift"),
            root.appendingPathComponent("Rockxy/Models/UI/DeveloperSetupWorkflow.swift"),
            root.appendingPathComponent("Rockxy/Models/UI/DeveloperSetupMobileSnippetCatalog.swift"),
            root.appendingPathComponent("Rockxy/Models/UI/DeveloperSetupGuideCatalog.swift"),
            root.appendingPathComponent("Rockxy/ViewModels/DeveloperSetupViewModel.swift"),
            root.appendingPathComponent("Rockxy/Views/DeveloperSetup/DeveloperSetupAutomationSheet.swift"),
            root.appendingPathComponent("Rockxy/Views/DeveloperSetup/DeveloperSetupWindowView.swift"),
            root.appendingPathComponent("Rockxy/Views/DeveloperSetup/DeveloperSetupSourceList.swift"),
            root.appendingPathComponent("Rockxy/Views/DeveloperSetup/DeveloperSetupInspector.swift"),
        ]

        let forbiddenPatterns = [
            #/\bCommunity\b/#,
            #/\bEnterprise\b/#,
            #/\bPro\b/#,
            #/\bpremium\b/#,
            #/\bsubscription\b/#,
            #/\bentitlement\b/#,
        ]

        let violations = try featureFiles.compactMap { url -> String? in
            let raw = try String(contentsOf: url, encoding: .utf8)
            let sanitized = raw.replacingOccurrences(of: "Vision Pro", with: "VisionPro")
            let hit = forbiddenPatterns.first(where: { sanitized.contains($0) })
            return hit.map { "\(url.lastPathComponent): \($0)" }
        }

        #expect(violations.isEmpty, "Developer Setup files must stay free of packaging and entitlement language: \(violations)")
    }

    // MARK: Private

    private enum ResolveError: Error, CustomStringConvertible {
        case rootNotFound(filePath: String)

        // MARK: Internal

        var description: String {
            switch self {
            case let .rootNotFound(filePath):
                "Could not locate RockxyTests directory from \(filePath)"
            }
        }
    }

    private func resolveProjectRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        guard url.lastPathComponent == "RockxyTests" else {
            throw ResolveError.rootNotFound(filePath: #filePath)
        }
        url.deleteLastPathComponent()
        return url
    }
}
