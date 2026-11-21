import Compression
import Foundation
@testable import Rockxy
import Testing

// Tests for `BodyDecoder`: passthrough for nil/unknown/empty encodings,
// deflate and gzip decompression roundtrips, and graceful fallback on invalid data.

// MARK: - BodyDecoderTests

@Suite(.serialized)
struct BodyDecoderTests {
    // MARK: Internal

    @Test("Nil encoding returns original data")
    func nilEncodingPassthrough() {
        let original = Data("Hello, World!".utf8)
        let result = BodyDecoder.decode(original, encoding: nil)
        #expect(result == original)
    }

    @Test("Change-reporting decode flags only real decompression")
    func decodeReportingChangeFlagsRealDecompression() throws {
        let original = "Reporting whether bytes changed lets callers drop Content-Encoding safely."
        let originalData = try #require(original.data(using: .utf8))
        let compressed = try #require(deflateCompress(originalData))

        let decoded = BodyDecoder.decodeReportingChange(compressed, encoding: "deflate")
        #expect(decoded.didDecode)
        #expect(decoded.data == originalData)

        let untouched = BodyDecoder.decodeReportingChange(originalData, encoding: "unknown-encoding")
        #expect(!untouched.didDecode)
        #expect(untouched.data == originalData)

        let missing = BodyDecoder.decodeReportingChange(originalData, encoding: nil)
        #expect(!missing.didDecode)

        let invalid = BodyDecoder.decodeReportingChange(Data([0x01, 0x02, 0x03]), encoding: "gzip")
        #expect(!invalid.didDecode)
        #expect(invalid.data == Data([0x01, 0x02, 0x03]))

        // A chain with an unknown stage is not fully decoded, even though the known stage applied.
        let partial = BodyDecoder.decodeReportingChange(compressed, encoding: "unknown-encoding, deflate")
        #expect(!partial.didDecode)
        #expect(partial.data == originalData)
    }

    @Test("Unknown encoding returns original data")
    func unknownEncodingPassthrough() {
        let original = Data("Test data".utf8)
        let result = BodyDecoder.decode(original, encoding: "unknown-encoding")
        #expect(result == original)
    }

    @Test("Empty encoding string returns original data")
    func emptyEncodingPassthrough() {
        let original = Data("Identity test".utf8)
        let result = BodyDecoder.decode(original, encoding: "")
        #expect(result == original)
    }

    @Test("Encoding names are normalized before decompression")
    func encodingNameNormalization() throws {
        let original = "Encoding names should ignore case and whitespace."
        let originalData = try #require(original.data(using: .utf8))
        let compressed = try #require(deflateCompress(originalData))

        let decompressed = BodyDecoder.decode(compressed, encoding: " Deflate ")

        #expect(String(data: decompressed, encoding: .utf8) == original)
    }

    @Test("Deflate decompression restores compressed data")
    func deflateDecompression() throws {
        let original = "This is a test string for deflate compression. Repeated words help compression work better. Test test test."
        let originalData = try #require(original.data(using: .utf8))

        let compressed = try #require(deflateCompress(originalData))

        let decompressed = BodyDecoder.decode(compressed, encoding: "deflate")
        let decompressedString = String(data: decompressed, encoding: .utf8)

        #expect(decompressedString == original)
    }

    @Test("Gzip decompression restores compressed data")
    func gzipDecompression() throws {
        let original = "This is gzip test data that should roundtrip correctly through compression."
        let originalData = try #require(original.data(using: .utf8))

        let compressed = try #require(deflateCompress(originalData))
        let gzipData = wrapInGzip(compressed, originalData: originalData)

        let decompressed = BodyDecoder.decode(gzipData, encoding: "gzip")
        let decompressedString = String(data: decompressed, encoding: .utf8)

        #expect(decompressedString == original)
    }

