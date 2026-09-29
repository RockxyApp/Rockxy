import SwiftUI

// MARK: - WebSocketInspectorView

/// WebSocket inspector tab content showing connection summary, frame list with
/// direction filtering, and selected-frame detail panel. Reads `webSocketFrameVersion`
/// to trigger live repaint as frames arrive from the NIO pipeline.
struct WebSocketInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction

    var body: some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = transaction.webSocketFrameVersion
        Group {
            if let connection = transaction.webSocketConnection {
                // The summary, filter, detail header, and payload picker alone outgrow a short
                // bottom inspector, and an oversized stack pushes the inspector's own URL bar and
                // tab strip out of view. Scrolling the tab instead keeps that chrome fixed; the
                // frame list gets a bounded height so it scrolls on its own inside the tab.
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        connectionSummary(connection)
                        Divider()
                        directionFilter(connection)
                        Divider()
                        frameList(connection)
                            .frame(height: frameListHeight(for: connection))
                        if selectedFrame != nil {
                            Divider()
                            frameDetail
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                InspectorEmptyStateView(
                    String(localized: "No WebSocket Data", bundle: RockxyLocalization.bundle),
                    systemImage: "arrow.left.arrow.right",
                    description: String(
                        localized: "This request does not contain WebSocket frames.",
                        bundle: RockxyLocalization.bundle
                    )
                )
            }
        }
        .task(id: transaction.id) {
            selectedFrameID = nil
        }
        .onChange(of: selectedFrameID) { _, _ in
            payloadMode = selectedFrame
                .map { ProtobufDetector.isLikelyProtobuf($0.payload) } == true ? .protobuf : .payload
        }
    }

    // MARK: Private

    private static let maxPayloadPreviewBytes = 512
    /// Bounds for the frame list inside the scrolling tab: a few rows minimum so the selection
    /// context never vanishes, and a cap so long sessions scroll within the list.
    private static let frameRowHeight: CGFloat = 26
    private static let minimumFrameListRows = 3
    private static let maximumFrameListRows = 8

    private func frameListHeight(for connection: WebSocketConnection) -> CGFloat {
        let rows = max(Self.minimumFrameListRows, min(Self.maximumFrameListRows, filteredFrames(connection).count))
        return CGFloat(rows) * Self.frameRowHeight + 8
    }

    @State private var selectedFrameID: UUID?
    @State private var directionFilterValue: FrameDirection?
    @State private var showDetail = true
    @State private var payloadMode: WebSocketPayloadInspectorMode = .payload
    @State private var frameSearchText = ""
    @State private var formatsJSONPayloads = true
    @Environment(\.appUIDisplayMetrics) private var metrics

    private var selectedFrame: WebSocketFrameData? {
        guard let id = selectedFrameID,
              let connection = transaction.webSocketConnection else
        {
            return nil
        }
        return connection.frames.first { $0.id == id }
    }

    // MARK: - Frame Detail

    private var frameDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showDetail.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showDetail ? "chevron.down" : "chevron.right")
                        .font(.system(size: metrics.badgeFontSize))
                    Text(String(localized: "Frame Detail", bundle: RockxyLocalization.bundle))
                        .font(.system(size: metrics.secondaryFontSize))
                        .fontWeight(.medium)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, showDetail ? 4 : 6)

            if showDetail, let frame = selectedFrame {
                HStack(spacing: 12) {
                    HStack(spacing: 2) {
                        Text(String(localized: "Direction:", bundle: RockxyLocalization.bundle))
                            .foregroundStyle(.secondary)
                        Image(systemName: frame.direction == .sent ? "arrow.up.circle" : "arrow.down.circle")
                            .foregroundStyle(frame.direction == .sent ? .blue : .green)
                        Text(frame.direction == .sent
                            ? String(localized: "Sent", bundle: RockxyLocalization.bundle)
                            : String(localized: "Received", bundle: RockxyLocalization.bundle))
                    }
                    HStack(spacing: 2) {
                        Text(String(localized: "Type:", bundle: RockxyLocalization.bundle)).foregroundStyle(.secondary)
                        Text(opcodeInfo(frame.opcode).0)
                    }
                    HStack(spacing: 2) {
                        Text(String(localized: "Size:", bundle: RockxyLocalization.bundle)).foregroundStyle(.secondary)
                        Text(SizeFormatter.format(bytes: frame.payload.count))
                    }
                }
                .font(.system(size: metrics.metadataFontSize))
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

                Divider()

                framePayloadView(frame)
            } else if showDetail {
                InspectorEmptyStateView(
                    String(localized: "No Frame Selected", bundle: RockxyLocalization.bundle),
                    systemImage: "arrow.left.arrow.right",
                    description: String(
                        localized: "Select a frame to inspect its payload.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                .frame(maxHeight: 120)
            }
        }
    }

    // MARK: - Connection Summary

    private func connectionSummary(_ connection: WebSocketConnection) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            summaryRow(
                String(localized: "URL", bundle: RockxyLocalization.bundle),
                value: connection.upgradeRequest.url.absoluteString
            )
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    summaryLabel(String(localized: "State", bundle: RockxyLocalization.bundle))
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(transaction.state == .completed ? .red : .green)
                    Text(transaction.state == .completed
                        ? String(localized: "Closed", bundle: RockxyLocalization.bundle)
                        : String(localized: "Active", bundle: RockxyLocalization.bundle))
                        .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                }
                TimelineView(.animation(minimumInterval: 1, paused: !transaction.isRunning)) { context in
                    if let duration = transaction.displayDuration(at: context.date) {
                        summaryRow(
                            String(localized: "Duration", bundle: RockxyLocalization.bundle),
                            value: DurationFormatter.format(seconds: duration)
                        )
                    }
                }
            }
            HStack(spacing: 16) {
                summaryRow(
                    String(localized: "Sent", bundle: RockxyLocalization.bundle),
                    value: frameCountSummary(connection.sentFrames)
                )
                summaryRow(
                    String(localized: "Received", bundle: RockxyLocalization.bundle),
                    value: frameCountSummary(connection.receivedFrames)
                )
            }
            if connection.isCaptureLimitReached {
                Label(
                    String(
                        localized: "Frame capture stopped at the safety limit; the live connection remains active.",
                        bundle: RockxyLocalization.bundle
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: metrics.secondaryFontSize))
                .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5))
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack(spacing: 4) {
            summaryLabel(label)
            Text(value)
                .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func summaryLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: metrics.secondaryFontSize))
            .foregroundStyle(.secondary)
    }

    // MARK: - Direction Filter

    private func directionFilter(_ connection: WebSocketConnection) -> some View {
        Picker(selection: $directionFilterValue) {
            Text(String(localized: "All (\(connection.frameCount))", bundle: RockxyLocalization.bundle))
                .tag(FrameDirection?.none)
            Text("↑ \(String(localized: "Sent", bundle: RockxyLocalization.bundle)) (\(CountFormatter.format(connection.sentFrames.count)))")
                .tag(Optional(FrameDirection.sent))
            Text(
                "↓ \(String(localized: "Received", bundle: RockxyLocalization.bundle)) (\(CountFormatter.format(connection.receivedFrames.count)))"
            )
            .tag(Optional(FrameDirection.received))
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) {
            TextField(
                String(localized: "Filter Frames", bundle: RockxyLocalization.bundle),
                text: $frameSearchText
            )
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .frame(width: 180)
            .accessibilityLabel(String(localized: "Filter frames by payload text", bundle: RockxyLocalization.bundle))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    // MARK: - Frame List

    private func frameList(_ connection: WebSocketConnection) -> some View {
        let frames = filteredFrames(connection)
        return Group {
            if frames.isEmpty {
                InspectorEmptyStateView(
                    String(localized: "Waiting for Frames", bundle: RockxyLocalization.bundle),
                    systemImage: "arrow.left.arrow.right",
                    description: String(
                        localized: "WebSocket connection established. Frames will appear here as they arrive.",
                        bundle: RockxyLocalization.bundle
                    )
                )
            } else {
                List(frames, selection: $selectedFrameID) { frame in
                    frameRow(frame)
                        .tag(frame.id)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    private func frameRow(_ frame: WebSocketFrameData) -> some View {
        HStack(spacing: 4) {
            Text(formatTimestamp(frame.timestamp))
                .font(.system(size: metrics.metadataFontSize, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)

            Image(systemName: frame.direction == .sent ? "arrow.up.circle" : "arrow.down.circle")
                .font(.system(size: metrics.secondaryFontSize))
                .foregroundStyle(frame.direction == .sent ? .blue : .green)
                .frame(width: 16)

            opcodeBadge(frame.opcode)
                .frame(width: 42, alignment: .leading)

            Text(payloadPreview(frame))
                .font(.system(size: metrics.metadataFontSize, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Text(SizeFormatter.format(bytes: frame.payload.count))
                .font(.system(size: metrics.metadataFontSize, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 1)
    }

    private func opcodeBadge(_ opcode: FrameOpcode) -> some View {
        let (label, color) = opcodeInfo(opcode)
        return Text(label)
            .font(.system(size: metrics.badgeFontSize, weight: .medium, design: .monospaced))
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    @ViewBuilder
    private func framePayloadView(_ frame: WebSocketFrameData) -> some View {
        if frame.payload.isEmpty {
            Text(String(localized: "(empty payload)", bundle: RockxyLocalization.bundle))
                .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(12)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Picker(
                        String(localized: "Payload View", bundle: RockxyLocalization.bundle),
                        selection: $payloadMode
                    ) {
                        Text(String(localized: "Payload", bundle: RockxyLocalization.bundle))
                            .tag(WebSocketPayloadInspectorMode.payload)
                        Text(String(localized: "Protobuf", bundle: RockxyLocalization.bundle))
                            .tag(WebSocketPayloadInspectorMode.protobuf)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 190)

                    if payloadMode == .payload, frame.opcode == .text {
                        Toggle(
                            String(localized: "Format JSON", bundle: RockxyLocalization.bundle),
                            isOn: $formatsJSONPayloads
                        )
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                    }

                    if ProtobufDetector.isLikelyProtobuf(frame.payload) {
                        Label(
                            String(localized: "Likely Protobuf", bundle: RockxyLocalization.bundle),
                            systemImage: "sparkles"
                        )
                        .font(.system(size: metrics.metadataFontSize))
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Divider()

                switch payloadMode {
                case .payload:
                    rawPayloadView(frame)
                case .protobuf:
                    protobufPayloadView(frame)
                }
            }
        }
    }

    @ViewBuilder
    private func rawPayloadView(_ frame: WebSocketFrameData) -> some View {
        if frame.opcode == .text || frame.opcode == .connectionClose,
           frame.payload.isProbablyUTF8Text
        {
            let payload = frame.payload
            let formatsJSON = formatsJSONPayloads
            AsyncInspectorTextEditor(
                renderID: "\(frame.id.uuidString)-payload-text-\(payload.count)-\(formatsJSON)"
            ) {
                if let text = String(data: payload, encoding: .utf8) {
                    return .text(formatsJSON ? WebSocketFrameSearch.prettyJSON(text) ?? text : text)
                }
                return .unavailable(
                    title: String(localized: "Binary Payload", bundle: RockxyLocalization.bundle),
                    systemImage: "doc",
                    description: SizeFormatter.format(bytes: payload.count)
                )
            }
            .frame(maxHeight: 200)
        } else {
            AsyncHexDumpView(
                data: frame.payload,
                renderID: "\(frame.id.uuidString)-payload-hex-\(frame.payload.count)"
            )
            .frame(maxHeight: 200)
        }
    }

    @ViewBuilder
    private func protobufPayloadView(_ frame: WebSocketFrameData) -> some View {
        if let tree = frame.protobufHeuristicTree(), !tree.fields.isEmpty {
            ProtobufTreeView(tree: tree)
                .frame(maxHeight: 220)
        } else {
            InspectorEmptyStateView(
                String(localized: "No Protobuf Fields", bundle: RockxyLocalization.bundle),
                systemImage: "curlybraces",
                description: String(
                    localized: "This frame does not look like a valid Protobuf wire-format payload.",
                    bundle: RockxyLocalization.bundle
                )
            )
            .frame(maxHeight: 160)
        }
    }

    private func totalSize(_ frames: [WebSocketFrameData]) -> String {
        SizeFormatter.format(bytes: frames.reduce(0) { $0 + $1.payload.count })
    }

    /// "1,204 (2.3 MB)" — the frame count beside its own payload total. Both halves go through a
    /// shared formatter so the pair reads in one locale; the parentheses carry no wording to
    /// translate, so this stays a plain composition.
    private func frameCountSummary(_ frames: [WebSocketFrameData]) -> String {
        "\(CountFormatter.format(frames.count)) (\(totalSize(frames)))"
    }

    private func filteredFrames(_ connection: WebSocketConnection) -> [WebSocketFrameData] {
        let query = frameSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return connection.frames.filter { frame in
            if let filter = directionFilterValue, frame.direction != filter {
                return false
            }
            return query.isEmpty || WebSocketFrameSearch.matches(frame.payload, query: query)
        }
    }

    private func opcodeInfo(_ opcode: FrameOpcode) -> (String, Color) {
        switch opcode {
        case .text: ("text", .primary)
        case .binary: ("bin", .purple)
        case .ping: ("ping", .gray)
        case .pong: ("pong", .gray)
        case .connectionClose: ("close", .red)
        case .continuation: ("cont", .orange)
        }
    }

    /// Stands in for a frame whose bytes cannot be shown as text. It sits in the same row as the
    /// frame's own size column, so it has to be the shared formatter's spelling — building the
    /// count by hand printed "(1048576 bytes)" beside that column's "1 MB".
    private static func sizePlaceholder(for frame: WebSocketFrameData) -> String {
        "(\(SizeFormatter.format(bytes: frame.payload.count)))"
    }

    private func payloadPreview(_ frame: WebSocketFrameData) -> String {
        switch frame.opcode {
        case .text:
            let previewBytes = frame.payload.prefix(Self.maxPayloadPreviewBytes)
            guard let text = String(data: previewBytes, encoding: .utf8) else {
                return Self.sizePlaceholder(for: frame)
            }
            if text.count > 80 {
                return String(text.prefix(80))
            }
            return text
        case .binary:
            return Self.sizePlaceholder(for: frame)
        case .connectionClose:
            if frame.payload.count >= 2 {
                let code = UInt16(frame.payload[0]) << 8 | UInt16(frame.payload[1])
                let reason = frame.payload.count > 2
                    ? String(data: frame.payload.dropFirst(2).prefix(
                        Self.maxPayloadPreviewBytes
                    ), encoding: .utf8) ?? ""
                    : ""
                return "\(code) \(reason)".trimmingCharacters(in: .whitespaces)
            }
            return ""
        case .ping,
             .pong,
             .continuation:
            return ""
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        TimestampFormatter.timeOfDayWithMilliseconds(date)
    }
}

// MARK: - WebSocketPayloadInspectorMode

private enum WebSocketPayloadInspectorMode {
    case payload
    case protobuf
}

private extension Data {
    var isProbablyUTF8Text: Bool {
        String(data: prefix(512), encoding: .utf8) != nil
    }
}

// MARK: - WebSocketFrameSearch

/// Text search and JSON formatting for WebSocket frame payloads. Only the first
/// `maxScannedBytes` of a payload are searched so very large frames stay cheap.
enum WebSocketFrameSearch {
    static let maxScannedBytes = 65_536

    static func matches(_ payload: Data, query: String) -> Bool {
        guard !query.isEmpty else {
            return true
        }
        guard let text = String(data: payload.prefix(maxScannedBytes), encoding: .utf8) else {
            return false
        }
        return text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// Pretty-printed JSON for an object or array payload, or `nil` when the text is not JSON.
    static func prettyJSON(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ) else
        {
            return nil
        }
        return String(data: pretty, encoding: .utf8)
    }
}
