import Foundation
import Testing

/// Lightweight smoke check that tier/edition logic has not leaked into
/// the helper, shared, or core layers. This is a sanity check, not a
/// strong architecture guarantee — the real rule is enforced by code
/// review and architecture docs.
struct HelperEditionNeutralityTests {
    // MARK: Internal

    // MARK: - Tests

    @Test("Shared/ does not reference ProductEdition or EditionCapabilities")
    func sharedIsNeutral() {
        let violations = Self.swiftFiles(in: "Shared").filter(Self.containsEditionImport)
        #expect(violations.isEmpty, "Shared/ must not reference edition types: \(violations.map(\.lastPathComponent))")
    }

    @Test("RockxyHelperTool/ does not reference ProductEdition or EditionCapabilities")
    func helperIsNeutral() {
        let violations = Self.swiftFiles(in: "RockxyHelperTool").filter(Self.containsEditionImport)
        #expect(
            violations.isEmpty,
            "RockxyHelperTool/ must not reference edition types: \(violations.map(\.lastPathComponent))"
        )
    }

    @Test("Core/ does not reference ProductEdition or EditionCapabilities")
    func coreIsNeutral() {
        let violations = Self.swiftFiles(in: "Rockxy/Core").filter(Self.containsEditionImport)
        #expect(violations.isEmpty, "Core/ must not reference edition types: \(violations.map(\.lastPathComponent))")
    }

    // MARK: Private

    private static let projectRoot: URL = {
        // RockxyTests is at <root>/RockxyTests; walk up to root
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests" {
            url.deleteLastPathComponent()
        }
        url.deleteLastPathComponent()
        return url
    }()

    private static func swiftFiles(in directory: String) -> [URL] {
        let dir = projectRoot.appendingPathComponent(directory)
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files
    }

    private static func containsEditionImport(_ url: URL) -> Bool {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }
        return contents.contains("ProductEdition") || contents.contains("EditionCapabilities")
    }
}
