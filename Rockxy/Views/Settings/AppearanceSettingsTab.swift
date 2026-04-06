import SwiftUI

/// Appearance settings for the inspector body view (font size, tab width, word wrap,
/// minimap) and application-wide theme selection (System / Light / Dark).
///
/// ## Settings Wiring Status
///
/// | Key                    | Wired? | Consumer                          |
/// |------------------------|--------|-----------------------------------|
/// | fontSize               | DEFERRED | No runtime consumer — future feature |
/// | tabWidth               | DEFERRED | No runtime consumer — future feature |
/// | useMonospacedFont      | DEFERRED | No runtime consumer — future feature |
/// | wordWrap               | DEFERRED | No runtime consumer — future feature |
/// | showInvisibles         | DEFERRED | No runtime consumer — future feature |
/// | showMinimap            | DEFERRED | No runtime consumer — future feature |
/// | scrollBeyondLastLine   | DEFERRED | No runtime consumer — future feature |
/// | alternateRowColors     | DEFERRED | No runtime consumer — future feature |
/// | appTheme               | YES    | NSApp.appearance in onChange handler |
struct AppearanceSettingsTab: View {
    // MARK: Internal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                editorSettings

                Divider()

                settingsRow(label: String(localized: "App Theme:")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 16) {
                            themeOption(title: String(localized: "System"), value: "system")
                            themeOption(title: String(localized: "Light"), value: "light")
                            themeOption(title: String(localized: "Dark"), value: "dark")
                        }
                    }
                }
                .onChange(of: appTheme) {
                    AppThemeApplier.apply(appTheme)
                }

                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
        }
    }

    // MARK: Private

    @AppStorage(RockxyIdentity.current.defaultsKey("fontSize")) private var fontSize = 12 // DEFERRED: No runtime consumer — future feature
    @AppStorage(RockxyIdentity.current.defaultsKey("tabWidth")) private var tabWidth = 2 // DEFERRED: No runtime consumer — future feature
    @AppStorage(RockxyIdentity.current.defaultsKey("useMonospacedFont")) private var useMonospacedFont =
        true // DEFERRED: No runtime consumer — future feature
    @AppStorage(RockxyIdentity.current.defaultsKey("wordWrap")) private var wordWrap =
        true // DEFERRED: No runtime consumer — future feature
    @AppStorage(RockxyIdentity.current.defaultsKey("showInvisibles")) private var showInvisibles =
        false // DEFERRED: No runtime consumer — future feature
    @AppStorage(RockxyIdentity.current.defaultsKey("showMinimap")) private var showMinimap =
        false // DEFERRED: No runtime consumer — future feature
    @AppStorage(RockxyIdentity.current.defaultsKey("scrollBeyondLastLine")) private var scrollBeyondLastLine =
        false // DEFERRED: No runtime consumer — future feature
    @AppStorage(RockxyIdentity.current.defaultsKey("alternateRowColors")) private var alternateRowColors =
        true // DEFERRED: No runtime consumer — future feature
    @AppStorage(RockxyIdentity.current.defaultsKey("appTheme")) private var appTheme = "system"

    private var editorSettings: some View {
        Group {
            settingsRow(label: String(localized: "Font Size:")) {
                HStack {
                    TextField("", value: $fontSize, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Stepper("", value: $fontSize, in: 8 ... 24)
                        .labelsHidden()
                }
            }

            settingsRow(label: String(localized: "Tab Width:")) {
                Picker("", selection: $tabWidth) {
                    Text(String(localized: "2 Spaces")).tag(2)
                    Text(String(localized: "4 Spaces")).tag(4)
                    Text(String(localized: "8 Spaces")).tag(8)
                }
                .labelsHidden()
                .frame(width: 120)
            }

            settingsRow(label: "") {
                Toggle(String(localized: "Use Monospaced Font"), isOn: $useMonospacedFont)
                    .toggleStyle(.checkbox)
            }

            Divider()

            Text(String(localized: "BODY TAB"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 176)

            checkboxRow(title: String(localized: "Word Wrap"), isOn: $wordWrap)
            checkboxRow(title: String(localized: "Show Invisibles"), isOn: $showInvisibles)
            checkboxRow(title: String(localized: "Show Minimap"), isOn: $showMinimap)
            checkboxRow(title: String(localized: "Scroll Beyond Last Line"), isOn: $scrollBeyondLastLine)

            Divider()

            settingsRow(label: String(localized: "Other:")) {
                Toggle(String(localized: "Alternative Rows Background Colors"), isOn: $alternateRowColors)
                    .toggleStyle(.checkbox)
            }
        }
        .disabled(true)
        .opacity(0.6)
    }

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

    private func themeOption(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .fill(value == "dark" ? Color(nsColor: .darkGray) : Color(nsColor: .windowBackgroundColor))
                .frame(width: 100, height: 64)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            appTheme == value ? Color.accentColor : Color(nsColor: .separatorColor),
                            lineWidth: appTheme == value ? 2 : 1
                        )
                )
                .onTapGesture { appTheme = value }

            HStack(spacing: 5) {
                Circle()
                    .strokeBorder(appTheme == value ? Color.accentColor : Color.gray, lineWidth: 1)
                    .background(Circle().fill(appTheme == value ? Color.accentColor : Color.clear).padding(4))
                    .frame(width: 14, height: 14)
                Text(title)
                    .font(.system(size: 12))
            }
            .onTapGesture { appTheme = value }
        }
    }
}
