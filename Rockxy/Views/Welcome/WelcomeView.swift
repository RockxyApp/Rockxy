import ServiceManagement
import SwiftUI

// Renders the welcome interface for first-run onboarding.

// MARK: - WelcomeStepItem

private struct WelcomeStepItem: Identifiable {
    let id: Int
    let title: String
    let actionLabel: String?
    let isCompleted: Bool
    let isDisabled: Bool
    let action: (() async -> Void)?
}

// MARK: - WelcomeView

struct WelcomeView: View {
    // MARK: Internal

    var isFirstLaunch = false
    var onComplete: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            stepsList
            Divider()
            footerSection
        }
        .frame(width: 520, height: 480)
        .task {
            await viewModel.loadInitialStatus()
        }
        .onChange(of: ReadinessCoordinator.shared.certReadiness) {
            viewModel.syncFromCoordinator()
        }
        .onChange(of: ReadinessCoordinator.shared.helperReadiness) {
            viewModel.syncFromCoordinator()
        }
        .onChange(of: ReadinessCoordinator.shared.proxyMode) {
            viewModel.syncFromCoordinator()
        }
    }

    // MARK: Private

    @State private var viewModel = WelcomeViewModel()
    @AppStorage("showWelcomeOnLaunch") private var showWelcomeOnLaunch = true
    @AppStorage(RockxyIdentity.current.defaultsKey("onboardingCompletedOnce")) private var onboardingCompletedOnce =
        false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    private var steps: [WelcomeStepItem] {
        [
            WelcomeStepItem(
                id: 1,
                title: String(localized: "Generate Root Certificate"),
                actionLabel: viewModel.certInstalled ? nil : String(localized: "Install"),
                isCompleted: viewModel.certInstalled,
                isDisabled: false,
                action: { await viewModel.installCert() }
            ),
            WelcomeStepItem(
                id: 2,
                title: String(localized: "Trust Root Certificate"),
                actionLabel: viewModel.certTrusted ? nil : String(localized: "Trust"),
                isCompleted: viewModel.certTrusted,
                isDisabled: !viewModel.certInstalled,
                action: { await viewModel.installCert() }
            ),
            WelcomeStepItem(
                id: 3,
                title: String(localized: "Install Helper Tool"),
                actionLabel: helperActionLabel,
                isCompleted: viewModel.helperStatus == .installedCompatible,
                isDisabled: false,
                action: {
                    if viewModel.helperStatus == .requiresApproval {
                        SMAppService.openSystemSettingsLoginItems()
                    } else if viewModel.helperStatus == .installedOutdated || viewModel
                        .helperStatus == .installedIncompatible
                    {
                        await viewModel.updateHelper()
                    } else {
                        await viewModel.installHelper()
                    }
                }
            ),
            WelcomeStepItem(
                id: 4,
                title: String(localized: "Enable System Proxy"),
                actionLabel: viewModel.systemProxyEnabled ? nil : String(localized: "Enable"),
                isCompleted: viewModel.systemProxyEnabled,
                isDisabled: false,
                action: { await viewModel.enableProxy() }
            ),
        ]
    }

    private var helperActionLabel: String? {
        switch viewModel.helperStatus {
        case .installedCompatible:
            nil
        case .installedOutdated,
             .installedIncompatible:
            String(localized: "Update")
        case .notInstalled:
            String(localized: "Install")
        case .requiresApproval:
            String(localized: "Open Settings")
        case .unreachable:
            String(localized: "Retry")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "Version \(version) (\(build))"
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Spacer()
                .frame(height: 8)

            Image(nsImage: AppIconProvider.appIcon)
                .resizable()
                .frame(width: 80, height: 80)

            Text(String(localized: "Welcome to Rockxy"))
                .font(.title)
                .fontWeight(.bold)

            Text(String(localized: "Complete the steps below to set up network debugging."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            progressSection

            Spacer()
                .frame(height: 4)
        }
        .padding(.horizontal, 40)
    }

    private var progressSection: some View {
        VStack(spacing: 6) {
            ProgressView(
                value: Double(viewModel.completedSteps),
                total: Double(viewModel.totalSteps)
            )
            .tint(.accentColor)

            Text(
                String(
                    localized: "\(viewModel.completedSteps) of \(viewModel.totalSteps) steps complete"
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
    }

    private var stepsList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(steps) { step in
                    stepRow(step)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 40)
        }
        .frame(maxHeight: .infinity)
    }

    private var footerSection: some View {
        VStack(spacing: 12) {
            Spacer()
                .frame(height: 4)

            if let errorMessage = viewModel.errorMessage {
                VStack(spacing: 6) {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    Button {
                        openWindow(id: "advancedProxySettings")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.system(size: 10))
                            Text(String(localized: "View Advanced Diagnostics"))
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 40)
            }

            if viewModel.helperStatus == .requiresApproval {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 10))
                    Text(
                        String(
                            localized: "macOS requires you to approve the helper tool in System Settings \u{2192} General \u{2192} Login Items."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 40)
            }

            HStack {
                Toggle(isOn: $showWelcomeOnLaunch) {
                    Text(String(localized: "Show on startup"))
                        .font(.caption)
                }
                .toggleStyle(.checkbox)

                Spacer()

                Button(String(localized: "Get Started")) {
                    onboardingCompletedOnce = true
                    if let onComplete {
                        onComplete()
                    } else {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canGetStarted)
            }
            .padding(.horizontal, 40)

            Text(appVersion)
                .font(.caption2)
                .foregroundStyle(.quaternary)

            Spacer()
                .frame(height: 8)
        }
    }

    private func stepRow(_ step: WelcomeStepItem) -> some View {
        HStack(spacing: 12) {
            statusIcon(for: step)
                .font(.title3)

            Text(step.title)
                .foregroundStyle(step.isDisabled ? .tertiary : .primary)

            Spacer()

            if let actionLabel = step.actionLabel, !step.isDisabled {
                Button(actionLabel) {
                    Task {
                        await step.action?()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isPerformingAction)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(step.isCompleted ? Color.green.opacity(0.06) : Color.clear)
        )
    }

    private func statusIcon(for step: WelcomeStepItem) -> some View {
        Group {
            if step.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if step.isDisabled {
                Image(systemName: "circle")
                    .foregroundStyle(.tertiary)
            } else {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.yellow)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    WelcomeView()
}