    @Test("Invalid compressed data returns original data as fallback")
    func invalidDataFallback() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05])
        let result = BodyDecoder.decode(garbage, encoding: "deflate")
        #expect(result == garbage)
    }

    @Test("Large incompressible deflate bodies below the output limit decode fully")
    func largeIncompressibleBody() throws {
        var original = Data(count: 13 * 1_024 * 1_024)
        original.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            var state: UInt64 = 0x524F434B58592026
            for index in bytes.indices {
                state = state &* 2_862_933_555_777_941_757 &+ 3_037_000_493
                bytes[index] = UInt8(truncatingIfNeeded: state >> 56)
            }
        }
        let compressed = try #require(deflateCompress(original))
        // This exceeds the old scratch-buffer guard while remaining below the real output limit.
        #expect(compressed.count > 50 * 1_024 * 1_024 / 4)
        let result = BodyDecoder.decodeReportingChange(compressed, encoding: "deflate")
        #expect(result.didDecode)
        #expect(result.data == original)
    }

    @Test(
        "The decompressed output limit is inclusive and overflow preserves compressed bytes",
        arguments: [50 * 1_024 * 1_024, 50 * 1_024 * 1_024 + 1]
    )
    func outputLimitBoundary(byteCount: Int) throws {
        let original = Data(repeating: 0x41, count: byteCount)
        let compressed = try #require(deflateCompress(original))
        let result = BodyDecoder.decodeReportingChange(compressed, encoding: "deflate")
        let withinLimit = byteCount == 50 * 1_024 * 1_024
        #expect(result.didDecode == withinLimit)
        #expect(result.data == (withinLimit ? original : compressed))
        if !withinLimit {
            let unboundedRequest = BodyDecoder.decodeReportingChange(
                compressed,
                encoding: "deflate",
                maxOutputSize: Int.max
            )
            #expect(!unboundedRequest.didDecode)
            #expect(unboundedRequest.data == compressed)
        }
    }

    @Test("Brotli responses survive bounded streaming decompression")
    func brotliDecompression() throws {
        let compressed = try #require(Data(base64Encoded:
            "Gz8AwEVveL07LsfPdaNWSonShSgCDUNhY2wOXa6gp7DpLSL5e7N+iBL6src01gNAAg=="))
        let result = BodyDecoder.decodeReportingChange(compressed, encoding: "br")
        #expect(result.didDecode)
        #expect(String(data: result.data, encoding: .utf8) ==
            "A Brotli fixture should survive bounded streaming decompression.")
    }

    @Test(
        "Hot-path response readers enforce their decoded output budget",
        arguments: [64, 4_095, 4_096, 0, -1, Int.max]
    )
    func responseReaderOutputBudget(limit: Int) throws {
        let original = Data(repeating: 0x41, count: 4_096)
        let compressed = try #require(deflateCompress(original))
        #expect(compressed.count <= 64)
        let response = HTTPResponseData(
            statusCode: 200, statusMessage: "OK",
            headers: [HTTPHeader(name: "Content-Encoding", value: "deflate")], body: compressed
        )
        let withinLimit = limit >= original.count
        #expect(response.decodedBody(limit: limit) == (withinLimit ? original : compressed))
        let direct = BodyDecoder.decodeReportingChange(compressed, encoding: "deflate", maxOutputSize: limit)
        #expect(direct.didDecode == withinLimit)
        #expect(direct.data == (withinLimit ? original : compressed))
    }

    @Test(
        "Caller output budgets apply to gzip, deflate and Brotli",
        arguments: ["gzip", "deflate", "br"]
    )
    func encodingOutputBudget(encoding: String) throws {
        let original = Data("A Brotli fixture should survive bounded streaming decompression.".utf8)
        let compressed: Data = switch encoding {
        case "br":
            try #require(Data(base64Encoded:
                "Gz8AwEVveL07LsfPdaNWSonShSgCDUNhY2wOXa6gp7DpLSL5e7N+iBL6src01gNAAg=="))
        case "gzip":
            try wrapInGzip(#require(deflateCompress(original)), originalData: original)
        default:
            try #require(deflateCompress(original))
        }
        let bounded = BodyDecoder.decodeReportingChange(compressed, encoding: encoding, maxOutputSize: 8)
        #expect(!bounded.didDecode)
        #expect(bounded.data == compressed)
        let exact = BodyDecoder.decodeReportingChange(compressed, encoding: encoding, maxOutputSize: original.count)
        #expect(exact.didDecode)
        #expect(exact.data == original)
    }

    @Test("Valid empty compressed bodies decode with a zero-byte budget", arguments: ["deflate", "gzip", "br"])
    func emptyCompressedBodies(encoding: String) {
        let bytes: [UInt8] = switch encoding {
        case "gzip": [31, 139, 8, 0, 0, 0, 0, 0, 0, 3, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case "br": [59]
        default: [3, 0]
        }
        for budget in [0, 1, 64] {
            let decoded = BodyDecoder.decodeReportingChange(Data(bytes), encoding: encoding, maxOutputSize: budget)
            #expect(decoded.didDecode)
            #expect(decoded.data.isEmpty)
        }
    }

    @Test("All gzip members share one output budget", arguments: [0, 5, 10, 11, 12])
    func concatenatedGzip(budget: Int) throws {
        let first = Data("first".utf8)
        let second = Data("second".utf8)
        let input = try wrapInGzip(#require(deflateCompress(first)), originalData: first)
            + wrapInGzip(#require(deflateCompress(second)), originalData: second)
        let decoded = BodyDecoder.decodeReportingChange(input, encoding: "gzip", maxOutputSize: budget)
        #expect(decoded.didDecode == (budget >= 11))
        #expect(decoded.data == (budget >= 11 ? first + second : input))
    }

    @Test("Gzip validates every header, checksum, length and member before publishing", arguments: 0 ..< 8)
    func invalidGzipIntegrity(variant: Int) throws {
        let original = Data("Do not publish an unverified decoded prefix.".utf8)
        let valid = try wrapInGzip(#require(deflateCompress(original)), originalData: original)
        var input = valid
        switch variant {
        case 0: input[input.count - 8] ^= 1 // CRC32
        case 1: input[input.count - 4] ^= 1 // ISIZE
        case 2: input[2] = 0 // Invalid compression method
        case 3: input[3] = 0xE0 // Reserved flags
        case 4: input = Data(input.dropLast())
        case 5: input.append(contentsOf: [0, 1, 2]) // Unrecognized trailing bytes
        case 6: input.append(valid.dropLast()) // Incomplete second member
        default:
            var corrupt = valid
            corrupt[corrupt.count - 8] ^= 1
            input.append(corrupt) // Corrupt second member
        }
        let decoded = BodyDecoder.decodeReportingChange(input, encoding: "gzip")
        #expect(!decoded.didDecode)
        #expect(decoded.data == input)
    }

    @Test("Standard zlib-wrapped HTTP deflate validates Adler32")
    func standardZlibDeflate() {
        // Python zlib.compress(b"hello"); independent of the raw Apple Compression fixture helper.
        let input = Data([0x78, 0x9C, 0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0x07, 0x00, 0x06, 0x2C, 0x02, 0x15])
        let decoded = BodyDecoder.decodeReportingChange(input, encoding: "deflate")
        #expect(decoded.didDecode)
        #expect(decoded.data == Data("hello".utf8))
        var corrupt = input
        corrupt[corrupt.count - 1] ^= 1
        let invalid = BodyDecoder.decodeReportingChange(corrupt, encoding: "deflate")
        #expect(!invalid.didDecode)
        #expect(invalid.data == corrupt)
        let empty = Data([0x78, 0x9C, 3, 0, 0, 0, 0, 1])
        let emptyDecoded = BodyDecoder.decodeReportingChange(empty, encoding: "deflate", maxOutputSize: 0)
        #expect(emptyDecoded.didDecode)
        #expect(emptyDecoded.data.isEmpty)
    }

    @Test(
        "Truncated or trailing deflate and Brotli bytes do not report complete decoding",
        arguments: ["deflate", "br"]
    )
    func incompleteOrTrailingStreams(encoding: String) throws {
        let input: Data = if encoding == "br" {
            try #require(Data(base64Encoded:
                "Gz8AwEVveL07LsfPdaNWSonShSgCDUNhY2wOXa6gp7DpLSL5e7N+iBL6src01gNAAg=="))
        } else {
            try #require(deflateCompress(Data("A complete body requires a complete stream.".utf8)))
        }
        for invalid in [Data(input.dropLast()), input + Data([1, 2, 3])] {
            let result = BodyDecoder.decodeReportingChange(invalid, encoding: encoding)
            #expect(!result.didDecode)
            #expect(result.data == invalid)
        }
    }

    // MARK: Private

    private static func crc32(_ buffer: UnsafeRawBufferPointer) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in buffer {
            crc ^= UInt32(byte)
            for _ in 0 ..< 8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFFFFFF
    }

    // MARK: - Helpers

    private func deflateCompress(_ input: Data) -> Data? {
        let capacity = input.count + input.count / 8 + 1_024
        let destBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destBuffer.deallocate() }
        let compressedSize = input.withUnsafeBytes { srcPtr -> Int in
            guard let base = srcPtr.baseAddress else {
                return 0
            }
            return compression_encode_buffer(
                destBuffer, capacity,
                base.assumingMemoryBound(to: UInt8.self),
                input.count, nil, COMPRESSION_ZLIB
            )
        }
        guard compressedSize > 0 else {
            return nil
        }
        return Data(bytes: destBuffer, count: compressedSize)
    }

    private func wrapInGzip(_ deflatedData: Data, originalData: Data) -> Data {
        var gzip = Data()
        // Gzip header: magic bytes, compression method (deflate), flags, mtime, xfl, os
        gzip.append(contentsOf: [0x1F, 0x8B, 0x08, 0x00])
        gzip.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // mtime
        gzip.append(contentsOf: [0x00, 0x03]) // xfl, OS (Unix)
        // Compressed data
        gzip.append(deflatedData)
        // Trailer: CRC32 + original size (little-endian)
        var crc: UInt32 = 0
        originalData.withUnsafeBytes { ptr in
            crc = Self.crc32(ptr)
        }
        var crcLE = crc.littleEndian
        gzip.append(Data(bytes: &crcLE, count: 4))
        var sizeLE = UInt32(originalData.count).littleEndian
        gzip.append(Data(bytes: &sizeLE, count: 4))
        return gzip
    }
}
