import Foundation
import os

// MARK: - HeaderColumnStore

// Persists and coordinates custom header column configuration for the traffic table.

@MainActor @Observable
final class HeaderColumnStore {
    // MARK: Lifecycle

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? Self.defaultDefaults
        load()
    }

    // MARK: Internal

    // MARK: - Header Discovery

    struct DiscoveredHeaders {
        var request: [String]
        var response: [String]
    }

    var columns: [HeaderColumn] = []

    var discoveredRequestHeaders: [String] = []
    var discoveredResponseHeaders: [String] = []
    var hiddenBuiltInColumns: Set<String> = []
    var visibleDefaultHiddenBuiltInColumns: Set<String> = []

    var enabledColumns: [HeaderColumn] {
        columns.filter(\.isEnabled)
    }

    var requestColumns: [HeaderColumn] {
        columns.filter { $0.source == .request }
    }

    var responseColumns: [HeaderColumn] {
        columns.filter { $0.source == .response }
    }

    // MARK: - Header Value Resolution

    nonisolated static func resolveValue(
        for columnID: String,
        transaction: HTTPTransaction
    )
        -> String
    {
        guard let (source, name) = HeaderColumn.parse(columnID: columnID) else {
            return ""
        }
        switch source {
        case .request:
            return transaction.request.headers
                .first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?
                .value ?? ""
        case .response:
            return transaction.response?.headers
                .first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?
                .value ?? ""
        case .query:
            return CustomColumnValueResolver.queryValue(named: name, in: transaction.request.url)
        case .requestBody,
             .responseBody:
            return CustomColumnValueResolver.bodyValue(
                expression: name,
                response: source == .responseBody,
                transaction: transaction
            )
        }
    }

    // MARK: - Column Management

    @discardableResult
    func addColumn(headerName: String, source: HeaderColumnSource) -> HeaderColumn {
        if let existing = columns.first(where: {
            $0.source == source && source.namesMatch($0.headerName, headerName)
        }) {
            return existing
        }
        let column = HeaderColumn(headerName: headerName, source: source)
        columns.append(column)
        save()
        Self.logger.info("Added header column: \(headerName) (\(source.rawValue))")
        return column
    }

    func removeColumn(id: UUID) {
        columns.removeAll { $0.id == id }
        save()
    }

    func toggleColumn(id: UUID) {
        guard let index = columns.firstIndex(where: { $0.id == id }) else {
            return
        }
        columns[index].isEnabled.toggle()
        save()
    }

    func isColumnDefined(headerName: String, source: HeaderColumnSource) -> Bool {
        columns.contains {
            $0.source == source && source.namesMatch($0.headerName, headerName)
        }
    }

    func moveColumn(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0, sourceIndex < columns.count,
              destinationIndex >= 0, destinationIndex < columns.count,
              sourceIndex != destinationIndex else
        {
            return
        }
        let column = columns.remove(at: sourceIndex)
        columns.insert(column, at: destinationIndex)
        save()
    }

    func discoverHeaders(from transactions: [HTTPTransaction]) -> DiscoveredHeaders {
        var requestNames = DiscoveredHeaderNames()
        var responseNames = DiscoveredHeaderNames()
        for transaction in transactions.prefix(200) {
            for header in transaction.request.headers {
                requestNames.insert(header.name)
            }
            for header in transaction.response?.headers ?? [] {
                responseNames.insert(header.name)
            }
        }
        let existingRequestNames = Set(requestColumns.map { $0.headerName.lowercased() })
        let existingResponseNames = Set(responseColumns.map { $0.headerName.lowercased() })
        return DiscoveredHeaders(
            request: requestNames.sortedNames.filter { !existingRequestNames.contains($0.lowercased()) },
            response: responseNames.sortedNames.filter { !existingResponseNames.contains($0.lowercased()) }
        )
    }

    func updateDiscoveredHeaders(from transactions: [HTTPTransaction]) {
        var requestNames = DiscoveredHeaderNames()
        var responseNames = DiscoveredHeaderNames()
        for transaction in transactions {
            for header in transaction.request.headers {
                requestNames.insert(header.name)
            }
            for header in transaction.response?.headers ?? [] {
                responseNames.insert(header.name)
            }
        }
        discoveredRequestHeaderSet = requestNames
        discoveredResponseHeaderSet = responseNames
        persistDiscoveredHeaders()
    }

    /// Incremental header discovery from a batch of new transactions. O(batch_size) per call
    /// with O(1) membership checks via bounded indexes. Replaces the old full-scan approach that
    /// was biased toward the oldest 500 transactions.
    func updateDiscoveredHeaders(fromBatch batch: [HTTPTransaction]) {
        var changed = false
        for transaction in batch {
            for header in transaction.request.headers {
                if discoveredRequestHeaderSet.insert(header.name) {
                    changed = true
                }
            }
            if let response = transaction.response {
                for header in response.headers {
                    if discoveredResponseHeaderSet.insert(header.name) {
                        changed = true
                    }
                }
            }
        }
        if changed {
            persistDiscoveredHeaders()
        }
    }

    func toggleBuiltInColumn(_ columnID: String) {
        if isBuiltInColumnVisible(columnID) {
            visibleDefaultHiddenBuiltInColumns.remove(columnID)
            hiddenBuiltInColumns.insert(columnID)
        } else {
            hiddenBuiltInColumns.remove(columnID)
            if Self.defaultHiddenBuiltInColumns.contains(columnID) {
                visibleDefaultHiddenBuiltInColumns.insert(columnID)
            }
        }
        saveHiddenColumns()
    }

    func isBuiltInColumnVisible(_ columnID: String) -> Bool {
        if hiddenBuiltInColumns.contains(columnID) {
            return false
        }
        if Self.defaultHiddenBuiltInColumns.contains(columnID) {
            return visibleDefaultHiddenBuiltInColumns.contains(columnID)
        }
        return true
    }

    func reload() {
        load()
    }

    // MARK: Private

    /// Coordinator tests use the real app identity, but their suggestion and column
    /// writes must never migrate or replace the user's persistent configuration.
    private static let defaultDefaults: UserDefaults = {
        guard RockxyIdentity.isRunningTests else {
            return .standard
        }
        let name = "RockxyTests.HeaderColumns.\(ProcessInfo.processInfo.processIdentifier)"
        guard let defaults = UserDefaults(suiteName: name) else {
            preconditionFailure("Unable to create isolated header-column test defaults")
        }
        return defaults
    }()

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "HeaderColumnStore")
    private static let storageKey = RockxyIdentity.current.defaultsKey("headerColumns")
    private static let discoveredReqKey = RockxyIdentity.current.defaultsKey("discoveredReqHeaders")
    private static let discoveredResKey = RockxyIdentity.current.defaultsKey("discoveredResHeaders")
    private static let hiddenColumnsKey = RockxyIdentity.current.defaultsKey("hiddenBuiltInColumns")
    private static let visibleDefaultHiddenColumnsKey = RockxyIdentity.current
        .defaultsKey("visibleDefaultHiddenBuiltInColumns")
    private static let defaultHiddenBuiltInColumns: Set<String> = ["version"]

    private let defaults: UserDefaults

    // Bounded case-insensitive indexes for incremental discovery.
    private var discoveredRequestHeaderSet = DiscoveredHeaderNames()
    private var discoveredResponseHeaderSet = DiscoveredHeaderNames()

    private func persistDiscoveredHeaders() {
        discoveredRequestHeaders = discoveredRequestHeaderSet.sortedNames
        discoveredResponseHeaders = discoveredResponseHeaderSet.sortedNames
        defaults.set(discoveredRequestHeaders, forKey: Self.discoveredReqKey)
        defaults.set(discoveredResponseHeaders, forKey: Self.discoveredResKey)
    }

    private func saveHiddenColumns() {
        let array = Array(hiddenBuiltInColumns)
        defaults.set(array, forKey: Self.hiddenColumnsKey)
        defaults.set(
            Array(visibleDefaultHiddenBuiltInColumns),
            forKey: Self.visibleDefaultHiddenColumnsKey
        )
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(columns)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            Self.logger.error("Failed to save header columns: \(error.localizedDescription)")
        }
    }

    private func load() {
        if let hidden = defaults.stringArray(forKey: Self.hiddenColumnsKey) {
            hiddenBuiltInColumns = Set(hidden)
        }
        if let visibleDefaultHidden = defaults.stringArray(forKey: Self.visibleDefaultHiddenColumnsKey) {
            visibleDefaultHiddenBuiltInColumns = Set(visibleDefaultHidden)
        }
        if let reqHeaders = defaults.stringArray(forKey: Self.discoveredReqKey) {
            discoveredRequestHeaderSet = DiscoveredHeaderNames(reqHeaders)
            discoveredRequestHeaders = discoveredRequestHeaderSet.sortedNames
            if discoveredRequestHeaders != reqHeaders {
                defaults.set(discoveredRequestHeaders, forKey: Self.discoveredReqKey)
            }
        }
        if let resHeaders = defaults.stringArray(forKey: Self.discoveredResKey) {
            discoveredResponseHeaderSet = DiscoveredHeaderNames(resHeaders)
            discoveredResponseHeaders = discoveredResponseHeaderSet.sortedNames
            if discoveredResponseHeaders != resHeaders {
                defaults.set(discoveredResponseHeaders, forKey: Self.discoveredResKey)
            }
        }
        guard let data = defaults.data(forKey: Self.storageKey) else {
            return
        }
        do {
            columns = try JSONDecoder().decode([HeaderColumn].self, from: data)
            Self.logger.info("Loaded \(self.columns.count) header columns")
        } catch {
            Self.logger.error("Failed to load header columns: \(error.localizedDescription)")
        }
    }
}

// MARK: - DiscoveredHeaderNames

/// Bounded suggestions only; captured headers and manually configured columns stay complete.
struct DiscoveredHeaderNames {
    // MARK: Lifecycle

    init(_ names: [String] = []) {
        for name in names {
            insert(name)
        }
    }

    // MARK: Internal

    static let maximumCount = 1_024

    var sortedNames: [String] {
        namesByKey.values.sorted()
    }

    @discardableResult
    mutating func insert(_ name: String) -> Bool {
        let key = name.lowercased()
        if let existing = namesByKey[key] {
            let preferred = min(existing, name)
            guard preferred != existing else {
                return false
            }
            namesByKey[key] = preferred
            return true
        }
        guard namesByKey.count < Self.maximumCount else {
            return false
        }
        namesByKey[key] = name
        return true
    }

    // MARK: Private

    private var namesByKey: [String: String] = [:]
}
