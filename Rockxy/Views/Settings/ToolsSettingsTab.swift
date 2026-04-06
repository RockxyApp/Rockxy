import SwiftUI

/// Debugging tools settings: request timeout, copy-as-cURL/HTTPie configuration,
/// Map Local file serving, scripting permissions, and export preferences.
///
/// ## Settings Wiring Status
///
/// | Key                    | Wired? | Consumer                          |
/// |------------------------|--------|-----------------------------------|
/// | appendHeaders          | DEFERRED | No runtime consumer — future feature |
/// | noCaching              | WIRED  | NoCacheHeaderMutator               |
/// | requestTimeout         | DEFERRED | No runtime consumer — future feature |
/// | copyLibrary            | DEFERRED | No runtime consumer — future feature |
/// | addProxyFlag           | DEFERRED | No runtime consumer — future feature |
/// | preserveOriginalRequest| DEFERRED | No runtime consumer — future feature |
/// | mapLocalPath           | DEFERRED | No runtime consumer — future feature |
/// | mapLocalDelay          | DEFERRED | No runtime consumer — future feature |
/// | allowScripts           | DEFERRED | No runtime consumer — future feature |
/// | autoOpenExport         | DEFERRED | No runtime consumer — future feature |
struct ToolsSettingsTab: View {
    // MARK: Internal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "DEBUGGING TOOLS"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 176)

                checkboxRow(
                    title: String(localized: "Append debug headers to requests"),
                    isOn: $appendHeaders
                )
                .disabled(true)
                .opacity(0.6)

                checkboxRow(
                    title: String(localized: "Disable caching (No-Cache headers)"),
                    isOn: $noCaching
                )

                Divider()

                settingsRow(label: String(localized: "Request Timeout:")) {
                    HStack {
                        TextField("", value: $requestTimeout, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text(String(localized: "seconds"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(true)
                .opacity(0.6)

                Divider()

                Text(String(localized: "COPY AS (Preview)"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 176)

                settingsRow(label: String(localized: "Copy Library:")) {
                    Picker("", selection: $copyLibrary) {
                        Text("cURL").tag("curl")
                        Text("HTTPie").tag("httpie")
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                .disabled(true)
                .opacity(0.6)

                checkboxRow(
                    title: String(localized: "Add --proxy flag"),
                    isOn: $addProxyFlag
                )
                .disabled(true)
                .opacity(0.6)

                checkboxRow(
                    title: String(localized: "Preserve Original Request"),
                    isOn: $preserveOriginalRequest
                )
                .disabled(true)
                .opacity(0.6)

                Divider()

                Text(String(localized: "MAP LOCAL (Preview)"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 176)

                settingsRow(label: String(localized: "Map Local Path:")) {
                    HStack {
                        Text(mapLocalPath.isEmpty ? String(localized: "Not set") : mapLocalPath)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(mapLocalPath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 300, alignment: .leading)
                        Button(String(localized: "Select Directory...")) {
                            selectMapLocalDirectory()
                        }
                    }
                }
                .disabled(true)
                .opacity(0.6)

                settingsRow(label: String(localized: "Map Local Delay:")) {
                    Picker("", selection: $mapLocalDelay) {
                        Text(String(localized: "None")).tag(0)
                        Text(String(localized: "1 second")).tag(1)
                        Text(String(localized: "2 seconds")).tag(2)
                        Text(String(localized: "5 seconds")).tag(5)
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                .disabled(true)
                .opacity(0.6)

                Divider()

                settingsRow(label: String(localized: "Scripting:")) {
                    Toggle(
                        String(localized: "Allow Scripts to modify requests and responses"),
                        isOn: $allowScripts
                    )
                    .toggleStyle(.checkbox)
                }
                .disabled(true)
                .opacity(0.6)

                Divider()

                settingsRow(label: String(localized: "Export Log:")) {
                    Toggle(
                        String(localized: "Auto open exported file"),
                        isOn: $autoOpenExport
                    )
                    .toggleStyle(.checkbox)
                }
                .disabled(true)
                .opacity(0.6)

                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
        }
    }

    // MARK: Private

    @AppStorage(RockxyIdentity.current.defaultsKey("appendHeaders")) private var appendHeaders =
        false // DEFERRED: No runtime consumer — future feature
    @AppStorage(RockxyIdentity.current.defaultsKey("noCaching")) private var noCaching = false // WIRED: NoCacheHeaderMutator
    @AppStorage(RockxyIdentity.current.defaultsKey("requestTimeout")) private var requestTimeout =
        30 // DEFERRED: No runtime consumer — future feature
    @AppStorage(RockxyIdentity.current.defaultsKey("copyLibrary")) private var copyLibrary =
        "curl" // DEFERRED: No runtime consumer — future feature
    @AppStorage(RockxyIdentity.current.defaultsKey("addProxyFlag")) private var addProxyFlag =
        false // DEFERRED: No runtime consumer — future feature
    @AppStorage(RockxyIdentity.current.defaultsKey("preserveOriginalRequest")) private var preserveOriginalRequest =
        false // DEFERRED: No runtime consumer — future feature
    @AppStorage(RockxyIdentity.current.defaultsKey("mapLocalPath")) private var mapLocalPath =
        "" // DEFERRED: No runtime consumer — future feature
    @AppStorage(RockxyIdentity.current.defaultsKey("mapLocalDelay")) private var mapLocalDelay =
        0 // DEFERRED: No runtime consumer — future feature
    @AppStorage(RockxyIdentity.current.defaultsKey("allowScripts")) private var allowScripts =
        false // DEFERRED: No runtime consumer — future feature
    @AppStorage(RockxyIdentity.current.defaultsKey("autoOpenExport")) private var autoOpenExport =
        true // DEFERRED: No runtime consumer — future feature

    private func settingsRow(
        label: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 160, alignment: .trailing)
                .padding(.trailing, 16)
                .padding(.top, 2)
            content()
        }
    }

    private func checkboxRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Color.clear.frame(width: 176)
            Toggle(title, isOn: isOn)
                .toggleStyle(.checkbox)
        }
    }

    private func selectMapLocalDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            mapLocalPath = url.path
        }
    }
}
