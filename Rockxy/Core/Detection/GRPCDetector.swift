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

        let statusFields = statusHeaders(of: response)
        let hasGRPCTrailers = headerValue(named: "grpc-status", in: statusFields) != nil
            || headerValue(named: "grpc-message", in: statusFields) != nil
        return hasGRPCTrailers && looksLikeGRPCMethodPath(request.path)
    }

    /// gRPC status travels in trailers over HTTP/2 and in headers for trailers-only responses.
    static func statusHeaders(of response: HTTPResponseData?) -> [HTTPHeader] {
        (response?.trailers ?? []) + (response?.headers ?? [])
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
        let requestFrames = parseFrames(
            decodedBody(request.body, contentType: headerValue(named: "content-type", in: request.headers)),
            direction: .request
        )
        let responseFrames = parseFrames(
            decodedBody(response?.body, contentType: headerValue(named: "content-type", in: response?.headers ?? [])),
            direction: .response
        )
        // gRPC-Web carries status in a trailer frame inside the body instead of HTTP trailers.
        let statusFields = statusHeaders(of: response) + responseFrames.flatMap(\.trailers)
        var inspection = GRPCInspection(
            serviceName: method?.service,
            methodName: method?.method,
            fullMethodPath: method?.fullPath ?? request.path,
            requestContentType: headerValue(named: "content-type", in: request.headers),
            responseContentType: headerValue(named: "content-type", in: response?.headers ?? []),
            requestEncoding: headerValue(named: "grpc-encoding", in: request.headers),
            responseEncoding: headerValue(named: "grpc-encoding", in: response?.headers ?? []),
            httpStatusCode: response?.statusCode,
            httpStatusMessage: response?.statusMessage,
            grpcStatus: headerValue(named: "grpc-status", in: statusFields),
            grpcMessage: headerValue(named: "grpc-message", in: statusFields),
            grpcStatusDetails: headerValue(named: "grpc-status-details-bin", in: statusFields),
            duration: timingInfo?.totalDuration ?? measuredDuration,
            requestFrames: requestFrames,
            responseFrames: responseFrames
        )
        inspection.timeout = headerValue(named: "grpc-timeout", in: request.headers)
        inspection.requestMetadata = customMetadata(request.headers)
        inspection.responseMetadata = customMetadata(statusFields)
        return inspection
    }

    /// Metadata a person added, with transport, HTTP/2 pseudo, and gRPC protocol fields removed.
    static func customMetadata(_ headers: [HTTPHeader]) -> [HTTPHeader] {
        var seen = Set<String>()
        return headers.filter { header in
            let name = header.name.lowercased()
            guard !name.hasPrefix(":"),
                  !protocolHeaderNames.contains(name),
                  !ignoredHeaderPrefixes.contains(where: { name.hasPrefix($0) }) else
            {
                return false
            }
            return seen.insert("\(name)\u{0}\(header.value)").inserted
        }
    }

    /// gRPC-Web text mode base64-encodes the framed body. Servers may send several padded chunks
    /// back to back, so each chunk is decoded on its own.
    static func decodedBody(_ body: Data?, contentType: String?) -> Data? {
        guard let body, let contentType,
              contentType.lowercased().hasPrefix("application/grpc-web-text") else
        {
            return body
        }
        guard let text = String(data: body, encoding: .ascii) else {
            return body
        }
        let compact = Array(text.filter { !$0.isWhitespace })
        // Anything outside the base64 alphabet means this is not text-mode framing after all.
        guard compact.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+/=".contains($0)) }) else {
            return body
        }
        var decoded = Data()
        var start = 0
        var index = 0
        while index < compact.count {
            // A chunk closes after its last padding character, or at the end of the body.
            let closesChunk = compact[index] == "=" && (index + 1 == compact.count || compact[index + 1] != "=")
            if closesChunk || index + 1 == compact.count {
                var chunk = String(compact[start ... index])
                if !closesChunk, chunk.count % 4 != 0 {
                    // A capture that ended mid-chunk: keep the complete quanta, drop the tail.
                    chunk = String(chunk.prefix(chunk.count - chunk.count % 4))
                }
                guard let piece = Data(base64Encoded: chunk) else {
                    return decoded.isEmpty ? body : decoded
                }
                decoded.append(piece)
                start = index + 1
            }
            index += 1
        }
        return decoded
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

            let isTrailerFrame = compressedFlag & 0x80 != 0
            let status: GRPCFrameParseStatus
            if isTrailerFrame, availablePayloadBytes >= declaredLength {
                status = .trailers
            } else if !isTrailerFrame, compressedFlag != 0, compressedFlag != 1 {
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
                heuristicTree: tree,
                trailers: status == .trailers ? parseTrailerBlock(payload) : []
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

    private static let protocolHeaderNames: Set<String> = [
        "content-type", "content-length", "te", "user-agent", "host", "accept", "accept-encoding",
        "content-encoding", "transfer-encoding", "connection", "date", "server", "vary",
        "grpc-encoding", "grpc-accept-encoding", "grpc-timeout", "grpc-status", "grpc-message",
        "grpc-status-details-bin", "x-grpc-web", "x-user-agent", "access-control-allow-origin",
        "access-control-expose-headers", "access-control-allow-credentials",
        // Browser, caching, and edge headers that a gRPC-Web call from a page carries.
        "origin", "referer", "cookie", "set-cookie", "accept-language", "pragma", "cache-control",
        "priority", "dnt", "alt-svc", "strict-transport-security", "expires", "etag", "age", "via",
        "keep-alive", "upgrade-insecure-requests", "authority",
    ]

    private static let ignoredHeaderPrefixes = ["sec-", "access-control-", "x-envoy-", "cf-", "x-amz-cf-"]

    /// A gRPC-Web trailer frame holds an HTTP/1-style header block: `name: value` lines.
    private static func parseTrailerBlock(_ payload: Data) -> [HTTPHeader] {
        guard let text = String(data: payload, encoding: .utf8) else {
            return []
        }
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let colon = line.firstIndex(of: ":") else {
                return nil
            }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : HTTPHeader(name: name, value: value)
        }
    }

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
            || mediaType == "application/grpc-web-text"
            || mediaType.hasPrefix("application/grpc-web-text+")
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
        // Length check first: this runs for every request-list row on every batch, and most
        // header names are the wrong length before a case-insensitive compare is needed.
        let length = name.utf8.count
        return headers.first { $0.name.utf8.count == length && $0.name.caseInsensitiveCompare(name) == .orderedSame }?
            .value
    }
}
