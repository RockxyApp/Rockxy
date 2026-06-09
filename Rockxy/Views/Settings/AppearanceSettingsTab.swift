import SwiftUI

/// Application-wide appearance and readability settings.
struct AppearanceSettingsTab: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(localized: "App UI"))
                        .font(.system(size: 13, weight: .medium))

                    appUISection

                    Text(String(localized: "App Theme"))
                        .font(.system(size: 13, weight: .medium))

                    themeSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            restoreDefaultsButton
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 24)
        }
        .appUIDisplayMetrics(AppUIDisplayMetrics(settings: settingsManager.settings.appUI))
    }

    // MARK: Private

    private let settingsManager = AppSettingsManager.shared

    private var appUI: AppUISettings {
        settingsManager.settings.appUI
    }

    private var appTheme: AppTheme {
        settingsManager.settings.appTheme
    }

    private var appUISection: some View {
        VStack(alignment: .leading, spacing: 10) {
            appearanceControlGroup {
                HStack(alignment: .top, spacing: 28) {
                    HStack(spacing: 8) {
                        Text(String(localized: "Font Size:"))
                            .frame(width: 84, alignment: .trailing)
                        Picker("", selection: fontSizeBinding) {
                            ForEach(AppUISettings.allowedFontSizes, id: \.self) { size in
                                Text("\(size)").tag(size)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 72)
                    }

                    HStack(spacing: 8) {
                        Text(String(localized: "Tab Width:"))
                        Picker("", selection: tabWidthBinding) {
                            ForEach(AppUISettings.allowedTabWidths, id: \.self) { width in
                                Text(String(localized: "\(width) Spaces")).tag(width)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 112)
                    }
                }

                optionRow(label: "") {
                    Toggle(String(localized: "Use Monospaced Font"), isOn: appUIToggle(\.useMonospacedFont))
                        .toggleStyle(.checkbox)
                }

                Text(String(localized: "Apply to all tabs in the Request and Response Panel and the main table."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 192)
            }

            appearanceControlGroup {
                optionRow(label: String(localized: "Body Tab:")) {
                    VStack(alignment: .leading, spacing: 5) {
                        Toggle(String(localized: "Word Wrap"), isOn: appUIToggle(\.bodyWordWrap))
                        Toggle(String(localized: "Show Invisibles"), isOn: appUIToggle(\.bodyShowInvisibles))
                        Toggle(String(localized: "Show Minimap"), isOn: appUIToggle(\.bodyShowMinimap))
                        Toggle(String(localized: "Scroll Beyond The Last Line"), isOn: appUIToggle(\.bodyScrollBeyondLastLine))
                    }
                    .toggleStyle(.checkbox)
                }
            }

            appearanceControlGroup {
                optionRow(label: String(localized: "Other:")) {
                    Toggle(
                        String(localized: "Alternative Rows Background Colors"),
                        isOn: appUIToggle(\.useAlternatingRowBackgroundColors)
                    )
                    .toggleStyle(.checkbox)
                }
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 112)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.82),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.22), lineWidth: 0.5)
        }
    }

    private var themeSection: some View {
        HStack(spacing: 56) {
            ForEach(AppTheme.allCases) { theme in
                themeOption(theme)
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .overlay {
            Rectangle()
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    private var restoreDefaultsButton: some View {
        HStack(spacing: 8) {
            Button(String(localized: "Restore Defaults")) {
                settingsManager.restoreAppearanceDefaults()
            }
            .controlSize(.regular)

            Button {
                settingsManager.restoreAppearanceDefaults()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help(String(localized: "Restore Defaults"))

            Spacer()
        }
        .font(.system(size: 13))
    }

    private var fontSizeBinding: Binding<Int> {
        Binding(
            get: { appUI.fontSize },
            set: { newValue in
                settingsManager.updateAppUI { $0.fontSize = newValue }
            }
        )
    }

    private var tabWidthBinding: Binding<Int> {
        Binding(
            get: { appUI.tabWidth },
            set: { newValue in
                settingsManager.updateAppUI { $0.tabWidth = newValue }
            }
        )
    }

    private func appUIToggle(_ keyPath: WritableKeyPath<AppUISettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { appUI[keyPath: keyPath] },
            set: { newValue in
                settingsManager.updateAppUI { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func optionRow<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    )
        -> some View
    {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .frame(width: 84, alignment: .trailing)
            content()
        }
    }

    private func appearanceControlGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func themeOption(_ theme: AppTheme) -> some View {
        Button {
            settingsManager.updateAppTheme(theme)
        } label: {
            VStack(spacing: 8) {
                ThemePreviewCard(theme: theme)
                    .frame(width: 78, height: 54)

                HStack(spacing: 6) {
                    if appTheme == theme {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(nsColor: .systemGreen))
                    }
                    Text(theme.displayName)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                }
                .frame(minWidth: 82)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.displayName)
        .accessibilityAddTraits(appTheme == theme ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - ThemePreviewCard

private struct ThemePreviewCard: View {
    let theme: AppTheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(background)

            if theme == .system {
                GeometryReader { proxy in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: proxy.size.height))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: 0))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(Color(nsColor: .controlBackgroundColor))
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 4) {
                Circle().fill(Color(nsColor: .systemRed))
                Circle().fill(Color(nsColor: .systemYellow))
                Circle().fill(Color(nsColor: .systemGreen))
            }
            .frame(width: 34, height: 6)
            .padding(7)

            if theme != .system {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HTTP/1.1 OK 200")
                        .foregroundStyle(.green)
                    Text("Vary: Origin")
                        .foregroundStyle(.purple)
                    Text("Connection: close")
                        .foregroundStyle(.blue)
                }
                .font(.system(size: 4.5, design: .monospaced))
                .padding(.top, 22)
                .padding(.leading, 11)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }

    private var background: Color {
        switch theme {
        case .system, .light:
            Color(nsColor: .textBackgroundColor)
        case .dark:
            Color(nsColor: .windowBackgroundColor)
        }
    }
}
