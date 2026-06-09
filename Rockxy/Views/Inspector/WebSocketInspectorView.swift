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
                VStack(spacing: 0) {
                    connectionSummary(connection)
                    Divider()
                    directionFilter(connection)
                    Divider()
                    frameList(connection)
                    if selectedFrame != nil {
                        Divider()
                        frameDetail
                    }
                }
            } else {
                InspectorEmptyStateView(
                    String(localized: "No WebSocket Data"),
                    systemImage: "arrow.left.arrow.right",
                    description: String(localized: "This request does not contain WebSocket frames.")
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

    @State private var selectedFrameID: UUID?
    @State private var directionFilterValue: FrameDirection?
    @State private var showDetail = true
    @State private var payloadMode: WebSocketPayloadInspectorMode = .payload

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
                        .font(.caption2)
                    Text(String(localized: "Frame Detail"))
                        .font(.caption)
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
                        Text(String(localized: "Direction:"))
                            .foregroundStyle(.secondary)
                        Image(systemName: frame.direction == .sent ? "arrow.up.circle" : "arrow.down.circle")
                            .foregroundStyle(frame.direction == .sent ? .blue : .green)
                        Text(frame.direction == .sent
                            ? String(localized: "Sent")
                            : String(localized: "Received"))
                    }
                    HStack(spacing: 2) {
                        Text(String(localized: "Type:")).foregroundStyle(.secondary)
                        Text(opcodeInfo(frame.opcode).0)
                    }
                    HStack(spacing: 2) {
                        Text(String(localized: "Size:")).foregroundStyle(.secondary)
                        Text(SizeFormatter.format(bytes: frame.payload.count))
                    }
                }
                .font(.system(size: 10))
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

                Divider()

                framePayloadView(frame)
            } else if showDetail {
                InspectorEmptyStateView(
                    String(localized: "No Frame Selected"),
                    systemImage: "arrow.left.arrow.right",
                    description: String(localized: "Select a frame to inspect its payload.")
                )
                .frame(maxHeight: 120)
            }
        }
    }

    // MARK: - Connection Summary

    private func connectionSummary(_ connection: WebSocketConnection) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            summaryRow(String(localized: "URL"), value: connection.upgradeRequest.url.absoluteString)
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    summaryLabel(String(localized: "State"))
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(transaction.state == .completed ? .red : .green)
                    Text(transaction.state == .completed
                        ? String(localized: "Closed")
                        : String(localized: "Active"))
                        .font(.system(size: 11, design: .monospaced))
                }
                if let duration = connectionDuration(connection) {
                    summaryRow(String(localized: "Duration"), value: duration)
                }
            }
            HStack(spacing: 16) {
                summaryRow(
                    String(localized: "Sent"),
                    value: "\(connection.sentFrames.count) (\(totalSize(connection.sentFrames)))"
                )
                summaryRow(
                    String(localized: "Received"),
                    value: "\(connection.receivedFrames.count) (\(totalSize(connection.receivedFrames)))"
                )
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
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func summaryLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }

    // MARK: - Direction Filter

    private func directionFilter(_ connection: WebSocketConnection) -> some View {
        Picker(selection: $directionFilterValue) {
            Text(String(localized: "All (\(connection.frameCount))")).tag(FrameDirection?.none)
            Text("↑ \(String(localized: "Sent")) (\(connection.sentFrames.count))").tag(Optional(FrameDirection.sent))
            Text("↓ \(String(localized: "Received")) (\(connection.receivedFrames.count))")
                .tag(Optional(FrameDirection.received))
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    // MARK: - Frame List

    private func frameList(_ connection: WebSocketConnection) -> some View {
        let frames = filteredFrames(connection)
        return Group {
            if frames.isEmpty {
                InspectorEmptyStateView(
                    String(localized: "Waiting for Frames"),
                    systemImage: "arrow.left.arrow.right",
                    description: String(
                        localized: "WebSocket connection established. Frames will appear here as they arrive."
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
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)

            Image(systemName: frame.direction == .sent ? "arrow.up.circle" : "arrow.down.circle")
                .font(.system(size: 11))
                .foregroundStyle(frame.direction == .sent ? .blue : .green)
                .frame(width: 16)

            opcodeBadge(frame.opcode)
                .frame(width: 42, alignment: .leading)

            Text(payloadPreview(frame))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Text(SizeFormatter.format(bytes: frame.payload.count))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 1)
    }

    private func opcodeBadge(_ opcode: FrameOpcode) -> some View {
        let (label, color) = opcodeInfo(opcode)
        return Text(label)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    @ViewBuilder
    private func framePayloadView(_ frame: WebSocketFrameData) -> some View {
        if frame.payload.isEmpty {
            Text(String(localized: "(empty payload)"))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(12)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Picker(String(localized: "Payload View"), selection: $payloadMode) {
                        Text(String(localized: "Payload")).tag(WebSocketPayloadInspectorMode.payload)
                        Text(String(localized: "Protobuf")).tag(WebSocketPayloadInspectorMode.protobuf)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 190)

                    if ProtobufDetector.isLikelyProtobuf(frame.payload) {
                        Label(String(localized: "Likely Protobuf"), systemImage: "sparkles")
                            .font(.system(size: 10))
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
            AsyncInspectorTextEditor(
                renderID: "\(frame.id.uuidString)-payload-text-\(payload.count)"
            ) {
                if let text = String(data: payload, encoding: .utf8) {
                    return .text(text)
                }
                return .unavailable(
                    title: String(localized: "Binary Payload"),
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
                String(localized: "No Protobuf Fields"),
                systemImage: "curlybraces",
                description: String(localized: "This frame does not look like a valid Protobuf wire-format payload.")
            )
            .frame(maxHeight: 160)
        }
    }

    private func totalSize(_ frames: [WebSocketFrameData]) -> String {
        SizeFormatter.format(bytes: frames.reduce(0) { $0 + $1.payload.count })
    }

    private func connectionDuration(_ connection: WebSocketConnection) -> String? {
        let frames = connection.frames
        guard let first = frames.first else {
            return nil
        }
        let end = frames.last?.timestamp ?? Date()
        let interval = end.timeIntervalSince(first.timestamp)
        if interval < 60 {
            return String(format: "%.0fs", interval)
        } else if interval < 3_600 {
            return String(format: "%.0fm %.0fs", interval / 60, interval.truncatingRemainder(dividingBy: 60))
        } else {
            return String(format: "%.0fh %.0fm", interval / 3_600, (interval / 60).truncatingRemainder(dividingBy: 60))
        }
    }

    private func filteredFrames(_ connection: WebSocketConnection) -> [WebSocketFrameData] {
        guard let filter = directionFilterValue else {
            return connection.frames
        }
        return connection.frames.filter { $0.direction == filter }
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

    private func payloadPreview(_ frame: WebSocketFrameData) -> String {
        switch frame.opcode {
        case .text:
            let previewBytes = frame.payload.prefix(Self.maxPayloadPreviewBytes)
            guard let text = String(data: previewBytes, encoding: .utf8) else {
                return "(\(frame.payload.count) bytes)"
            }
            if text.count > 80 {
                return String(text.prefix(80))
            }
            return text
        case .binary:
            return "(\(frame.payload.count) bytes)"
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
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
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
