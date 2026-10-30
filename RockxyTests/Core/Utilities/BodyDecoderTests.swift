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
