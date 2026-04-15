import SwiftUI

/// Attaches the `.openScriptingListWindow` and `.openScriptEditorWindow`
/// notification receivers to a view. Extracted into a separate modifier so
/// `ContentView`'s body keeps a manageable expression depth — SwiftUI's type
/// checker chokes on many chained `.onReceive` modifiers.
struct ScriptingWindowOpeners: ViewModifier {
    let openWindow: OpenWindowAction

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openScriptingListWindow)) { _ in
                openWindow(id: "scriptingList")
            }
            .onReceive(NotificationCenter.default.publisher(for: .openScriptEditorWindow)) { _ in
                openWindow(id: "scriptEditor")
            }
    }
}
