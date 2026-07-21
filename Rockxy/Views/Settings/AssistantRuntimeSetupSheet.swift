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
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "shippingbox.and.arrow.backward.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Set Up Ollama on This Mac"))
                        .font(.title2.weight(.semibold))
                    Text(
                        String(
                            localized: "Rockxy downloads the official app, verifies its developer signature, installs it where you choose, and checks the local service."
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    detailRow(
                        String(localized: "Runtime"),
                        value: String(localized: "Ollama · official macOS app")
                    )
                    detailRow(
                        String(localized: "Download"),
                        value: approximateSize(runtime.approximateDownloadBytes)
                    )
                    detailRow(
                        String(localized: "Installed"),
                        value: approximateSize(runtime.approximateInstalledBytes)
                    )
                    detailRow(
                        String(localized: "Models"),
                        value: runtime.modelFamilies.joined(separator: ", ")
                    )
                }
                .padding(.vertical, 2)
            } label: {
                Label(String(localized: "Verified Runtime"), systemImage: "checkmark.seal")
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(String(localized: "Install Location"))
                    .font(.headline)
                HStack(spacing: 8) {
                    Text(viewModel.runtimeInstallDestinationDisplayPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(String(localized: "Choose…")) {
                        viewModel.chooseRuntimeInstallDestination()
                    }
                    .disabled(viewModel.runtimeSetupState.isBusy)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                }
                Text(
                    String(
                        localized: "Model files are downloaded separately after setup and remain managed by Ollama. They can require several GB each."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            setupStatus

            Divider()

            HStack {
                if viewModel.runtimeSetupState.isBusy {
                    Button(String(localized: "Cancel")) {
                        viewModel.cancelRuntimeInstall()
                    }
                } else {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }
                Spacer()
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
                    Button(String(localized: "Download & Install")) {
                        viewModel.installOllamaRuntime()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.runtimeSetupState.isBusy)
                }
            }
        }
        .padding(20)
        .frame(width: 540)
        .interactiveDismissDisabled(viewModel.runtimeSetupState.isBusy)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    private let runtime = AssistantLocalRuntimeDescriptor.ollama

    @ViewBuilder private var setupStatus: some View {
        switch viewModel.runtimeSetupState {
        case .idle:
            Label(
                String(localized: "Nothing will be installed until you confirm."),
                systemImage: "hand.raised"
            )
            .foregroundStyle(.secondary)
        case let .downloading(receivedBytes, totalBytes):
            VStack(alignment: .leading, spacing: 7) {
                if let totalBytes, totalBytes > 0 {
                    ProgressView(value: min(1, Double(receivedBytes) / Double(totalBytes)))
                } else {
                    ProgressView()
                }
                Text(downloadStatus(receivedBytes: receivedBytes, totalBytes: totalBytes))
                    .font(.caption)
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
    }

    private func progressStatus(_ text: String) -> some View {
        HStack(spacing: 9) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(.subheadline)
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
