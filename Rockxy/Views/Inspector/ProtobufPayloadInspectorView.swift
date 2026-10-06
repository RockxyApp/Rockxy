import SwiftUI

// Protobuf view shared by request bodies, response bodies, and WebSocket frames.

// MARK: - ProtobufPayloadContext

/// Where a payload came from, so the automatic message type can follow mapping definitions
/// and gRPC service methods.
struct ProtobufPayloadContext: Equatable {
    let url: URL?
    let method: String?
    let direction: ProtobufPayloadDirection
}

// MARK: - ProtobufPayloadInspectorView

/// Decodes a payload with an imported schema's message type — chosen automatically from a
/// matching mapping definition or gRPC method, or picked by the user — and falls back to
/// best-guess wire decoding when no schema applies.
struct ProtobufPayloadInspectorView: View {
    // MARK: Internal

    let payload: Data
    let context: ProtobufPayloadContext
    /// Changes when a different payload is shown, resetting a manual type choice.
    let payloadID: String
    /// When set, a manual type choice survives payload changes until this value changes, so
    /// stepping through a socket's frames keeps the message type the user picked.
    var choiceScopeID: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: DecodeKey(payloadID: payloadID, choice: effectiveChoice, schemaVersion: schemaVersion)) {
            await decode()
        }
        .onChange(of: choiceScopeID ?? payloadID) {
            manualChoice = nil
        }
    }

    // MARK: Private

    private struct DecodeKey: Equatable {
        let payloadID: String
        let choice: ProtobufDecodeChoice
        let schemaVersion: Int
    }

    /// Up to this many message types are listed inline in the menu; larger schemas get a
    /// searchable picker.
    private static let inlineMessageLimit = 12

    @State private var showsTypePicker = false
    @State private var manualChoice: ProtobufDecodeChoice?
    @State private var result: Result<ProtobufDecodedTree, Error>?
    @State private var schemaStore = ProtobufSchemaStore.shared
    @State private var mappingStore = ProtobufMappingRuleStore.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.appUIDisplayMetrics) private var metrics

    /// Changes whenever schemas or mapping definitions change, so the view re-decodes.
    private var schemaVersion: Int {
        var hasher = Hasher()
        hasher.combine(schemaStore.schemas.map(\.id))
        hasher.combine(mappingStore.rules.map(\.id))
        hasher.combine(mappingStore.rules.map(\.isEnabled))
        hasher.combine(mappingStore.rules.map(\.messageType))
        hasher.combine(mappingStore.rules.map(\.requestMessageType))
        hasher.combine(mappingStore.rules.map(\.responseMessageType))
        hasher.combine(mappingStore.rules.map(\.urlPattern))
        return hasher.finalize()
    }

    private var automaticChoice: ProtobufDecodeChoice {
        _ = schemaVersion
        return ProtobufDecodeResolver.automaticChoice(
            url: context.url,
            method: context.method,
            direction: context.direction,
            rules: mappingStore.rules,
            schema: schemaStore.combinedSchema()
        )
    }

    private var effectiveChoice: ProtobufDecodeChoice {
        manualChoice ?? automaticChoice
    }

    private var messageNames: [String] {
        schemaStore.combinedSchema().messageNames
    }

    private var automaticTitle: String {
        switch automaticChoice {
        case .bestGuess:
            String(localized: "Automatic (Best Guess)", bundle: RockxyLocalization.bundle)
        case let .messageType(name, _):
            String(localized: "Automatic (\(name))", bundle: RockxyLocalization.bundle)
        }
    }

    private var choiceTitle: String {
        switch manualChoice {
        case nil:
            automaticTitle
        case .bestGuess?:
            String(localized: "Best Guess (No Schema)", bundle: RockxyLocalization.bundle)
        case let .messageType(name, _)?:
            name
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text(String(localized: "Decode As", bundle: RockxyLocalization.bundle))
                .foregroundStyle(.secondary)
            Menu {
                Button(automaticTitle) {
                    manualChoice = nil
                }
                Button(String(localized: "Best Guess (No Schema)", bundle: RockxyLocalization.bundle)) {
                    manualChoice = .bestGuess
                }
                if messageNames.count > Self.inlineMessageLimit {
                    Divider()
                    Button(String(localized: "Choose Message Type…", bundle: RockxyLocalization.bundle)) {
                        showsTypePicker = true
                    }
                } else if !messageNames.isEmpty {
                    Divider()
                    ForEach(messageNames, id: \.self) { name in
                        Button(name) {
                            manualChoice = .messageType(name, encoding: .auto)
                        }
                    }
                }
                Divider()
                Button(String(localized: "Manage Schemas…", bundle: RockxyLocalization.bundle)) {
                    openWindow(id: "protobufSchemaList")
                }
                Button(String(localized: "Protobuf Mapping…", bundle: RockxyLocalization.bundle)) {
                    openWindow(id: "protobufSettings")
                }
            } label: {
                Text(choiceTitle)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .menuStyle(.button)
            .fixedSize()
            .accessibilityIdentifier("protobuf.decodeAs")
            .popover(isPresented: $showsTypePicker, arrowEdge: .bottom) {
                ProtobufMessageTypePicker(names: messageNames) { name in
                    manualChoice = .messageType(name, encoding: .auto)
                    showsTypePicker = false
                }
            }
            .help(String(
                localized: "Choose the message type used to decode this payload.",
                bundle: RockxyLocalization.bundle
            ))
            Spacer(minLength: 0)
        }
        .font(.system(size: metrics.secondaryFontSize))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    @ViewBuilder private var content: some View {
        switch result {
        case nil:
            ProgressView()
                .controlSize(.small)
        case let .success(tree)?:
            ProtobufTreeView(tree: tree)
        case let .failure(error)?:
            InspectorEmptyStateView(
                effectiveChoice == .bestGuess
                    ? String(localized: "No Protobuf Fields", bundle: RockxyLocalization.bundle)
                    : String(localized: "Could Not Decode", bundle: RockxyLocalization.bundle),
                systemImage: "curlybraces",
                description: error.localizedDescription
            )
        }
    }

    private func decode() async {
        let data = payload
        let choice = effectiveChoice
        let schema = schemaStore.combinedSchema()
        let decoded = await Task.detached(priority: .userInitiated) {
            ProtobufDecodeResolver.decode(data, choice: choice, schema: schema)
        }.value
        guard !Task.isCancelled else {
            return
        }
        result = decoded
    }
}

// MARK: - ProtobufBodyInspection

/// Decides when an HTTP body gets a Protobuf tab: the body declares a Protobuf media type, or a
/// mapping definition assigns it a message type. gRPC bodies stay in the gRPC tab.
@MainActor
enum ProtobufBodyInspection {
    static func isApplicable(to transaction: HTTPTransaction, direction: ProtobufPayloadDirection) -> Bool {
        guard let body = rawBody(of: transaction, direction: direction), !body.isEmpty else {
            return false
        }
        let contentType = headerValue("Content-Type", in: headers(of: transaction, direction: direction))?
            .lowercased() ?? ""
        if contentType.hasPrefix("application/grpc") {
            return false
        }
        if contentType.contains("protobuf") || contentType.contains("x-protobuf") {
            return true
        }
        return ProtobufDecodeResolver.automaticChoice(
            url: transaction.request.url,
            method: transaction.request.method,
            direction: direction
        ) != .bestGuess
    }

    /// The body with any Content-Encoding (gzip, br, deflate) removed.
    static func payload(of transaction: HTTPTransaction, direction: ProtobufPayloadDirection) -> Data {
        let body = rawBody(of: transaction, direction: direction) ?? Data()
        let encoding = headerValue("Content-Encoding", in: headers(of: transaction, direction: direction))
        return BodyDecoder.decode(body, encoding: encoding)
    }

    static func context(of transaction: HTTPTransaction, direction: ProtobufPayloadDirection) -> ProtobufPayloadContext {
        ProtobufPayloadContext(url: transaction.request.url, method: transaction.request.method, direction: direction)
    }

    private static func rawBody(of transaction: HTTPTransaction, direction: ProtobufPayloadDirection) -> Data? {
        direction == .request ? transaction.request.body : transaction.response?.body
    }

    private static func headers(of transaction: HTTPTransaction, direction: ProtobufPayloadDirection) -> [HTTPHeader] {
        direction == .request ? transaction.request.headers : transaction.response?.headers ?? []
    }

    private static func headerValue(_ name: String, in headers: [HTTPHeader]) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

// MARK: - ProtobufMessageTypePicker

/// Searchable list of a schema's message types, for descriptor sets too large for a menu.
private struct ProtobufMessageTypePicker: View {
    let names: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            TextField(String(localized: "Search message types", bundle: RockxyLocalization.bundle), text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(8)
            Divider()
            List(filteredNames, id: \.self) { name in
                Button(name) {
                    onSelect(name)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
            }
            .frame(width: 380, height: 280)
        }
    }

    @State private var query = ""

    private var filteredNames: [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return names
        }
        return names.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }
}
