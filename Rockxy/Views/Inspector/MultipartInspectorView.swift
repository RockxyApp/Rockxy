import AppKit
import SwiftUI

// Part-by-part view of a multipart/form-data request body.

// MARK: - MultipartInspectorView

/// Lists every part of a multipart upload (field name, file name, type, size)
/// with a preview of the selected part and a Save action that writes the exact
/// bytes the client sent.
struct MultipartInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction

    var body: some View {
        Group {
            if let parts {
                if parts.isEmpty {
                    InspectorEmptyStateView(
                        String(localized: "No Parts", bundle: RockxyLocalization.bundle),
                        systemImage: "square.stack.3d.up.slash",
                        description: String(
                            localized: "The body does not contain any parts for its declared boundary.",
                            bundle: RockxyLocalization.bundle
                        )
                    )
                } else {
                    VSplitView {
                        partTable(parts)
                            .frame(minHeight: 90, idealHeight: 150)
                        partDetail
                            .frame(minHeight: 120)
                    }
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: transaction.id) {
            await loadParts()
        }
    }

    /// Whether the request declares a multipart body worth a dedicated tab.
    static func isApplicable(to transaction: HTTPTransaction) -> Bool {
        guard transaction.request.body?.isEmpty == false,
              let contentType = transaction.request.headers.first(where: {
                  $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame
              })?.value else
        {
            return false
        }
        return MultipartFormDataParser.boundary(fromContentType: contentType) != nil
    }

    // MARK: Private

    @State private var parts: [MultipartPart]?
    @State private var selection: MultipartPart.ID?
    @State private var saveErrorMessage: String?
    @Environment(\.appUIDisplayMetrics) private var metrics

    private var selectedPart: MultipartPart? {
        guard let selection else {
            return parts?.first
        }
        return parts?.first { $0.id == selection }
    }

    @ViewBuilder private var partDetail: some View {
        if let part = selectedPart {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(part.fileName ?? part.name ?? String(
                        localized: "Unnamed Part",
                        bundle: RockxyLocalization.bundle
                    ))
                    .font(.system(size: metrics.fontSize, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    Spacer()
                    if let text = part.textValue {
                        Button(String(localized: "Copy", bundle: RockxyLocalization.bundle)) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                        .controlSize(.small)
                    }
                    Button(String(localized: "Save Part…", bundle: RockxyLocalization.bundle)) {
                        save(part)
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                Divider()
                partContent(part)
            }
            .alert(
                String(localized: "Could Not Save Part", bundle: RockxyLocalization.bundle),
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                )
            ) {
                Button(String(localized: "OK", bundle: RockxyLocalization.bundle)) {}
            } message: {
                Text(saveErrorMessage ?? "")
            }
        }
    }

    private func partTable(_ parts: [MultipartPart]) -> some View {
        Table(parts, selection: $selection) {
            TableColumn(String(localized: "Name", bundle: RockxyLocalization.bundle)) { part in
                Text(part.name ?? "—")
            }
            TableColumn(String(localized: "File Name", bundle: RockxyLocalization.bundle)) { part in
                Text(part.fileName ?? "—")
                    .foregroundStyle(part.fileName == nil ? .secondary : .primary)
            }
            TableColumn(String(localized: "Content Type", bundle: RockxyLocalization.bundle)) { part in
                Text(part.contentType ?? "—")
                    .foregroundStyle(part.contentType == nil ? .secondary : .primary)
            }
            TableColumn(String(localized: "Size", bundle: RockxyLocalization.bundle)) { part in
                Text(SizeFormatter.format(bytes: part.data.count))
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 80, max: 120)
        }
        .font(.system(size: metrics.secondaryFontSize))
        .accessibilityLabel(String(localized: "Multipart parts", bundle: RockxyLocalization.bundle))
    }

    @ViewBuilder
    private func partContent(_ part: MultipartPart) -> some View {
        if part.contentType?.lowercased().hasPrefix("image/") == true {
            ImagePreviewView(data: part.data)
        } else if let text = part.textValue {
            ScrollView {
                Text(text.isEmpty
                    ? String(localized: "Empty value", bundle: RockxyLocalization.bundle)
                    : text)
                    .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(10)
            }
        } else {
            InspectorEmptyStateView(
                String(localized: "Binary Part", bundle: RockxyLocalization.bundle),
                systemImage: "doc.zipper",
                description: String(
                    localized: "\(SizeFormatter.format(bytes: part.data.count)) of binary data. Save the part to inspect it in another app.",
                    bundle: RockxyLocalization.bundle
                )
            )
        }
    }

    private func loadParts() async {
        parts = nil
        selection = nil
        guard let body = transaction.request.body else {
            parts = []
            return
        }
        let headers = transaction.request.headers
        let parsed = await Task.detached(priority: .userInitiated) {
            MultipartFormDataParser.parse(body: body, headers: headers) ?? []
        }.value
        guard !Task.isCancelled else {
            return
        }
        parts = parsed
        selection = parsed.first?.id
    }

    private func save(_ part: MultipartPart) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Self.suggestedFileName(for: part)
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            try part.data.write(to: url, options: .atomic)
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    /// Uses only the last path component of the client-supplied file name so a
    /// crafted name cannot steer the save panel into another directory.
    private static func suggestedFileName(for part: MultipartPart) -> String {
        let candidate = (part.fileName ?? part.name ?? "part-\(part.id + 1)")
            .replacingOccurrences(of: "\\", with: "/")
        let lastComponent = (candidate as NSString).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return lastComponent.isEmpty || lastComponent == "." || lastComponent == ".."
            ? "part-\(part.id + 1)"
            : lastComponent
    }
}
