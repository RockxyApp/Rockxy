import Foundation
import os

// Coordinates paused breakpoint items and user decisions across the breakpoint workflow.

// MARK: - PausedBreakpointItem

/// A single HTTP transaction paused by a breakpoint rule, queued for user inspection.
/// The `editableDraft` is mutated by the editor view; the final state is sent back
/// to the proxy pipeline when the user resolves the item.
struct PausedBreakpointItem: Identifiable {
    let id: UUID
    let sequenceNumber: Int
    let phase: BreakpointPhase
    let host: String
    let path: String
    let url: String
    let client: String
    let queryName: String
    let method: String
    let statusCode: Int?
    let matchedRuleName: String?
    let createdAt: Date
    var editableDraft: BreakpointRequestData
}

// MARK: - BreakpointManager

/// Queue-backed breakpoint manager that holds multiple paused transactions simultaneously.
/// The proxy pipeline calls `enqueueAndWait(_:)` which suspends until the user resolves
/// the item in the Breakpoints window. Replaces the single-item `BreakpointViewModel`.
@MainActor @Observable
final class BreakpointManager {
    // MARK: Internal

    static let shared = BreakpointManager()

    private(set) var pausedItems: [PausedBreakpointItem] = []
    var selectedItemId: UUID?

    var hasPausedItems: Bool {
        !pausedItems.isEmpty
    }

    /// Called by the proxy pipeline to pause execution and wait for a user decision.
    /// Returns the decision AND the potentially-modified request data.
    func enqueueAndWait(_ data: BreakpointRequestData) async -> (BreakpointDecision, BreakpointRequestData) {
        let components = URLComponents(string: data.url)
        let host = components?.host ?? ""
        let path = components?.path ?? "/"

        let itemId = UUID()
        nextSequenceNumber += 1
        let item = PausedBreakpointItem(
            id: itemId,
            sequenceNumber: nextSequenceNumber,
            phase: data.phase,
            host: host,
            path: path,
            url: Self.displayURL(from: data.url),
            client: Self.clientLabel(from: data.headers),
            queryName: Self.queryName(from: data),
            method: data.method,
            statusCode: data.phase == .response ? data.statusCode : nil,
            matchedRuleName: nil,
            createdAt: Date(),
            editableDraft: data
        )

        return await withCheckedContinuation { continuation in
            continuations[itemId] = continuation
            pausedItems.append(item)
            if selectedItemId == nil {
                selectedItemId = itemId
            }
            BreakpointWindowModel.shared.selectPausedItem(item.id)
            Self.logger.info("Breakpoint paused: \(host)\(path)")
            NotificationCenter.default.post(name: .breakpointHit, object: nil)
        }
    }

    /// Resolve a single paused item with the given decision.
    func resolve(id: UUID, decision: BreakpointDecision) {
        guard let index = pausedItems.firstIndex(where: { $0.id == id }) else {
            return
        }
        let item = pausedItems[index]
        pausedItems.remove(at: index)

        if let continuation = continuations.removeValue(forKey: id) {
            continuation.resume(returning: (decision, item.editableDraft))
        }

        if selectedItemId == id {
            selectedItemId = pausedItems.first?.id
        }

        BreakpointWindowModel.shared.handlePausedResolutionFallback(remainingPausedItems: pausedItems)

        Self.logger.info("Breakpoint resolved (\(String(describing: decision))): \(item.host)\(item.path)")
    }

    /// Resolve all paused items at once with the same decision.
    func resolveAll(decision: BreakpointDecision) {
        for item in pausedItems {
            if let continuation = continuations.removeValue(forKey: item.id) {
                continuation.resume(returning: (decision, item.editableDraft))
            }
        }
        let count = pausedItems.count
        pausedItems.removeAll()
        selectedItemId = nil
        Self.logger.info("Breakpoint resolved all (\(count) items, \(String(describing: decision)))")
    }

    /// Update the editable draft for a specific paused item (called by the editor view bindings).
    func updateDraft(id: UUID, _ transform: (inout BreakpointRequestData) -> Void) {
        guard let index = pausedItems.firstIndex(where: { $0.id == id }) else {
            return
        }
        transform(&pausedItems[index].editableDraft)
    }

    func selectPreviousItem() {
        selectAdjacentItem(offset: -1)
    }

    func selectNextItem() {
        selectAdjacentItem(offset: 1)
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "BreakpointManager")

    private var continuations: [UUID: CheckedContinuation<(BreakpointDecision, BreakpointRequestData), Never>] = [:]
    private var nextSequenceNumber = 0

    private func selectAdjacentItem(offset: Int) {
        guard !pausedItems.isEmpty else {
            selectedItemId = nil
            return
        }
        guard let selectedItemId,
              let index = pausedItems.firstIndex(where: { $0.id == selectedItemId }) else
        {
            selectedItemId = pausedItems.first?.id
            return
        }
        let nextIndex = (index + offset + pausedItems.count) % pausedItems.count
        self.selectedItemId = pausedItems[nextIndex].id
        BreakpointWindowModel.shared.selectPausedItem(pausedItems[nextIndex].id)
    }

    private static func displayURL(from urlString: String) -> String {
        guard let components = URLComponents(string: urlString) else {
            return urlString
        }
        var display = components.host ?? urlString
        if let port = components.port {
            display += ":\(port)"
        }
        display += components.path.isEmpty ? "/" : components.path
        if let query = components.percentEncodedQuery, !query.isEmpty {
            display += "?\(query)"
        }
        return display
    }

    private static func clientLabel(from headers: [EditableHeader]) -> String {
        let directHeaderNames = [
            "x-rockxy-runtime",
            "x-client",
            "x-client-name",
            "x-runtime",
        ]
        for headerName in directHeaderNames {
            if let value = headers.first(where: { $0.name.lowercased() == headerName })?.value
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty
            {
                return value
            }
        }
        guard let userAgent = headers.first(where: { $0.name.lowercased() == "user-agent" })?.value,
              !userAgent.isEmpty
        else {
            return String(localized: "Unknown")
        }
        if !userAgent.contains("Mozilla/"), let slash = userAgent.firstIndex(of: "/") {
            let name = String(userAgent[..<slash])
            return name.isEmpty ? userAgent : name
        }
        if userAgent.contains("Chrome/") {
            return "Google Chrome"
        }
        if userAgent.contains("Firefox/") {
            return "Firefox"
        }
        if userAgent.contains("Safari/") {
            return "Safari"
        }
        return userAgent
    }

    private static func queryName(from data: BreakpointRequestData) -> String {
        if let components = URLComponents(string: data.url),
           let operationName = components.queryItems?.first(where: {
               ["operationName", "queryName"].contains($0.name)
           })?.value,
           !operationName.isEmpty
        {
            return operationName
        }
        guard let contentType = data.headers.first(where: {
            $0.name.caseInsensitiveCompare("content-type") == .orderedSame
        })?.value.lowercased(),
              contentType.contains("json"),
              let bodyData = data.body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let operationName = object["operationName"] as? String,
              !operationName.isEmpty
        else {
            return ""
        }
        return operationName
    }
}
