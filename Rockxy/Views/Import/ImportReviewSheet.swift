import SwiftUI

// Renders the import review sheet interface for session import review.

// MARK: - ImportReviewSheet

/// Confirmation sheet shown after file selection but before any destructive session
/// replacement. Displays file metadata and a warning about data loss when the current
/// session is non-empty. Matches the Figma design at file BmxrbvKOU3Q2wZUe2NT87Y node 8:3.
struct ImportReviewSheet: View {
    // MARK: Internal

    let preview: ImportPreview
    let currentTransactionCount: Int
    let currentLogCount: Int
    var onReplace: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            title

            sectionLabel(String(localized: "FILE INFO"))

            fileInfoSection

            sectionLabel(String(localized: "WARNING"))

            warningRow

            bottomBar
        }
        .padding(.top, 16)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .font(toolMetrics.font())
        .frame(width: max(420, toolMetrics.fieldWidth(420)))
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Private

    private var fileTypeDisplayName: String {
        switch preview.fileType {
        case .har:
            String(localized: "HAR Archive (HTTP Archive 1.2)")
        case .rockxysession:
            String(localized: "Rockxy Session")
        }
    }

    private var warningText: String {
        if currentTransactionCount == 0, currentLogCount == 0 {
            return String(
                localized: "Your session is empty. This will load \(preview.transactionCount) transactions."
            )
        }
        return String(
            localized: "This will replace \(currentTransactionCount) transactions and \(currentLogCount) log entries."
        )
    }

    private var title: some View {
        Text(String(localized: "Import Review"))
            .font(toolMetrics.font(weight: .semibold))
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var fileInfoSection: some View {
        VStack(spacing: 0) {
            infoRow(
                label: String(localized: "File Name"),
                value: preview.fileName
            )

            dividerLine

            infoRow(
                label: String(localized: "Type"),
                value: fileTypeDisplayName
            )

            dividerLine

            infoRow(
                label: String(localized: "Requests"),
                value: "\(preview.transactionCount)"
            )

            dividerLine

            infoRow(
                label: String(localized: "File Size"),
                value: ByteCountFormatter.string(
                    fromByteCount: preview.fileSize,
                    countStyle: .file
                )
            )

            if preview.fileType == .rockxysession {
                dividerLine

                infoRow(
                    label: String(localized: "Log Entries"),
                    value: "\(preview.logEntryCount)"
                )

                if let startDate = preview.captureStartDate {
                    dividerLine

                    infoRow(
                        label: String(localized: "Captured"),
                        value: dateRangeText(startDate, preview.captureEndDate)
                    )
                }

                if let version = preview.rockxyVersion, !version.isEmpty {
                    dividerLine

                    infoRow(
                        label: String(localized: "Saved with"),
                        value: "Rockxy v\(version)"
                    )
                }
            }
        }
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
    }

    private var warningRow: some View {
        HStack(spacing: 0) {
            Text("\u{26A0}")
                .font(toolMetrics.font(weight: .semibold))
                .foregroundStyle(Color(red: 0.93, green: 0.60, blue: 0.0))

            Spacer()
                .frame(width: 6)

            Text(warningText)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(Color(red: 0.55, green: 0.38, blue: 0.0))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: toolMetrics.formControlHeight)
                .background(Color(red: 1.0, green: 0.969, blue: 0.922))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(
                            Color(red: 0.93, green: 0.851, blue: 0.722),
                            lineWidth: 0.5
                        )
                }
        }
        .padding(.leading, 12)
        .frame(minHeight: toolMetrics.formControlHeight + 16)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            dividerLine

            HStack(spacing: 8) {
                Spacer()

                Button(String(localized: "Cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .frame(width: toolMetrics.footerButtonWidth)
                .frame(minHeight: toolMetrics.formControlHeight)

                Button(role: .destructive) {
                    onReplace()
                } label: {
                    Text(String(localized: "Replace Current"))
                        .font(toolMetrics.font(weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: toolMetrics.menuWidth(130))
                        .frame(minHeight: toolMetrics.formControlHeight)
                        .background(Color(red: 1.0, green: 0.231, blue: 0.188))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(toolMetrics.metadataFont(weight: .medium))
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .tracking(0.3)
            .textCase(.uppercase)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(toolMetrics.font())
                .frame(width: toolMetrics.menuWidth(90), alignment: .leading)

            Text(value)
                .font(toolMetrics.font())
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: toolMetrics.formControlHeight)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                }
        }
        .padding(.leading, 12)
        .frame(minHeight: toolMetrics.formControlHeight + 16)
    }

    private func dateRangeText(_ start: Date, _ end: Date?) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        let startStr = formatter.string(from: start)
        guard let end else {
            return startStr
        }
        return "\(startStr) — \(formatter.string(from: end))"
    }

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}
