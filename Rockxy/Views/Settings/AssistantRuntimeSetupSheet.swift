import AppKit
import SwiftUI

// MARK: - AssistantRuntimeSetupState

enum AssistantRuntimeSetupState: Equatable {
    case idle
    case downloading(receivedBytes: Int64, totalBytes: Int64?)
    case verifying
    case installing
    case starting
    case ready(version: String)
    case failed(message: String)

    var isBusy: Bool {
        switch self {
        case .downloading,
             .verifying,
             .installing,
             .starting:
            true
        case .idle,
             .ready,
             .failed:
            false
        }
    }
}

// MARK: - AssistantRuntimeApplicationOpening

protocol AssistantRuntimeApplicationOpening {
    @MainActor
    func open(applicationURL: URL) async throws
}

struct NSWorkspaceAssistantRuntimeApplicationOpener: AssistantRuntimeApplicationOpening {
    func open(applicationURL: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.arguments = ["hidden"]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(
                at: applicationURL,
                configuration: configuration
            ) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

// MARK: - AssistantRuntimeSetupSheet

struct AssistantRuntimeSetupSheet: View {
    // MARK: Internal

    @Bindable var viewModel: AssistantSettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                header
                installationSummary
                installLocation
                setupStatus
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 18)

            Divider()

            actionBar
        }
        .font(settingsMetrics.font())
        .frame(width: max(500, settingsMetrics.fieldWidth(500)))
        .background(Color(nsColor: .windowBackgroundColor))
        .interactiveDismissDisabled(viewModel.runtimeSetupState.isBusy)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private let runtime = AssistantLocalRuntimeDescriptor.ollama

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Install Ollama"))
                .font(.system(size: max(16, settingsMetrics.bodyFontSize + 3), weight: .semibold))
            Text(
                String(
                    localized: "Ollama runs local models used by Rockxy. The app is downloaded from ollama.com."
                )
            )
            .font(settingsMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var installationSummary: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            detailRow(
                String(localized: "Application"),
                value: runtime.applicationName
            )
            detailRow(
                String(localized: "Download"),
                value: approximateSize(runtime.approximateDownloadBytes)
            )
            detailRow(
                String(localized: "Disk Space"),
                value: String(
                    localized: "\(approximateSize(runtime.approximateInstalledBytes)), excluding models"
                )
            )
        }
        .font(settingsMetrics.secondaryFont())
    }

    private var installLocation: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "Install in:"))
                .font(settingsMetrics.secondaryFont(weight: .medium))

            HStack(spacing: 8) {
                AssistantInstallPathControl(
                    url: viewModel.runtimeInstallDestination,
                    fontSize: settingsMetrics.bodyFontSize
                )
                .frame(maxWidth: .infinity)
                .frame(height: settingsMetrics.controlHeight)

                Button(String(localized: "Choose…")) {
                    viewModel.chooseRuntimeInstallDestination()
                }
                .disabled(viewModel.runtimeSetupState.isBusy)
            }

            Text(
                String(
                    localized: "Models are installed separately by Ollama and may require several GB each."
                )
            )
            .font(settingsMetrics.metadataFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var setupStatus: some View {
        switch viewModel.runtimeSetupState {
        case .idle:
            Label(
                String(localized: "The developer signature and Gatekeeper approval are checked before installation."),
                systemImage: "checkmark.shield"
            )
            .font(settingsMetrics.secondaryFont())
            .foregroundStyle(.secondary)
        case let .downloading(receivedBytes, totalBytes):
            VStack(alignment: .leading, spacing: 7) {
                if let totalBytes, totalBytes > 0 {
                    ProgressView(value: min(1, Double(receivedBytes) / Double(totalBytes)))
                } else {
                    ProgressView()
                }
                Text(downloadStatus(receivedBytes: receivedBytes, totalBytes: totalBytes))
                    .font(settingsMetrics.metadataFont())
                    .foregroundStyle(.secondary)
            }
        case .verifying:
            progressStatus(
                String(localized: "Verifying archive, developer signature, and Gatekeeper approval…")
            )
        case .installing:
            progressStatus(String(localized: "Installing the verified application…"))
        case .starting:
            progressStatus(String(localized: "Starting Ollama and checking the local service…"))
        case let .ready(version):
            Label(String(localized: "Ollama \(version) is ready on this Mac."), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case let .failed(message):
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                if viewModel.ollamaApplicationURL != nil {
                    Text(String(localized: "The verified app remains installed. Rockxy can open it and check the service again without downloading it twice."))
                        .font(settingsMetrics.metadataFont())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Spacer()

            if viewModel.runtimeSetupState.isBusy {
                Button(String(localized: "Cancel")) {
                    viewModel.cancelRuntimeInstall()
                }
                .keyboardShortcut(.cancelAction)
            } else {
                Button(String(localized: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            switch viewModel.runtimeSetupState {
            case .ready:
                Button(String(localized: "Done")) {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            case .failed where viewModel.ollamaApplicationURL != nil:
                Button(String(localized: "Open & Check Again")) {
                    viewModel.retryInstalledOllamaRuntime()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            default:
                Button(String(localized: "Install")) {
                    viewModel.installOllamaRuntime()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.runtimeSetupState.isBusy)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    private func detailRow(_ label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .trailing)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func progressStatus(_ text: String) -> some View {
        HStack(spacing: 9) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(settingsMetrics.secondaryFont())
                .foregroundStyle(.secondary)
        }
    }

    private func approximateSize(_ bytes: Int64) -> String {
        String(localized: "About \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))")
    }

    private func downloadStatus(receivedBytes: Int64, totalBytes: Int64?) -> String {
        let received = ByteCountFormatter.string(fromByteCount: receivedBytes, countStyle: .file)
        guard let totalBytes, totalBytes > 0 else {
            return String(localized: "Downloading official runtime · \(received)")
        }
        let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return String(localized: "Downloading official runtime · \(received) of \(total)")
    }
}

// MARK: - AssistantInstallPathControl

private struct AssistantInstallPathControl: NSViewRepresentable {
    let url: URL
    let fontSize: CGFloat

    func makeNSView(context: Context) -> NSPathControl {
        let control = NSPathControl()
        control.pathStyle = .standard
        control.isEditable = false
        control.focusRingType = .none
        return control
    }

    func updateNSView(_ control: NSPathControl, context: Context) {
        control.url = url
        control.font = .systemFont(ofSize: fontSize)
    }
}
