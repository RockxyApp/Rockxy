import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - DeveloperSetupAutomaticWindowView

struct DeveloperSetupAutomaticWindowView: View {
    // MARK: Lifecycle

    init(coordinator: MainContentCoordinator) {
        _viewModel = State(initialValue: DeveloperSetupSessionSetupViewModel(coordinator: coordinator))
    }

    // MARK: Internal

    var body: some View {
        setupLayout
            .frame(minWidth: 620, minHeight: 440)
            .background(Color(nsColor: .windowBackgroundColor))
            .font(setupMetrics.font())
            .centerOverRockxyMainWindowOnAppear()
            .task {
                viewModel.applyRoute(routeStore.consumeAutomaticRoute(), destination: .automatic)
                viewModel.refresh()
            }
            .onChange(of: routeStore.automaticRoute) { _, _ in
                viewModel.applyRoute(routeStore.consumeAutomaticRoute(), destination: .automatic)
            }
    }

    // MARK: Private

    @State private var viewModel: DeveloperSetupSessionSetupViewModel
    @State private var routeStore = DeveloperSetupRouteStore.shared
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var setupMetrics: DeveloperSetupDisplayMetrics {
        DeveloperSetupDisplayMetrics(appMetrics: appMetrics)
    }

    private var openTerminalTitle: String {
        viewModel.selectedTerminalApp == .custom
            ? String(localized: "Copy Setup Command", bundle: RockxyLocalization.bundle)
            : String(localized: "Open Prepared Terminal…", bundle: RockxyLocalization.bundle)
    }

    @ViewBuilder private var setupLayout: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            ScrollView {
                setupSections
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .safeAreaBar(edge: .top, spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                footer
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
        } else {
            legacySetupLayout
        }
        #else
        legacySetupLayout
        #endif
    }

    private var legacySetupLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                setupSections
                footer
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "gearshape.2.fill")
                    .font(setupMetrics.font(size: setupMetrics.prominentIconFontSize))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Automatic Setup", bundle: RockxyLocalization.bundle))
                        .font(setupMetrics.font(size: setupMetrics.titleFontSize, weight: .semibold))
                    Text(viewModel.target.title)
                        .font(setupMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.isRuntimeTerminalTarget {
                Text(
                    String(
                        localized: "Rockxy prepares a scoped shell for \(viewModel.target.title) pointed at the local proxy.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                .font(setupMetrics.font())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Text(
                    String(
                        localized: """
                        Automatic Setup only affects the session it launches. An app that is already running \
                        keeps its current environment, and some GUI apps ignore shell variables — use macOS \
                        System Proxy or this target's Manual Setup for those.
                        """,
                        bundle: RockxyLocalization.bundle
                    )
                )
                .font(setupMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if viewModel.target.id == .javaVMs {
                    Text(
                        String(
                            localized: """
                            For Java, HTTPS interception still needs the Rockxy root CA trusted in the exact \
                            JVM or IDE trust store, plus a Decrypt rule for the target application or \
                            host under HTTPS Decryption.
                            """,
                            bundle: RockxyLocalization.bundle
                        )
                    )
                    .font(setupMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var terminalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "\(viewModel.target.title) terminal session", bundle: RockxyLocalization.bundle))
                .font(setupMetrics.font(size: setupMetrics.sectionTitleFontSize, weight: .semibold))

            VStack(alignment: .leading, spacing: 10) {
                Text(
                    String(
                        localized: "Open a prepared terminal that points \(viewModel.target.title) at Rockxy before you run your app or script.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                .font(setupMetrics.font())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Divider()

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        Text(String(localized: "Use", bundle: RockxyLocalization.bundle))
                            .foregroundStyle(.secondary)
                        terminalPicker
                        terminalActionButton
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        terminalPicker
                        terminalActionButton
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }

    private var setupSections: some View {
        VStack(alignment: .leading, spacing: 16) {
            terminalSection
            developerApplicationSection
        }
    }

    private var developerApplicationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Developer application", bundle: RockxyLocalization.bundle))
                .font(setupMetrics.font(size: setupMetrics.sectionTitleFontSize, weight: .semibold))

            VStack(alignment: .leading, spacing: 10) {
                Text(viewModel.developerApplicationGuidanceText)
                    .font(setupMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(String(localized: "Choose & Open Developer App…", bundle: RockxyLocalization.bundle)) {
                    chooseAndOpenDeveloperApplication()
                }
                .help(
                    String(
                        localized: "Opens a fresh app instance with scoped proxy and certificate settings; recognized app-level proxy settings are prepared safely.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                .rockxyGlassButtonStyle(prominent: true)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }

    private var terminalPicker: some View {
        Picker(
            String(localized: "Terminal app", bundle: RockxyLocalization.bundle),
            selection: $viewModel.selectedTerminalApp
        ) {
            ForEach(SetupTerminalApp.allCases) { terminalApp in
                Text(terminalApp.title).tag(terminalApp)
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel(String(localized: "Terminal app", bundle: RockxyLocalization.bundle))
    }

    private var terminalActionButton: some View {
        Button(openTerminalTitle) {
            Task { await viewModel.openPreparedTerminal() }
        }
        .keyboardShortcut(.defaultAction)
        .rockxyGlassButtonStyle(prominent: true)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel
                .statusMessage ?? String(
                    localized: "Rockxy generates a scoped setup script before launching.",
                    bundle: RockxyLocalization.bundle
                ))
                .font(setupMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(String(
                localized: "Proxy: \(viewModel.proxyEndpointText). \(viewModel.certificateStatusText)",
                bundle: RockxyLocalization.bundle
            ))
            .font(setupMetrics.font(size: setupMetrics.metadataFontSize))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chooseAndOpenDeveloperApplication() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose a developer application", bundle: RockxyLocalization.bundle)
        panel.prompt = String(localized: "Open with Rockxy", bundle: RockxyLocalization.bundle)
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true

        guard panel.runModal() == .OK, let appURL = panel.url else {
            return
        }
        Task {
            await viewModel.openDeveloperApplication(at: appURL)
        }
    }
}
