import Compression
import Foundation
import os

/// Decompresses HTTP response bodies based on the `Content-Encoding` header.
/// Supports gzip, deflate (zlib), and Brotli. Falls back to the raw data if
/// decompression fails or the encoding is unrecognized. Caps output at 50 MB
/// to prevent memory exhaustion from decompression bombs.
enum BodyDecoder {
    // MARK: Internal

    static func decode(_ data: Data, encoding: String?) -> Data {
        guard let encoding = encoding?.lowercased() else {
            return data
        }
        switch encoding {
        case "gzip":
            return decompressGzip(data) ?? data
        case "deflate":
            return decompress(data, algorithm: COMPRESSION_ZLIB) ?? data
        case "br":
            return decompress(data, algorithm: COMPRESSION_BROTLI) ?? data
        default:
            return data
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "BodyDecoder")

    private static let maxDecompressedSize = 50 * 1024 * 1024 // 50MB

    private static func decompressGzip(_ data: Data) -> Data? {
        guard data.count >= 18 else {
            logger.debug("Data too small for gzip (\(data.count) bytes), trying raw deflate")
            return decompress(data, algorithm: COMPRESSION_ZLIB)
        }

        let byte0 = data[data.startIndex]
        let byte1 = data[data.startIndex + 1]

        guard byte0 == 0x1F, byte1 == 0x8B else {
            logger.debug("Missing gzip magic bytes, trying raw deflate")
            return decompress(data, algorithm: COMPRESSION_ZLIB)
        }

        let stripped = stripGzipHeaderAndTrailer(data)
        return decompress(stripped, algorithm: COMPRESSION_ZLIB)
    }

    private static func stripGzipHeaderAndTrailer(_ data: Data) -> Data {
        var offset = 10 // Minimum gzip header size
        let flags = data[data.startIndex + 3]

        // FEXTRA (bit 2)
        if flags & 0x04 != 0, offset + 2 <= data.count {
            let extraLen = Int(data[data.startIndex + offset])
                | (Int(data[data.startIndex + offset + 1]) << 8)
            offset += 2 + extraLen
        }

        // FNAME (bit 3) - null-terminated string
        if flags & 0x08 != 0 {
            while offset < data.count, data[data.startIndex + offset] != 0 {
                offset += 1
            }
            offset += 1 // skip null terminator
        }

        // FCOMMENT (bit 4) - null-terminated string
        if flags & 0x10 != 0 {
            while offset < data.count, data[data.startIndex + offset] != 0 {
                offset += 1
            }
            offset += 1
        }

        // FHCRC (bit 1) - 2-byte header CRC
        if flags & 0x02 != 0 {
            offset += 2
        }

        guard offset < data.count - 8 else {
            logger.debug("Gzip header consumed too much data, returning empty payload")
            return Data()
        }

        // Strip header and 8-byte trailer (CRC32 + ISIZE)
        let start = data.startIndex + offset
        let end = data.endIndex - 8
        return data[start ..< end]
    }

    private static func decompress(_ data: Data, algorithm: compression_algorithm) -> Data? {
        guard !data.isEmpty else {
            return nil
        }

        var stream = compression_stream(
            dst_ptr: UnsafeMutablePointer<UInt8>.allocate(capacity: 0),
            dst_size: 0,
            src_ptr: UnsafeMutablePointer<UInt8>(mutating: [0]),
            src_size: 0,
            state: nil
        )

        let initStatus = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, algorithm)
        guard initStatus == COMPRESSION_STATUS_OK else {
            logger.debug("Decompression stream init failed for algorithm \(algorithm.rawValue)")
            return nil
        }
        defer { compression_stream_destroy(&stream) }

        let bufferSize = max(data.count * 4, 1024)
        guard bufferSize <= maxDecompressedSize else {
            logger.warning("Decompressed data exceeds \(maxDecompressedSize) byte limit")
            return nil
        }

        var result = Data()

        return data.withUnsafeBytes { sourcePtr -> Data? in
            guard let baseAddress = sourcePtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return nil
            }

            stream.src_ptr = baseAddress
            stream.src_size = data.count

            let destBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { destBuffer.deallocate() }

            while true {
                stream.dst_ptr = destBuffer
                stream.dst_size = bufferSize

                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))

                let produced = bufferSize - stream.dst_size
                if produced > 0 {
                    result.append(destBuffer, count: produced)
                }

                if result.count > maxDecompressedSize {
                    logger.warning("Decompressed data exceeds \(maxDecompressedSize) byte limit")
                    return nil
                }

                switch status {
                case COMPRESSION_STATUS_OK:
                    continue
                case COMPRESSION_STATUS_END:
                    return result.isEmpty ? nil : result
                default:
                    logger.debug("Decompression failed for algorithm \(algorithm.rawValue)")
                    return nil
                }
            }
        }
    }
}
