import Foundation
@testable import Rockxy
import Testing

// MARK: - ResponseBodyEditorTests

struct ResponseBodyEditorTests {
    @Test("Open With lists only editors installed on this Mac, in a stable order")
    func filtersToInstalledEditors() {
        let installed = ResponseBodyEditor.installed { ["com.apple.TextEdit", "com.apple.dt.Xcode"].contains($0) }

        #expect(installed.map(\.name) == ["TextEdit", "Xcode"])
        #expect(ResponseBodyEditor.installed { _ in false }.isEmpty)
    }
}
