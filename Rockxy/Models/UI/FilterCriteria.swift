import Foundation

// Defines the UI model for workspace and toolbar filtering criteria.

// MARK: - SidebarScope

enum SidebarScope: Codable, Hashable {
    case allTraffic
    case saved
    case pinned
}

// MARK: - FilterCriteria

/// Composite filter state applied to both the traffic list and log viewer.
/// Combines free-text search, HTTP method/status/content type sets, domain restrictions,
/// log level thresholds, and protocol-based filters into a single value type.
struct FilterCriteria {
    static let empty = FilterCriteria()

    var searchText: String = ""
    var methods: Set<String> = []
    var statusCodes: Set<Int> = []
    var contentTypes: Set<ContentType> = []
    var domains: Set<String> = []
    var logLevels: Set<LogLevel> = []
    var activeProtocolFilters: Set<ProtocolFilter> = []
    var searchField: FilterField = .url
    var isSearchEnabled: Bool = true
    var sidebarDomain: String?
    var sidebarPathPrefix: String?
    var sidebarApp: String?
    var sidebarScope: SidebarScope = .allTraffic

    var isEmpty: Bool {
        (!isSearchEnabled || searchText.isEmpty) && methods.isEmpty && statusCodes.isEmpty
            && contentTypes.isEmpty && domains.isEmpty && logLevels.isEmpty
            && activeProtocolFilters.isEmpty && sidebarDomain == nil
            && sidebarPathPrefix == nil && sidebarApp == nil && sidebarScope == .allTraffic
    }

    var activeFilterCount: Int {
        var count = 0
        if isSearchEnabled, !searchText.isEmpty {
            count += 1
        }
        if !methods.isEmpty {
            count += 1
        }
        if !statusCodes.isEmpty {
            count += 1
        }
        if !contentTypes.isEmpty {
            count += 1
        }
        if !domains.isEmpty {
            count += 1
        }
        if !activeProtocolFilters.isEmpty {
            count += 1
        }
        if sidebarDomain != nil {
            count += 1
        }
        if sidebarPathPrefix != nil {
            count += 1
        }
        if sidebarApp != nil {
            count += 1
        }
        if sidebarScope != .allTraffic {
            count += 1
        }
        return count
    }
}
