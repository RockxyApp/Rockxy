import Foundation
import os
import SwiftUI

// Built-in inspector plugin for JSON content. Renders request and response
// bodies as a collapsible tree with syntax-colored values, similar to the
// JSON viewer in Proxyman and Safari Web Inspector.

// MARK: - JSONInspector

struct JSONInspector: InspectorPlugin {
    // MARK: Internal

    let name = "JSON Inspector"
    let supportedContentTypes: [ContentType] = [.json]

    @MainActor
    func inspectorView(for transaction: HTTPTransaction) -> AnyView {
        AnyView(JSONInspectorView(transaction: transaction))
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "JSONInspector"
    )
}

// MARK: - JSONInspectorView

private struct JSONInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabBar
            Divider()
            contentArea
        }
    }

    // MARK: Private

    @State private var selectedTab: JSONTab = .response

    private var tabBar: some View {
        HStack(spacing: 12) {
            if transaction.response?.body != nil {
                tabButton(.response)
            }
            if transaction.request.body != nil {
                tabButton(.request)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var contentArea: some View {
        ScrollView([.horizontal, .vertical]) {
            let data = bodyData(for: selectedTab)
            if let data, let parsed = parseJSON(data) {
                JSONNodeTreeView(value: parsed, label: "root", depth: 0)
                    .padding(12)
            } else if let data, let text = String(data: data, encoding: .utf8) {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .textSelection(.enabled)
            } else {
                Text(String(localized: "No data available"))
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(12)
            }
        }
    }

    private func tabButton(_ tab: JSONTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Text(tab.title)
                .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                .foregroundStyle(selectedTab == tab ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func bodyData(for tab: JSONTab) -> Data? {
        switch tab {
        case .request:
            transaction.request.body
        case .response:
            transaction.response?.body
        }
    }

    private func parseJSON(_ data: Data) -> JSONValue? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return JSONValue(from: object)
    }
}

// MARK: - JSONTab

private enum JSONTab {
    case request
    case response

    // MARK: Internal

    var title: String {
        switch self {
        case .request: String(localized: "Request Body")
        case .response: String(localized: "Response Body")
        }
    }
}

// MARK: - JSONValue

/// Recursive enum representing a parsed JSON document. Bridges from
/// `JSONSerialization`'s `Any` output to a strongly-typed tree that
/// `JSONNodeTreeView` can render with `ForEach`.
private enum JSONValue: Identifiable {
    case string(String)
    case number(NSNumber)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([(key: String, value: JSONValue)])

    // MARK: Lifecycle

    init?(from object: Any) {
        switch object {
        case let dict as [String: Any]:
            let pairs = dict.keys.sorted().compactMap { key -> (key: String, value: JSONValue)? in
                guard let val = JSONValue(from: dict[key] as Any) else {
                    return nil
                }
                return (key: key, value: val)
            }
            self = .object(pairs)

        case let array as [Any]:
            let values = array.compactMap { JSONValue(from: $0) }
            self = .array(values)

        case let string as String:
            self = .string(string)

        case let number as NSNumber:
            // NSNumber wraps both booleans and numbers; CFBoolean check distinguishes them
            if CFBooleanGetTypeID() == CFGetTypeID(number) {
                self = .bool(number.boolValue)
            } else {
                self = .number(number)
            }

        case is NSNull:
            self = .null

        default:
            return nil
        }
    }

    // MARK: Internal

    nonisolated var id: String {
        UUID().uuidString
    }
}

// MARK: - JSONNodeTreeView

private struct JSONNodeTreeView: View {
    // MARK: Internal

    let value: JSONValue
    let label: String
    let depth: Int

    var body: some View {
        switch value {
        case let .object(pairs):
            objectView(pairs: pairs)
        case let .array(items):
            arrayView(items: items)
        case let .string(str):
            leafView(label: label, valueText: "\"\(str)\"", color: .green)
        case let .number(num):
            leafView(label: label, valueText: "\(num)", color: .blue)
        case let .bool(val):
            leafView(label: label, valueText: val ? "true" : "false", color: .orange)
        case .null:
            leafView(label: label, valueText: "null", color: .gray)
        }
    }

    // MARK: Private

    @State private var isExpanded = true

    private func objectView(pairs: [(key: String, value: JSONValue)]) -> some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                JSONNodeTreeView(value: pair.value, label: pair.key, depth: depth + 1)
            }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                Text("{\(pairs.count)}")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func arrayView(items: [JSONValue]) -> some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                JSONNodeTreeView(value: item, label: "[\(index)]", depth: depth + 1)
            }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                Text("[\(items.count)]")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func leafView(label: String, valueText: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
            Text(":")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(valueText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(color)
                .textSelection(.enabled)
        }
    }
}
