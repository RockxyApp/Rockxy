import Compression
import Foundation
@testable import Rockxy
import Testing

// Tests for `BodyDecoder`: passthrough for nil/unknown/empty encodings,
// deflate and gzip decompression roundtrips, and graceful fallback on invalid data.

// MARK: - BodyDecoderTests

struct BodyDecoderTests {
    // MARK: Internal

    @Test("Nil encoding returns original data")
    func nilEncodingPassthrough() {
        let original = "Hello, World!".data(using: .utf8)!
        let result = BodyDecoder.decode(original, encoding: nil)
        #expect(result == original)
    }

    @Test("Unknown encoding returns original data")
    func unknownEncodingPassthrough() {
        let original = "Test data".data(using: .utf8)!
        let result = BodyDecoder.decode(original, encoding: "unknown-encoding")
        #expect(result == original)
    }

    @Test("Empty encoding string returns original data")
    func emptyEncodingPassthrough() {
        let original = "Identity test".data(using: .utf8)!
        let result = BodyDecoder.decode(original, encoding: "")
        #expect(result == original)
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
        let capacity = input.count + 1_024
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
