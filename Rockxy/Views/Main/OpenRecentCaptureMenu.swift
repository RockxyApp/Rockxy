import SwiftUI

// MARK: - OpenRecentCaptureMenu

/// File ▸ Open Recent for capture documents.
struct OpenRecentCaptureMenu: View {
    let recents: RecentCaptureDocuments

    var body: some View {
        Menu(String(localized: "Open Recent", bundle: RockxyLocalization.bundle)) {
            ForEach(recents.urls, id: \.self) { url in
                Button(url.lastPathComponent) {
                    ExternalDocumentOpenRouter.shared.open([url])
                }
            }
            if !recents.urls.isEmpty {
                Divider()
            }
            Button(String(localized: "Clear Menu", bundle: RockxyLocalization.bundle)) {
                recents.clear()
            }
            .disabled(recents.urls.isEmpty)
        }
    }
}
