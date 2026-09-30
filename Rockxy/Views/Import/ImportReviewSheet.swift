import SwiftUI

// MARK: - ImportReviewSummary

/// Pure, testable description of an import review. Owns the file labels, the
/// incoming counts, the empty-vs-replace impact copy, and the primary action
/// title so the confirmation surface stays honest without reaching into the
/// import coordinator. Mirrors the shape of `GistPublishReviewSummary`.
struct ImportReviewSummary: Equatable {
    // MARK: Lifecycle

    init(preview: ImportPreview, currentTransactionCount: Int, currentLogCount: Int) {
        fileType = preview.fileType
        fileName = preview.fileName
        fileSize = preview.fileSize
        incomingTransactionCount = preview.transactionCount
        incomingLogEntryCount = preview.logEntryCount
        skippedEntryCount = preview.skippedEntryCount
        self.currentTransactionCount = currentTransactionCount
        self.currentLogCount = currentLogCount
        rockxyVersion = preview.rockxyVersion.flatMap {
            let normalized = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? nil : normalized
        }
    }

    // MARK: Internal

    let fileType: ImportFileType
    let fileName: String
    let fileSize: Int64
    let incomingTransactionCount: Int
    let incomingLogEntryCount: Int
    let skippedEntryCount: Int
    let currentTransactionCount: Int
    let currentLogCount: Int
    let rockxyVersion: String?

    var isRockxySession: Bool {
        fileType == .rockxysession
    }

    /// An empty workspace has nothing to lose — the import is non-destructive.
    var isSessionEmpty: Bool {
        currentTransactionCount == 0 && currentLogCount == 0
    }

    var isDestructive: Bool {
        !isSessionEmpty
    }

    var title: String {
        ImportReviewCopy.headerTitle(fileType)
    }

    var subtitle: String {
        ImportReviewCopy.subtitle
    }

    var fileTypeLabel: String {
        ImportReviewCopy.fileTypeLabel(fileType)
    }

    var fileSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var incomingRequestsLabel: String {
        ImportReviewCopy.requests(incomingTransactionCount)
    }

    var incomingLogsLabel: String {
        ImportReviewCopy.logEntries(incomingLogEntryCount)
    }

    var versionLabel: String? {
        rockxyVersion.map { String(localized: "Rockxy v\($0)", bundle: RockxyLocalization.bundle) }
    }

    var actionTitle: String {
        isDestructive ? ImportReviewCopy.replaceActionTitle : ImportReviewCopy.primaryActionTitle(fileType)
    }

    /// Neutral consequence copy for an empty workspace, explicit replacement copy
    /// (naming both current counts) for a populated one.
    var impactSummary: String {
        let base = baseImpactSummary
        guard skippedEntryCount > 0 else {
            return base
        }
        let skipped = String(skippedEntryCount)
        return base + " " + String(
            localized: "\(skipped) entries could not be read and will be left out.",
            bundle: RockxyLocalization.bundle
        )
    }

    private var baseImpactSummary: String {
        if isSessionEmpty {
            if isRockxySession {
                return String(
                    localized: "The current session is empty. Opening loads \(incomingRequestsLabel) and \(incomingLogsLabel).",
                    bundle: RockxyLocalization.bundle
                )
            }
            return String(
                localized: "The current session is empty. Importing loads \(incomingRequestsLabel).",
                bundle: RockxyLocalization.bundle
            )
        }
        let currentRequests = ImportReviewCopy.requests(currentTransactionCount)
        let currentLogs = ImportReviewCopy.logEntries(currentLogCount)
        return String(
            localized: "Importing replaces the entire current session — \(currentRequests) and \(currentLogs) — with this capture.",
            bundle: RockxyLocalization.bundle
        )
    }
}

// MARK: - ImportReviewCopy

/// Truthful, testable copy for the import review surface.
enum ImportReviewCopy {
    static var subtitle: String {
        String(
            localized: "Review this capture before it loads into the current session.",
            bundle: RockxyLocalization.bundle
        )
    }

    static var replaceActionTitle: String {
        String(localized: "Replace Session", bundle: RockxyLocalization.bundle)
    }

    static func fileTypeLabel(_ type: ImportFileType) -> String {
        switch type {
        case .har:
            String(localized: "HAR Archive (HTTP Archive 1.2)", bundle: RockxyLocalization.bundle)
        case .charlesJSON:
            String(localized: "Charles JSON Session", bundle: RockxyLocalization.bundle)
        case .rockxysession:
            String(localized: "Rockxy Session", bundle: RockxyLocalization.bundle)
        }
    }

    static func headerTitle(_ type: ImportFileType) -> String {
        switch type {
        case .har:
            String(localized: "Import HAR Archive", bundle: RockxyLocalization.bundle)
        case .charlesJSON:
            String(localized: "Import Charles Session", bundle: RockxyLocalization.bundle)
        case .rockxysession:
            String(localized: "Open Rockxy Session", bundle: RockxyLocalization.bundle)
        }
    }

    static func primaryActionTitle(_ type: ImportFileType) -> String {
        switch type {
        case .har,
             .charlesJSON:
            String(localized: "Import", bundle: RockxyLocalization.bundle)
        case .rockxysession:
            String(localized: "Open Session", bundle: RockxyLocalization.bundle)
        }
    }

    static func requests(_ count: Int) -> String {
        String(AttributedString(
            localized: "^[\(count) request](inflect: true)",
            bundle: RockxyLocalization.bundle,
            locale: RockxyLocalization.locale
        ).characters)
    }

