import Foundation

// Parses captured multipart/form-data bodies into their parts for inspection.

// MARK: - MultipartPart

/// One part of a multipart body, as sent on the wire.
struct MultipartPart: Identifiable, Equatable, Sendable {
    let id: Int
    let headers: [HTTPHeader]
    let name: String?
    let fileName: String?
    let contentType: String?
    let data: Data

    var isFile: Bool {
        fileName != nil
    }

    /// Part content as text when it is valid UTF-8 and not declared as a binary file.
    var textValue: String? {
        if let contentType, !MultipartFormDataParser.isTextual(contentType: contentType) {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - MultipartFormDataParser

/// Splits a multipart body on its boundary. Parsing is bounded (part count and
/// header size) and tolerant: a malformed tail is dropped, never guessed at, so
/// the inspector shows only what the client actually sent.
enum MultipartFormDataParser {
    static let maxParts = 512
    static let maxPartHeaderBytes = 16_384

    /// Extracts the `boundary` parameter from a `Content-Type` header value.
    static func boundary(fromContentType value: String) -> String? {
        let segments = value.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let mediaType = segments.first?.lowercased(), mediaType.hasPrefix("multipart/") else {
            return nil
        }
        for segment in segments.dropFirst() {
            let pair = segment.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2, pair[0].trimmingCharacters(in: .whitespaces).lowercased() == "boundary" else {
                continue
            }
            var boundary = pair[1].trimmingCharacters(in: .whitespaces)
            if boundary.count >= 2, boundary.hasPrefix("\""), boundary.hasSuffix("\"") {
                boundary = String(boundary.dropFirst().dropLast())
            }
            return boundary.isEmpty || boundary.count > 200 ? nil : boundary
        }
        return nil
    }

    /// Parses `body` using the boundary from the request's `Content-Type` header.
    /// Returns `nil` when the headers do not describe a multipart body.
    static func parse(body: Data, headers: [HTTPHeader]) -> [MultipartPart]? {
        guard let contentType = headers.first(where: {
            $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame
        })?.value,
            let boundary = boundary(fromContentType: contentType) else
        {
            return nil
        }
        return parse(body: body, boundary: boundary)
    }

    static func parse(body: Data, boundary: String) -> [MultipartPart] {
        let delimiter = Data("--\(boundary)".utf8)
        let bytes = [UInt8](body)
        var starts: [Int] = []
        var searchFrom = 0
        while let range = firstRange(of: [UInt8](delimiter), in: bytes, from: searchFrom) {
            starts.append(range.lowerBound)
            searchFrom = range.upperBound
            if starts.count > maxParts {
                break
            }
        }

        var parts: [MultipartPart] = []
        for (index, start) in starts.enumerated() where index + 1 < starts.count {
            var partStart = start + delimiter.count
            // The closing delimiter is `--boundary--`; nothing after it is a part.
            if partStart + 1 < bytes.count, bytes[partStart] == 0x2D, bytes[partStart + 1] == 0x2D {
                break
            }
            partStart = skipLineBreak(in: bytes, at: partStart)
            var partEnd = starts[index + 1]
            // The line break before the next delimiter belongs to the delimiter.
            if partEnd >= 2, bytes[partEnd - 2] == 0x0D, bytes[partEnd - 1] == 0x0A {
                partEnd -= 2
            } else if partEnd >= 1, bytes[partEnd - 1] == 0x0A {
                partEnd -= 1
            }
            guard partStart <= partEnd,
                  let part = makePart(id: parts.count, bytes: bytes[partStart ..< partEnd]) else
            {
                continue
            }
            parts.append(part)
        }
        return parts
    }

    static func isTextual(contentType: String) -> Bool {
        let type = contentType.lowercased()
        return type.hasPrefix("text/")
            || type.contains("json")
            || type.contains("xml")
            || type.contains("x-www-form-urlencoded")
            || type.contains("javascript")
    }

    // MARK: Private

    private static func makePart(id: Int, bytes: ArraySlice<UInt8>) -> MultipartPart? {
        let slice = Array(bytes)
        let separator: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A]
        let headerEnd: Int
        let bodyStart: Int
        if let range = firstRange(of: separator, in: slice, from: 0) {
            headerEnd = range.lowerBound
            bodyStart = range.upperBound
        } else if let range = firstRange(of: [0x0A, 0x0A], in: slice, from: 0) {
            headerEnd = range.lowerBound
            bodyStart = range.upperBound
        } else {
            return nil
        }
        guard headerEnd <= maxPartHeaderBytes,
              let headerText = String(bytes: slice[0 ..< headerEnd], encoding: .utf8) else
        {
            return nil
        }
        let headers = headerText
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> HTTPHeader? in
                let pair = line.split(separator: ":", maxSplits: 1)
                guard pair.count == 2 else {
                    return nil
                }
                return HTTPHeader(
                    name: pair[0].trimmingCharacters(in: .whitespaces),
                    value: pair[1].trimmingCharacters(in: .whitespaces)
                )
            }
        let disposition = headers.first {
            $0.name.caseInsensitiveCompare("Content-Disposition") == .orderedSame
        }?.value
        return MultipartPart(
            id: id,
            headers: headers,
            name: disposition.flatMap { parameter("name", in: $0) },
            fileName: disposition.flatMap { parameter("filename", in: $0) },
            contentType: headers.first { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value,
            data: Data(slice[bodyStart...])
        )
    }

    /// Reads `name="value"` (or an unquoted value) from a Content-Disposition header.
    private static func parameter(_ key: String, in disposition: String) -> String? {
        for segment in disposition.split(separator: ";").dropFirst() {
            let pair = segment.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard pair.count == 2, pair[0].lowercased() == key else {
                continue
            }
            var value = pair[1]
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            return value
        }
        return nil
    }

    private static func skipLineBreak(in bytes: [UInt8], at index: Int) -> Int {
        if index + 1 < bytes.count, bytes[index] == 0x0D, bytes[index + 1] == 0x0A {
            return index + 2
        }
        if index < bytes.count, bytes[index] == 0x0A {
            return index + 1
        }
        return index
    }

    private static func firstRange(of needle: [UInt8], in haystack: [UInt8], from start: Int) -> Range<Int>? {
        guard !needle.isEmpty, haystack.count >= needle.count, start <= haystack.count - needle.count else {
            return nil
        }
        let first = needle[0]
        var index = start
        let last = haystack.count - needle.count
        while index <= last {
            if haystack[index] == first, haystack[index ..< index + needle.count].elementsEqual(needle) {
                return index ..< index + needle.count
            }
            index += 1
        }
        return nil
    }
}
