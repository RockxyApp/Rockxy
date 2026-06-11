import SwiftUI

// MARK: - DeveloperSetupAutomaticWindowView

struct DeveloperSetupAutomaticWindowView: View {
    // MARK: Lifecycle

    init(coordinator: MainContentCoordinator) {
        _viewModel = State(initialValue: DeveloperSetupSessionSetupViewModel(coordinator: coordinator))
    }

    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider()
                terminalSection
                browserSection
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Divider()
            footer
        }
        .frame(width: 760, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .centerOverRockxyMainWindowOnAppear()
        .task {
            viewModel.refresh()
        }
    }

    // MARK: Private

    @State private var viewModel: DeveloperSetupSessionSetupViewModel
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var setupMetrics: DeveloperSetupDisplayMetrics {
        DeveloperSetupDisplayMetrics(appMetrics: appMetrics)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: setupMetrics.prominentIconFontSize, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)

                Text(String(localized: "Automatic Setup"))
                    .font(.system(size: setupMetrics.titleFontSize, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 8) {
                benefitRow(
                    systemImage: "bolt.fill",
                    text: String(localized: "One click prepares HTTP proxy and certificate hints for a scoped dev session.")
                )
                benefitRow(
                    systemImage: "checkmark.circle.fill",
                    text: String(localized: "Capture HTTP(s) traffic from Node.js, Python, Ruby, Go, cURL, terminals, and browsers.")
                )
                benefitRow(
                    systemImage: "lock.shield.fill",
                    text: String(localized: "Safe by default: affects the launched session, not your OS settings.")
                )
            }
        }
    }

    private var terminalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Terminal App"))
                .font(.system(size: setupMetrics.sectionTitleFontSize, weight: .semibold))

            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "Open a prepared terminal session that points supported tools at Rockxy."))
                    .font(.system(size: setupMetrics.bodyFontSize))
                    .foregroundStyle(.secondary)

                Text(String(localized: "Supports Node.js, Ruby, Python, Go, cURL, and shell workflows that do not follow the system proxy."))
                    .font(.system(size: setupMetrics.bodyFontSize))
                    .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 12) {
                    Text(String(localized: "Use"))
                        .foregroundStyle(.secondary)

                    Picker("", selection: $viewModel.selectedTerminalApp) {
                        ForEach(SetupTerminalApp.allCases) { terminalApp in
                            Text(terminalApp.title).tag(terminalApp)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 170)

                    Text(String(localized: "and"))
                        .foregroundStyle(.secondary)

                    Button(String(localized: "Open Prepared Terminal...")) {
                        viewModel.openPreparedTerminal()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }

    private var browserSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Web Browsers"))
                .font(.system(size: setupMetrics.sectionTitleFontSize, weight: .semibold))

            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "Open a prepared browser profile with Rockxy proxy and certificate guidance scoped to that profile."))
                    .font(.system(size: setupMetrics.bodyFontSize))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Picker("", selection: $viewModel.selectedBrowserApp) {
                        ForEach(SetupBrowserApp.allCases) { browserApp in
                            Text(browserApp.title)
                                .tag(browserApp)
                                .disabled(!browserApp.isEnabled)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 260)

                    Button(String(localized: "Open Browser...")) {
                        viewModel.openPreparedBrowser()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.selectedBrowserApp.isEnabled)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.statusMessage ?? String(localized: "Rockxy will generate a scoped setup script before launching."))
                    .font(.system(size: setupMetrics.secondaryFontSize))
                    .foregroundStyle(.secondary)
                Text(String(localized: "Proxy: \(viewModel.proxyEndpointText). \(viewModel.certificateStatusText)"))
                    .font(.system(size: setupMetrics.metadataFontSize))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 12)

            Button(String(localized: "How does it work?")) {
                viewModel.copyManualCommand()
            }
            .buttonStyle(.bordered)

            Button(String(localized: "Troubleshooting")) {
                viewModel.copyManualCommand()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func benefitRow(systemImage: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: setupMetrics.iconFontSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(nsColor: .systemGreen))
                .frame(width: 18)

            Text(text)
                .font(.system(size: setupMetrics.bodyFontSize))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