    static func logEntries(_ count: Int) -> String {
        String(AttributedString(
            localized: "^[\(count) log entry](inflect: true)",
            bundle: RockxyLocalization.bundle,
            locale: RockxyLocalization.locale
        ).characters)
    }
}

// MARK: - ImportReviewSheet

/// Confirmation sheet shown after file selection but before any destructive
/// session replacement. Displays the capture metadata and, when the current
/// session is non-empty, an explicit warning that importing replaces it.
struct ImportReviewSheet: View {
    // MARK: Internal

    let preview: ImportPreview
    let currentTransactionCount: Int
    let currentLogCount: Int
    var onReplace: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            summaryCard
            impactRow
            footer
        }
        .padding(.top, 18)
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .font(toolMetrics.font())
        .frame(width: max(440, toolMetrics.fieldWidth(440)))
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var summary: ImportReviewSummary {
        ImportReviewSummary(
            preview: preview,
            currentTransactionCount: currentTransactionCount,
            currentLogCount: currentLogCount
        )
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var footerActionWidth: CGFloat {
        max(140, toolMetrics.bodyFontSize * 8)
    }

    private var capturedLabel: String? {
        guard let start = preview.captureStartDate else {
            return nil
        }
        return dateRangeText(start, preview.captureEndDate)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(summary.title)
                .font(toolMetrics.font(weight: .semibold))
            Text(summary.subtitle)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("importReview.header")
    }

    private var summaryCard: some View {
        VStack(spacing: 0) {
            metadataRow(
                String(localized: "File", bundle: RockxyLocalization.bundle),
                summary.fileName,
                identifier: "importReview.summary.file",
                truncateMiddle: true
            )
            dividerLine
            metadataRow(
                String(localized: "Type", bundle: RockxyLocalization.bundle),
                summary.fileTypeLabel,
                identifier: "importReview.summary.type"
            )
            dividerLine
            metadataRow(
                String(localized: "Size", bundle: RockxyLocalization.bundle),
                summary.fileSizeLabel,
                identifier: "importReview.summary.size"
            )
            dividerLine
            metadataRow(
                String(localized: "Requests", bundle: RockxyLocalization.bundle),
                summary.incomingRequestsLabel,
                identifier: "importReview.summary.requests"
            )

            if summary.isRockxySession {
                dividerLine
                metadataRow(
                    String(localized: "Logs", bundle: RockxyLocalization.bundle),
                    summary.incomingLogsLabel,
                    identifier: "importReview.summary.logs"
                )

                if let capturedLabel {
                    dividerLine
                    metadataRow(
                        String(localized: "Captured", bundle: RockxyLocalization.bundle),
                        capturedLabel,
                        identifier: "importReview.summary.captured"
                    )
                }

                if let version = summary.versionLabel {
                    dividerLine
                    metadataRow(
                        String(localized: "Saved with", bundle: RockxyLocalization.bundle),
                        version,
                        identifier: "importReview.summary.version"
                    )
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var impactRow: some View {
        Label {
            Text(summary.impactSummary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: summary.isDestructive ? "exclamationmark.triangle.fill" : "info.circle")
        }
        .font(toolMetrics.secondaryFont())
        .foregroundStyle(summary.isDestructive ? Color.orange : Color(nsColor: .secondaryLabelColor))
        .accessibilityIdentifier("importReview.impact")
    }

    private var footer: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Spacer()

            Button {
                onCancel()
            } label: {
                Text(String(localized: "Cancel", bundle: RockxyLocalization.bundle))
                    .frame(width: footerActionWidth)
                    .frame(minHeight: toolMetrics.formControlHeight)
            }
            .rockxyGlassButtonStyle()
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("importReview.cancelButton")

            actionButton
        }
    }

    @ViewBuilder private var actionButton: some View {
        if summary.isDestructive {
            Button(role: .destructive) {
                onReplace()
            } label: {
                Text(summary.actionTitle)
                    .frame(width: footerActionWidth)
                    .frame(minHeight: toolMetrics.formControlHeight)
            }
            .rockxyGlassButtonStyle()
            .accessibilityIdentifier("importReview.actionButton")
        } else {
            Button {
                onReplace()
            } label: {
                Text(summary.actionTitle)
                    .frame(width: footerActionWidth)
                    .frame(minHeight: toolMetrics.formControlHeight)
            }
            .keyboardShortcut(.defaultAction)
            .rockxyGlassButtonStyle(prominent: true)
            .accessibilityIdentifier("importReview.actionButton")
        }
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
    }

    private func metadataRow(
        _ label: String,
        _ value: String,
        identifier: String,
        truncateMiddle: Bool = false
    )
        -> some View
    {
        HStack(spacing: 12) {
            Text(label)
                .font(toolMetrics.font())
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .frame(width: toolMetrics.menuWidth(92), alignment: .leading)

            Text(value)
                .font(toolMetrics.font())
                .foregroundStyle(Color(nsColor: .labelColor))
                .lineLimit(1)
                .truncationMode(truncateMiddle ? .middle : .tail)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: toolMetrics.tableRowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private func dateRangeText(_ start: Date, _ end: Date?) -> String {
        let startStr = TimestampFormatter.string(start, date: .numeric, time: .standard)
        guard let end else {
            return startStr
        }
        return "\(startStr) — \(TimestampFormatter.string(end, date: .numeric, time: .standard))"
    }
}
