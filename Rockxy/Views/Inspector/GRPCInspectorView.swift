import SwiftUI

// MARK: - GRPCInspectorView

/// gRPC-specific response inspector tab. It keeps the main inspector layout intact while
/// surfacing method metadata, frame boundaries, trailers, and honest Protobuf fallback state.
struct GRPCInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction
    var onOpenToolWindow: (String) -> Void = { _ in }

    var body: some View {
        Group {
            switch inspectionState {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unsupported:
                InspectorEmptyStateView(
                    String(localized: "No gRPC Metadata", bundle: RockxyLocalization.bundle),
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: String(
                        localized: "Open this tab when a request uses application/grpc metadata or length-prefixed gRPC messages.",
                        bundle: RockxyLocalization.bundle
                    )
                )
            case let .loaded(inspection):
                inspectorContent(inspection)
            }
        }
        .task(id: transaction.inspectionKey) {
            await loadInspection()
        }
    }

    // MARK: Private

    @State private var inspectionState: GRPCInspectionState = .loading
    @State private var selectedFrameID: String?
    @Environment(\.appUIDisplayMetrics) private var metrics

    private var frameHeaderRow: some View {
        HStack(spacing: 0) {
            headerCell("#", width: 44)
            headerCell(String(localized: "Dir", bundle: RockxyLocalization.bundle), width: 86)
            headerCell(String(localized: "Compressed", bundle: RockxyLocalization.bundle), width: 102)
            headerCell(String(localized: "Bytes", bundle: RockxyLocalization.bundle), width: 72)
            headerCell(String(localized: "Decode", bundle: RockxyLocalization.bundle), width: nil)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func inspectorContent(_ inspection: GRPCInspection) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                callSummary(inspection)
                messageFrames(inspection)
                frameDetail(inspection)
                metadataAndTrailers(inspection)
                descriptorCallout(inspection)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func callSummary(_ inspection: GRPCInspection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                badge(String(localized: "gRPC", bundle: RockxyLocalization.bundle), color: .blue)
                badge(
                    inspection.requestContentType ?? inspection.responseContentType ?? "application/grpc",
                    color: .secondary
                )
                if schemaMethod(for: inspection) != nil {
                    badge(String(localized: "Schema decoded", bundle: RockxyLocalization.bundle), color: .green)
                } else {
                    badge(
                        String(localized: "Wire-format heuristic", bundle: RockxyLocalization.bundle),
                        color: .orange
                    )
                }
                if let grpcStatus = inspection.grpcStatus {
                    badge(
                        String(localized: "grpc-status: \(grpcStatus)", bundle: RockxyLocalization.bundle),
                        color: grpcStatus == "0" ? .green : .red
                    )
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Service / method", bundle: RockxyLocalization.bundle))
                    .font(.system(size: metrics.metadataFontSize, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(methodTitle(inspection))
                    .font(.system(size: metrics.primaryFontSize, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 8) {
                metric(
                    String(localized: "HTTP", bundle: RockxyLocalization.bundle),
                    value: httpStatusText(inspection),
                    color: .green
                )
                metric(
                    String(localized: "Duration", bundle: RockxyLocalization.bundle),
                    value: durationText(inspection),
                    color: .primary
                )
                metric(
                    String(localized: "Messages", bundle: RockxyLocalization.bundle),
                    value: CountFormatter.format(inspection.frames.count),
                    color: .primary
                )
                metric(
                    String(localized: "Payload", bundle: RockxyLocalization.bundle),
                    value: SizeFormatter.format(bytes: totalPayloadBytes(inspection)),
                    color: .primary
                )
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }

    private func messageFrames(_ inspection: GRPCInspection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(String(localized: "Message Frames", bundle: RockxyLocalization.bundle))
                    .font(.system(size: metrics.primaryFontSize, weight: .semibold))
                badge(
                    String(localized: "5-byte gRPC prefix visible", bundle: RockxyLocalization.bundle),
                    color: .secondary
                )
                Spacer(minLength: 0)
            }

            if inspection.frames.isEmpty {
                InspectorEmptyStateView(
                    String(localized: "No Message Frames", bundle: RockxyLocalization.bundle),
                    systemImage: "shippingbox",
                    description: String(
                        localized: "Headers identify gRPC, but no length-prefixed messages were captured.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                .frame(minHeight: 120)
            } else {
                VStack(spacing: 0) {
                    frameHeaderRow
                    Divider()
                    ForEach(inspection.frames) { frame in
                        frameRow(frame)
                        if frame.id != inspection.frames.last?.id {
                            Divider()
                        }
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                }
            }
        }
    }

    private func frameRow(_ frame: GRPCMessageFrame) -> some View {
        Button {
            selectedFrameID = frame.id
        } label: {
            HStack(spacing: 0) {
                frameCell("\(frame.index)", width: 44)
                frameCell(frame.direction.displayName, width: 86, color: frame.direction == .request ? .blue : .green)
                frameCell(
                    frame.isCompressed ? String(localized: "Yes", bundle: RockxyLocalization.bundle) : String(
                        localized: "No",
                        bundle: RockxyLocalization.bundle
                    ),
                    width: 102
                )
                frameCell(SizeFormatter.format(bytes: frame.payload.count), width: 72)
                frameCell(decodeStateText(frame), width: nil, color: decodeStateColor(frame))
            }
            .contentShape(Rectangle())
            .background(selectedFrameID == frame.id ? Color.accentColor.opacity(0.12) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func frameDetail(_ inspection: GRPCInspection) -> some View {
        let frame = selectedFrame(in: inspection)
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Decoded Payload", bundle: RockxyLocalization.bundle))
                .font(.system(size: metrics.primaryFontSize, weight: .semibold))

            if let frame {
                HStack(spacing: 6) {
                    badge(frame.direction.displayName, color: frame.direction == .request ? .blue : .green)
                    badge(
                        String(localized: "Frame #\(frame.index)", bundle: RockxyLocalization.bundle),
                        color: .secondary
                    )
                    badge(frameStatusText(frame), color: frameStatusColor(frame))
                    Spacer(minLength: 0)
                }

                if let payload = decodablePayload(frame, in: inspection) {
                    ProtobufPayloadInspectorView(
                        payload: payload,
                        context: ProtobufPayloadContext(
                            url: transaction.request.url,
                            method: transaction.request.method,
                            direction: frame.direction == .request ? .request : .response
                        ),
                        payloadID: "\(transaction.id.uuidString)-\(frame.id)"
                    )
                    .frame(minHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    }
                } else {
                    InspectorEmptyStateView(
                        String(localized: "Compressed Message", bundle: RockxyLocalization.bundle),
                        systemImage: "archivebox",
                        description: String(
                            localized: "This gRPC message uses a compression Rockxy cannot decode, so its fields cannot be shown.",
                            bundle: RockxyLocalization.bundle
                        )
                    )
                    .frame(minHeight: 160)
                }
            } else {
                InspectorEmptyStateView(
                    String(localized: "No Frame Selected", bundle: RockxyLocalization.bundle),
                    systemImage: "shippingbox",
                    description: String(
                        localized: "Select a gRPC message frame to inspect its payload.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                .frame(minHeight: 160)
            }
        }
    }

    private func metadataAndTrailers(_ inspection: GRPCInspection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Metadata And Trailers", bundle: RockxyLocalization.bundle))
                .font(.system(size: metrics.primaryFontSize, weight: .semibold))

            VStack(spacing: 0) {
                metadataRow(
                    String(localized: "grpc-encoding", bundle: RockxyLocalization.bundle),
                    value: inspection.responseEncoding ?? inspection.requestEncoding ?? "identity"
                )
                metadataRow(
                    String(localized: "grpc-status", bundle: RockxyLocalization.bundle),
                    value: inspection.grpcStatus ?? String(localized: "Not captured", bundle: RockxyLocalization.bundle)
                )
                metadataRow(
                    String(localized: "grpc-message", bundle: RockxyLocalization.bundle),
                    value: inspection.grpcMessage ?? String(
                        localized: "Not captured",
                        bundle: RockxyLocalization.bundle
                    )
                )
                metadataRow(
                    String(localized: "grpc-status-details-bin", bundle: RockxyLocalization.bundle),
                    value: inspection.grpcStatusDetails ?? String(
                        localized: "Not captured",
                        bundle: RockxyLocalization.bundle
                    )
                )
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
        }
    }

    private func descriptorCallout(_ inspection: GRPCInspection) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.badge.gearshape")
                .foregroundStyle(.orange)
            Text(descriptorCopy(inspection))
                .font(.system(size: metrics.secondaryFontSize, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(String(localized: "Manage Schemas…", bundle: RockxyLocalization.bundle)) {
                onOpenToolWindow("protobufSchemaList")
            }
            .controlSize(.small)
            Button(String(localized: "Protobuf Mapping…", bundle: RockxyLocalization.bundle)) {
                onOpenToolWindow("protobufSettings")
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.35), lineWidth: 0.5)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: metrics.badgeFontSize, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }

    private func metric(_ label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: metrics.badgeFontSize, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: metrics.secondaryFontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }

    private func headerCell(_ text: String, width: CGFloat?) -> some View {
        Text(text)
            .font(.system(size: metrics.metadataFontSize, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
    }

    private func frameCell(_ text: String, width: CGFloat?, color: Color = .secondary) -> some View {
        Text(text)
            .font(.system(size: metrics.metadataFontSize, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: metrics.metadataFontSize, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 180, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            Divider()
            Text(value)
                .font(.system(size: metrics.metadataFontSize, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
    }

    private func loadInspection() async {
        inspectionState = .loading
        let request = transaction.request
        let response = transaction.response
        let timingInfo = transaction.timingInfo
        let measuredDuration = transaction.measuredDuration
        let inspection = await Task.detached {
            GRPCDetector.detect(
                request: request,
                response: response,
                timingInfo: timingInfo,
                measuredDuration: measuredDuration
            )
        }.value

        guard !Task.isCancelled else {
            return
        }

        if let inspection {
            inspectionState = .loaded(inspection)
            if !inspection.frames.contains(where: { $0.id == selectedFrameID }) {
                selectedFrameID = inspection.frames.first?.id
            }
        } else {
            inspectionState = .unsupported
            selectedFrameID = nil
        }
    }

    private func selectedFrame(in inspection: GRPCInspection) -> GRPCMessageFrame? {
        guard let selectedFrameID else {
            return inspection.frames.first
        }
        return inspection.frames.first { $0.id == selectedFrameID } ?? inspection.frames.first
    }

    private func methodTitle(_ inspection: GRPCInspection) -> String {
        if let serviceName = inspection.serviceName, let methodName = inspection.methodName {
            return "\(serviceName) / \(methodName)"
        }
        return inspection.fullMethodPath ?? String(localized: "Unknown gRPC method", bundle: RockxyLocalization.bundle)
    }

    private func httpStatusText(_ inspection: GRPCInspection) -> String {
        guard let code = inspection.httpStatusCode else {
            return String(localized: "No response", bundle: RockxyLocalization.bundle)
        }
        return "\(code)"
    }

    private func durationText(_ inspection: GRPCInspection) -> String {
        guard let duration = inspection.duration else {
            return String(localized: "Unknown", bundle: RockxyLocalization.bundle)
        }
        return DurationFormatter.format(seconds: duration)
    }

    private func totalPayloadBytes(_ inspection: GRPCInspection) -> Int {
        inspection.frames.reduce(0) { $0 + $1.payload.count }
    }

    private func decodeStateText(_ frame: GRPCMessageFrame) -> String {
        guard frame.status == .complete else {
            return frameStatusText(frame)
        }
        if frame.isCompressed {
            return String(localized: "Compressed", bundle: RockxyLocalization.bundle)
        }
        if ProtobufSchemaStore.shared.combinedSchema().method(forGRPCPath: transaction.request.url.path) != nil {
            return String(localized: "Schema", bundle: RockxyLocalization.bundle)
        }
        if frame.heuristicTree != nil {
            return String(localized: "Heuristic tree", bundle: RockxyLocalization.bundle)
        }
        return frameStatusText(frame)
    }

    private func decodeStateColor(_ frame: GRPCMessageFrame) -> Color {
        if frame.heuristicTree != nil {
            return .blue
        }
        return frameStatusColor(frame)
    }

    private func frameStatusText(_ frame: GRPCMessageFrame) -> String {
        switch frame.status {
        case .complete:
            String(localized: "Raw bytes", bundle: RockxyLocalization.bundle)
        case let .incompleteHeader(remainingBytes):
            String(AttributedString(
                localized: "Incomplete header · ^[\(remainingBytes) byte](inflect: true)",
                bundle: RockxyLocalization.bundle,
                locale: RockxyLocalization.locale
            ).characters)
        case let .truncatedPayload(expectedBytes, actualBytes):
            // Deliberately raw counts rather than `SizeFormatter`: this is a ratio the reader
            // compares against itself, and adaptive units would print "1 KB/2 KB" for a frame that
            // is missing half its payload. Allowlisted in `SizeFormatterTests`.
            String(localized: "Truncated · \(actualBytes)/\(expectedBytes) bytes", bundle: RockxyLocalization.bundle)
        case let .unsupportedCompressionFlag(flag):
            String(localized: "Unknown compression flag \(Int(flag))", bundle: RockxyLocalization.bundle)
        }
    }

    private func frameStatusColor(_ frame: GRPCMessageFrame) -> Color {
        switch frame.status {
        case .complete:
            frame.isCompressed ? .orange : .secondary
        case .incompleteHeader,
             .truncatedPayload,
             .unsupportedCompressionFlag:
            .orange
        }
    }

    private func descriptorCopy(_ inspection: GRPCInspection) -> String {
        if let method = schemaMethod(for: inspection) {
            return String(
                localized: "Messages decode as \(method.inputType) and \(method.outputType) from your imported schemas.",
                bundle: RockxyLocalization.bundle
            )
        }
        return String(
            localized: """
            Import this service's .proto or .desc file in Local Protobuf Schemas to see field names. \
            Until then, field numbers and values are inferred from the wire format.
            """,
            bundle: RockxyLocalization.bundle
        )
    }

    private func schemaMethod(for inspection: GRPCInspection) -> ProtobufMethodSchema? {
        guard let path = inspection.fullMethodPath else {
            return nil
        }
        return ProtobufSchemaStore.shared.combinedSchema().method(forGRPCPath: path)
    }

    /// The message bytes to decode: uncompressed frames as-is, gzip/deflate frames inflated.
    private func decodablePayload(_ frame: GRPCMessageFrame, in inspection: GRPCInspection) -> Data? {
        guard frame.isCompressed else {
            return frame.payload
        }
        let encoding = frame.direction == .request ? inspection.requestEncoding : inspection.responseEncoding
        guard let encoding, encoding.lowercased() != "identity" else {
            return nil
        }
        let result = BodyDecoder.decodeReportingChange(frame.payload, encoding: encoding)
        return result.didDecode ? result.data : nil
    }
}

// MARK: - GRPCInspectionState

private enum GRPCInspectionState {
    case loading
    case unsupported
    case loaded(GRPCInspection)
}

private extension GRPCMessageDirection {
    var displayName: String {
        switch self {
        case .request:
            String(localized: "Request", bundle: RockxyLocalization.bundle)
        case .response:
            String(localized: "Response", bundle: RockxyLocalization.bundle)
        }
    }
}
