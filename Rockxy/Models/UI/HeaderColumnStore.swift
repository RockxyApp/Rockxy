import Foundation
import os

// Persists and coordinates custom header column configuration for the traffic table.

@MainActor @Observable
final class HeaderColumnStore {
    // MARK: Lifecycle

    init() {
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
        if columnID.hasPrefix("reqHeader.") {
            let headerName = String(columnID.dropFirst("reqHeader.".count))
            return transaction.request.headers
                .first { $0.name.caseInsensitiveCompare(headerName) == .orderedSame }?
                .value ?? ""
        } else if columnID.hasPrefix("resHeader.") {
            let headerName = String(columnID.dropFirst("resHeader.".count))
            return transaction.response?.headers
                .first { $0.name.caseInsensitiveCompare(headerName) == .orderedSame }?
                .value ?? ""
        }
        return ""
    }

    // MARK: - Column Management

    @discardableResult
    func addColumn(headerName: String, source: HeaderColumnSource) -> HeaderColumn {
        if let existing = columns.first(where: { $0.headerName == headerName && $0.source == source }) {
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
        columns.contains { $0.headerName == headerName && $0.source == source }
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
        var requestHeaders: Set<String> = []
        var responseHeaders: Set<String> = []

        let sampleSize = min(transactions.count, 200)
        for transaction in transactions.prefix(sampleSize) {
            for header in transaction.request.headers {
                requestHeaders.insert(header.name)
            }
            if let response = transaction.response {
                for header in response.headers {
                    responseHeaders.insert(header.name)
                }
            }
        }

        let existingRequestNames = Set(requestColumns.map(\.headerName))
        let existingResponseNames = Set(responseColumns.map(\.headerName))

        return DiscoveredHeaders(
            request: requestHeaders.subtracting(existingRequestNames).sorted(),
            response: responseHeaders.subtracting(existingResponseNames).sorted()
        )
    }

    func updateDiscoveredHeaders(from transactions: [HTTPTransaction]) {
        var requestHeaders: Set<String> = []
        var responseHeaders: Set<String> = []

        for transaction in transactions {
            for header in transaction.request.headers {
                requestHeaders.insert(header.name)
            }
            if let response = transaction.response {
                for header in response.headers {
                    responseHeaders.insert(header.name)
                }
            }
        }

        discoveredRequestHeaderSet = requestHeaders
        discoveredResponseHeaderSet = responseHeaders
        discoveredRequestHeaders = requestHeaders.sorted()
        discoveredResponseHeaders = responseHeaders.sorted()
        UserDefaults.standard.set(discoveredRequestHeaders, forKey: Self.discoveredReqKey)
        UserDefaults.standard.set(discoveredResponseHeaders, forKey: Self.discoveredResKey)
    }

    /// Incremental header discovery from a batch of new transactions. O(batch_size) per call
    /// with O(1) membership checks via internal sets. Replaces the old full-scan approach that
    /// was biased toward the oldest 500 transactions.
    func updateDiscoveredHeaders(fromBatch batch: [HTTPTransaction]) {
        var changed = false
        for transaction in batch {
            for header in transaction.request.headers {
                if discoveredRequestHeaderSet.insert(header.name).inserted {
                    changed = true
                }
            }
            if let response = transaction.response {
                for header in response.headers {
                    if discoveredResponseHeaderSet.insert(header.name).inserted {
                        changed = true
                    }
                }
            }
        }
        if changed {
            discoveredRequestHeaders = discoveredRequestHeaderSet.sorted()
            discoveredResponseHeaders = discoveredResponseHeaderSet.sorted()
            UserDefaults.standard.set(discoveredRequestHeaders, forKey: Self.discoveredReqKey)
            UserDefaults.standard.set(discoveredResponseHeaders, forKey: Self.discoveredResKey)
        }
    }

    func toggleBuiltInColumn(_ columnID: String) {
        if hiddenBuiltInColumns.contains(columnID) {
            hiddenBuiltInColumns.remove(columnID)
        } else {
            hiddenBuiltInColumns.insert(columnID)
        }
        saveHiddenColumns()
    }

    func isBuiltInColumnVisible(_ columnID: String) -> Bool {
        !hiddenBuiltInColumns.contains(columnID)
    }

    func reload() {
        load()
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "HeaderColumnStore")
    private static let storageKey = RockxyIdentity.current.defaultsKey("headerColumns")
    private static let discoveredReqKey = RockxyIdentity.current.defaultsKey("discoveredReqHeaders")
    private static let discoveredResKey = RockxyIdentity.current.defaultsKey("discoveredResHeaders")
    private static let hiddenColumnsKey = RockxyIdentity.current.defaultsKey("hiddenBuiltInColumns")

    // Internal dedup sets for O(1) membership checks during incremental discovery
    private var discoveredRequestHeaderSet: Set<String> = []
    private var discoveredResponseHeaderSet: Set<String> = []

    private func saveHiddenColumns() {
        let array = Array(hiddenBuiltInColumns)
        UserDefaults.standard.set(array, forKey: Self.hiddenColumnsKey)
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(columns)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            Self.logger.error("Failed to save header columns: \(error.localizedDescription)")
        }
    }

    private func load() {
        if let hidden = UserDefaults.standard.stringArray(forKey: Self.hiddenColumnsKey) {
            hiddenBuiltInColumns = Set(hidden)
        }
        if let reqHeaders = UserDefaults.standard.stringArray(forKey: Self.discoveredReqKey) {
            discoveredRequestHeaders = reqHeaders
            discoveredRequestHeaderSet = Set(reqHeaders)
        }
        if let resHeaders = UserDefaults.standard.stringArray(forKey: Self.discoveredResKey) {
            discoveredResponseHeaders = resHeaders
            discoveredResponseHeaderSet = Set(resHeaders)
        }
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else {
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
