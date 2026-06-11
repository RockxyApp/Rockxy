import SwiftUI

// Renders the compose response viewer interface for the compose workflow.

// MARK: - ComposeResponseViewer

/// Right panel of the Compose window. Displays one of four states:
/// empty (before first send), loading, success (with Body/Headers/Raw tabs), or error.
struct ComposeResponseViewer: View {
    // MARK: Internal

    let viewModel: ComposeViewModel

    var body: some View {
        Group {
            switch viewModel.responseState {
            case .empty:
                emptyState
            case .loading:
                loadingState
            case let .success(response):
                successState(response)
            case let .error(message):
                errorState(message)
            case let .unsupported(message):
                unsupportedState(message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Private

    // MARK: - Helpers

    private static let headerColumns = [
        GridItem(.flexible(minimum: 120, maximum: 200), alignment: .topLeading),
        GridItem(.flexible(), alignment: .topLeading),
    ]

    @State private var selectedTab: ComposeResponseTab = .body
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "No Response"), systemImage: "arrow.up.circle")
        } description: {
            Text(String(localized: "Send a request to see the response here."))
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.regular)
            Text(String(localized: "Sending..."))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Success State

    private func successState(_ response: ComposeResponse) -> some View {
        VStack(spacing: 0) {
            responseSummary(response)
            Divider()

            Picker("", selection: $selectedTab) {
                ForEach(ComposeResponseTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()

            Group {
                switch selectedTab {
                case .body:
                    responseBody(response)
                case .headers:
                    responseHeaders(response)
                case .raw:
                    responseRaw(response)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func responseSummary(_ response: ComposeResponse) -> some View {
        HStack(spacing: 8) {
            StatusCodeBadge(statusCode: response.statusCode)
            Text(response.statusMessage)
                .font(toolMetrics.secondaryFont(monospaced: true))
                .foregroundStyle(.secondary)
            Spacer()
            Text(Self.formatBodySize(response.bodySize))
                .font(toolMetrics.metadataFont())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func responseBody(_ response: ComposeResponse) -> some View {
        Group {
            if response.contentType == .json {
                JSONTreeView(data: response.bodyData)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Text(response.bodyDisplayText)
                        .font(toolMetrics.font(monospaced: true))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }
        }
    }

    private func responseHeaders(_ response: ComposeResponse) -> some View {
        ScrollView {
            LazyVGrid(columns: Self.headerColumns, alignment: .leading, spacing: 4) {
                Text(String(localized: "Name"))
                    .font(toolMetrics.secondaryFont(weight: .bold))
                    .foregroundStyle(.secondary)
                Text(String(localized: "Value"))
                    .font(toolMetrics.secondaryFont(weight: .bold))
                    .foregroundStyle(.secondary)

                ForEach(Array(response.headers.enumerated()), id: \.offset) { _, header in
                    Text(header.name)
                        .font(toolMetrics.secondaryFont(monospaced: true))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(header.value)
                        .font(toolMetrics.secondaryFont(monospaced: true))
                        .textSelection(.enabled)
                }
            }
            .padding(12)
        }
    }

    private func responseRaw(_ response: ComposeResponse) -> some View {
        ScrollView([.horizontal, .vertical]) {
            Text(Self.buildRawResponse(response))
                .font(toolMetrics.font(monospaced: true))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
    }

    // MARK: - Unsupported State

    private func unsupportedState(_ message: String) -> some View {
        ContentUnavailableView {
            Label(String(localized: "Replay Not Supported"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        }
    }

    // MARK: - Error State

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "xmark.circle.fill")
                .font(.title)
                .foregroundStyle(.red)
            Text(message)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static func formatBodySize(_ bytes: Int) -> String {
        if bytes < 1_024 {
            "\(bytes) B"
        } else if bytes < 1_048_576 {
            String(format: "%.1f KB", Double(bytes) / 1_024)
        } else {
            String(format: "%.1f MB", Double(bytes) / 1_048_576)
        }
    }

    private static func buildRawResponse(_ response: ComposeResponse) -> String {
        var lines: [String] = []
        lines.append("HTTP/1.1 \(response.statusCode) \(response.statusMessage)")
        for header in response.headers {
            lines.append("\(header.name): \(header.value)")
        }
        lines.append("")
        lines.append(response.bodyDisplayText)
        return lines.joined(separator: "\r\n")
    }
}

// MARK: - ComposeResponseTab

private enum ComposeResponseTab: String, CaseIterable, Identifiable {
    case body
    case headers
    case raw

    // MARK: Internal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .body: String(localized: "Body")
        case .headers: String(localized: "Headers")
        case .raw: String(localized: "Raw")
        }
    }
}
