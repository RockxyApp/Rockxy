import SwiftUI

// Export submenu shared by sidebar domain and app rows: copy the row's
// identifier, or save its requests as a Rockxy session or HAR archive.

struct SidebarExportMenu: View {
    let copyTitle: String
    let copy: () -> Void
    let export: (TrafficExportFormat) -> Void

    var body: some View {
        Menu {
            Button(action: copy) {
                Label(copyTitle, systemImage: "doc.on.doc")
            }
            Button {
                export(.rockxySession)
            } label: {
                Label(
                    String(localized: "as Rockxy Session...", bundle: RockxyLocalization.bundle),
                    systemImage: "star.circle"
                )
            }
            Button {
                export(.har)
            } label: {
                Label(
                    String(localized: "as HAR (HTTP Archive)...", bundle: RockxyLocalization.bundle),
                    systemImage: "doc.badge.gearshape"
                )
            }
        } label: {
            Label(String(localized: "Export", bundle: RockxyLocalization.bundle), systemImage: "square.and.arrow.up")
        }
    }
}
