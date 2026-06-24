import Foundation

// MARK: - GRPCDetector

nonisolated enum GRPCDetector {
    // MARK: Internal

    static func isGRPC(transaction: HTTPTransaction) -> Bool {
        isGRPC(
            request: transaction.request,
            response: transaction.response
        )
    }

    static func isGRPC(request: HTTPRequestData, response: HTTPResponseData?) -> Bool {
        if isGRPCContentType(headerValue(named: "content-type", in: request.headers))
            || isGRPCContentType(headerValue(named: "content-type", in: response?.headers ?? []))
        {
            return true
        }

        let hasGRPCTrailers = headerValue(named: "grpc-status", in: response?.headers ?? []) != nil
            || headerValue(named: "grpc-message", in: response?.headers ?? []) != nil
        return hasGRPCTrailers && looksLikeGRPCMethodPath(request.path)
    }

    static func detect(
        request: HTTPRequestData,
        response: HTTPResponseData?,
        timingInfo: TimingInfo?,
        measuredDuration: TimeInterval?
    )
        -> GRPCInspection?
    {
        guard isGRPC(request: request, response: response) else {
            return nil
        }

        let method = parseMethodPath(request.path)
        return GRPCInspection(
            serviceName: method?.service,
            methodName: method?.method,
            fullMethodPath: method?.fullPath ?? request.path,
            requestContentType: headerValue(named: "content-type", in: request.headers),
            responseContentType: headerValue(named: "content-type", in: response?.headers ?? []),
            requestEncoding: headerValue(named: "grpc-encoding", in: request.headers),
            responseEncoding: headerValue(named: "grpc-encoding", in: response?.headers ?? []),
            httpStatusCode: response?.statusCode,
            httpStatusMessage: response?.statusMessage,
            grpcStatus: headerValue(named: "grpc-status", in: response?.headers ?? []),
            grpcMessage: headerValue(named: "grpc-message", in: response?.headers ?? []),
            grpcStatusDetails: headerValue(named: "grpc-status-details-bin", in: response?.headers ?? []),
            duration: timingInfo?.totalDuration ?? measuredDuration,
            requestFrames: parseFrames(
                request.body,
                direction: .request
            ),
            responseFrames: parseFrames(
                response?.body,
                direction: .response
            )
        )
    }

    static func parseFrames(_ body: Data?, direction: GRPCMessageDirection) -> [GRPCMessageFrame] {
        guard let body, !body.isEmpty else {
            return []
        }

        var frames: [GRPCMessageFrame] = []
        var offset = body.startIndex
        var frameIndex = 1

        while offset < body.endIndex {
            let remaining = body.distance(from: offset, to: body.endIndex)
            let frameOffset = body.distance(from: body.startIndex, to: offset)
            guard remaining >= 5 else {
                frames.append(GRPCMessageFrame(
                    id: "\(direction.rawValue)-\(frameIndex)",
                    direction: direction,
                    index: frameIndex,
                    offset: frameOffset,
                    compressedFlag: nil,
                    declaredLength: nil,
                    payload: Data(body[offset ..< body.endIndex]),
                    status: .incompleteHeader(remainingBytes: remaining),
                    heuristicTree: nil
                ))
                break
            }

            let compressedFlag = body[offset]
            let lengthStart = body.index(after: offset)
            let lengthEnd = body.index(lengthStart, offsetBy: 4)
            let declaredLength = body[lengthStart ..< lengthEnd].reduce(0) { partial, byte in
                (partial << 8) | Int(byte)
            }
            let payloadStart = lengthEnd
            let availablePayloadBytes = body.distance(from: payloadStart, to: body.endIndex)
            let payloadLength = min(declaredLength, availablePayloadBytes)
            let payloadEnd = body.index(payloadStart, offsetBy: payloadLength)
            let payload = Data(body[payloadStart ..< payloadEnd])

            let status: GRPCFrameParseStatus
            if compressedFlag != 0, compressedFlag != 1 {
                status = .unsupportedCompressionFlag(compressedFlag)
            } else if availablePayloadBytes < declaredLength {
                status = .truncatedPayload(expectedBytes: declaredLength, actualBytes: availablePayloadBytes)
            } else {
                status = .complete
            }

            let tree = compressedFlag == 0 && status == .complete
                ? ProtobufHeuristicDecoder.decode(payload)
                : nil

            frames.append(GRPCMessageFrame(
                id: "\(direction.rawValue)-\(frameIndex)",
                direction: direction,
                index: frameIndex,
                offset: frameOffset,
                compressedFlag: compressedFlag,
                declaredLength: declaredLength,
                payload: payload,
                status: status,
                heuristicTree: tree
            ))

            if availablePayloadBytes < declaredLength {
                break
            }
            offset = payloadEnd
            frameIndex += 1
        }

        return frames
    }

    // MARK: Private

    private static func isGRPCContentType(_ rawValue: String?) -> Bool {
        guard let rawValue else {
            return false
        }
        let mediaType = rawValue
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? rawValue.lowercased()
        return mediaType == "application/grpc"
            || mediaType.hasPrefix("application/grpc+")
            || mediaType == "application/grpc-web"
            || mediaType.hasPrefix("application/grpc-web+")
    }

    private static func parseMethodPath(_ path: String) -> (service: String, method: String, fullPath: String)? {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = trimmed.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            return nil
        }
        return (parts[0], parts[1], "/\(parts[0])/\(parts[1])")
    }

    private static func looksLikeGRPCMethodPath(_ path: String) -> Bool {
        parseMethodPath(path) != nil
    }

    private static func headerValue(named name: String, in headers: [HTTPHeader]) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}
