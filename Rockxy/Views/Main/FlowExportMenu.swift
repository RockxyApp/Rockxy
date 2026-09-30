import SwiftUI

// Flow ▸ Export submenu. Each format opens the export scope sheet, so the
// user picks all, filtered, or selected transactions before saving.

struct FlowExportMenu: View {
    let actions: MainContentCommandActions

    var body: some View {
        Menu(String(localized: "Export", bundle: RockxyLocalization.bundle)) {
            Button(String(localized: "Export as HAR…", bundle: RockxyLocalization.bundle)) {
                actions.exportHAR()
            }

            Button(String(localized: "Export as CSV…", bundle: RockxyLocalization.bundle)) {
                actions.exportCSV()
            }

            Button(String(localized: "Export as Postman Collection…", bundle: RockxyLocalization.bundle)) {
                actions.exportPostmanCollection()
            }

            Button(String(localized: "Export as Rockxy Session…", bundle: RockxyLocalization.bundle)) {
                actions.exportRockxySession()
            }

            Button(String(localized: "Export as OpenAPI YAML…", bundle: RockxyLocalization.bundle)) {
                actions.exportOpenAPIYAML()
            }
            .disabled(!actions.canExportOpenAPI)

            Button(String(localized: "Export as OpenAPI HTML…", bundle: RockxyLocalization.bundle)) {
                actions.exportOpenAPIHTML()
            }
            .disabled(!actions.canExportOpenAPI)

            Divider()

            Button(String(localized: "Publish Selected to Gist…", bundle: RockxyLocalization.bundle)) {
                actions.publishSelectedToGist()
            }
            .disabled(!actions.canPublishGist)
        }
    }
}
