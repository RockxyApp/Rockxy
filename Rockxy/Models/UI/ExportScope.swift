import Foundation

// Defines `ExportScope`, the model for export scope used by the SwiftUI interface.

// MARK: - TrafficExportFormat

/// User-facing traffic export formats available from the main capture workspace.
enum TrafficExportFormat: String, CaseIterable {
    case har
    case openAPIYAML
    case openAPIHTML

    var title: String {
        switch self {
        case .har:
            String(localized: "Export as HAR")
        case .openAPIYAML:
            String(localized: "Export as OpenAPI YAML")
        case .openAPIHTML:
            String(localized: "Export as OpenAPI HTML")
        }
    }

    var privacyNote: String {
        switch self {
        case .har:
            String(localized: "Exported files may contain request bodies, cookies, and authorization headers.")
        case .openAPIYAML, .openAPIHTML:
            String(localized: "OpenAPI exports infer schemas from captured traffic and redact sensitive headers, query values, and body fields.")
        }
    }

    var defaultFileName: String {
        switch self {
        case .har:
            "rockxy-export.har"
        case .openAPIYAML:
            "rockxy-openapi.yaml"
        case .openAPIHTML:
            "rockxy-openapi.html"
        }
    }

    var successLabel: String {
        switch self {
        case .har:
            "HAR"
        case .openAPIYAML:
            "OpenAPI YAML"
        case .openAPIHTML:
            "OpenAPI HTML"
        }
    }
}

// MARK: - ExportScope

/// Determines which transactions are included when exporting captured traffic.
enum ExportScope: String, CaseIterable {
    case all
    case filtered
    case selected
}

// MARK: - ExportScopeContext

/// Snapshot of transaction counts used by `ExportScopeSheet` to display
/// scope options and disable unavailable choices.
struct ExportScopeContext {
    let format: TrafficExportFormat
    let allCount: Int
    let filteredCount: Int
    let selectedCount: Int
    let eligibleAllCount: Int
    let eligibleFilteredCount: Int
    let eligibleSelectedCount: Int
    let initialScope: ExportScope
    let restrictsToSelection: Bool

    init(
        format: TrafficExportFormat,
        allCount: Int,
        filteredCount: Int,
        selectedCount: Int,
        eligibleAllCount: Int,
        eligibleFilteredCount: Int,
        eligibleSelectedCount: Int,
        initialScope: ExportScope,
        restrictsToSelection: Bool = false
    ) {
        self.format = format
        self.allCount = allCount
        self.filteredCount = filteredCount
        self.selectedCount = selectedCount
        self.eligibleAllCount = eligibleAllCount
        self.eligibleFilteredCount = eligibleFilteredCount
        self.eligibleSelectedCount = eligibleSelectedCount
        self.initialScope = initialScope
        self.restrictsToSelection = restrictsToSelection
    }

    var hasActiveFilter: Bool {
        filteredCount != allCount
    }

    var hasSelection: Bool {
        selectedCount > 0
    }

    func count(for scope: ExportScope) -> Int {
        switch scope {
        case .all:
            allCount
        case .filtered:
            filteredCount
        case .selected:
            selectedCount
        }
    }

    func eligibleCount(for scope: ExportScope) -> Int {
        switch scope {
        case .all:
            eligibleAllCount
        case .filtered:
            eligibleFilteredCount
        case .selected:
            eligibleSelectedCount
        }
    }

    func isEnabled(_ scope: ExportScope) -> Bool {
        if restrictsToSelection, scope != .selected {
            return false
        }
        return switch scope {
        case .all:
            eligibleAllCount > 0
        case .filtered:
            hasActiveFilter && eligibleFilteredCount > 0
        case .selected:
            hasSelection && eligibleSelectedCount > 0
        }
    }

    func label(for scope: ExportScope) -> String {
        switch (format, scope) {
        case (.har, .all):
            String(localized: "All Transactions")
        case (.har, .filtered):
            String(localized: "Visible / Filtered")
        case (.har, .selected):
            String(localized: "Selected")
        case (_, .all):
            String(localized: "All Captured Requests")
        case (_, .filtered):
            String(localized: "Visible / Filtered Requests")
        case (_, .selected):
            String(localized: "Selected Requests")
        }
    }
}
