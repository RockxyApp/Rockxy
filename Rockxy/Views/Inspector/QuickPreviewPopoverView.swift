import AppKit
import SwiftUI

// MARK: - QuickPreviewPopoverView

struct QuickPreviewPopoverView: View {
    let result: QuickPreviewResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .padding(12)
        .frame(minWidth: 420, minHeight: 260)
    }

    @State private var copied = false
    @Environment(\.appUIDisplayMetrics) private var metrics

    private var title: String {
        switch result {
        case let .json(title, _),
             let .text(title, _),
             let .keyValue(title, _):
            title
        case .jwt:
            String(localized: "JWT")
        case let .error(title, _):
            title
        }
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(.system(size: metrics.primaryFontSize, weight: .semibold))
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.copyText, forType: .string)
                copied = true
            } label: {
                Label(copied ? String(localized: "Copied") : String(localized: "Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .font(.system(size: metrics.controlFontSize))
        }
    }

    @ViewBuilder private var content: some View {
        switch result {
        case let .json(_, text),
            let .text(_, text):
            InspectorBodyTextEditor(text: text, editorSettings: metrics.inspectorTextEditorSettings)
                .frame(minWidth: 0)
                .clipped()
                .frame(minHeight: 220)
        case let .keyValue(_, rows):
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        HStack(alignment: .top, spacing: 8) {
                            Text(row.key)
                                .font(.system(size: metrics.fontSize, weight: .semibold, design: .monospaced))
                                .frame(width: 150, alignment: .topLeading)
                            Text(row.value)
                                .font(.system(size: metrics.fontSize, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
            .frame(minHeight: 220)
        case let .jwt(preview):
            jwtContent(preview)
        case let .error(_, message):
            ContentUnavailableView {
                Label(String(localized: "Unable to Preview"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
            .frame(minHeight: 220)
        }
    }

    private func jwtContent(_ preview: JWTPreview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !preview.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(preview.warnings.enumerated()), id: \.offset) { _, warning in
                        Label(warning.message, systemImage: warning.severity == .warning ? "exclamationmark.triangle" : "info.circle")
                            .font(.system(size: metrics.secondaryFontSize))
                            .foregroundStyle(warning.severity == .warning ? .orange : .secondary)
                    }
                }
            }

            if !preview.claims.summaryRows.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(preview.claims.summaryRows) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.key)
                                .font(.system(size: metrics.metadataFontSize, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(row.value)
                                .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                                .lineLimit(2)
                        }
                    }
                }
            }

            TabView {
                InspectorBodyTextEditor(text: preview.headerText, editorSettings: metrics.inspectorTextEditorSettings)
                    .frame(minWidth: 0)
                    .clipped()
                    .tabItem { Text(String(localized: "Header")) }
                InspectorBodyTextEditor(text: preview.payloadText, editorSettings: metrics.inspectorTextEditorSettings)
                    .frame(minWidth: 0)
                    .clipped()
                    .tabItem { Text(String(localized: "Payload")) }
                InspectorBodyTextEditor(
                    text: preview.signaturePreview,
                    editorSettings: metrics.inspectorTextEditorSettings
                )
                    .frame(minWidth: 0)
                    .clipped()
                    .tabItem { Text(String(localized: "Signature")) }
            }
            .frame(minHeight: 210)
        }
    }

    private var footer: some View {
        Text(String(localized: "Preview is local. JWT signatures are decoded, not verified."))
            .font(.system(size: metrics.secondaryFontSize))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
