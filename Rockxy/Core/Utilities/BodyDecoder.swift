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
        decodeReportingChange(data, encoding: encoding).data
    }

    /// Decodes `data` and reports whether every `Content-Encoding` stage was applied, i.e.
    /// the returned bytes are the fully decoded body. Callers that hand the decoded body to
    /// an editor (Map Local drafts, breakpoints) use the flag to drop the now-inaccurate
    /// `Content-Encoding` header. An unknown encoding or a failed stage reports `false`;
    /// the bytes then follow the same best-effort fallback as `decode`, so callers that
    /// need the untouched payload should keep their original copy when the flag is `false`.
    static func decodeReportingChange(_ data: Data, encoding: String?) -> (data: Data, didDecode: Bool) {
        guard let encoding else {
            return (data, false)
        }
        let encodings = encoding
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !encodings.isEmpty else {
            return (data, false)
        }
        var body = data
        var everyStageDecoded = true
        for encoding in encodings.reversed() {
            guard let decoded = decodeSingle(body, encoding: encoding) else {
                everyStageDecoded = false
                continue
            }
            body = decoded
        }
        return (body, everyStageDecoded)
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "BodyDecoder")

    private static let maxDecompressedSize = 50 * 1_024 * 1_024 // 50MB

    /// Returns `nil` when the encoding is unrecognized or decompression fails so the
    /// caller keeps the current bytes, matching the pre-existing fall-back behavior.
    private static func decodeSingle(_ data: Data, encoding: String) -> Data? {
        switch encoding {
        case "gzip":
            decompressGzip(data)
        case "deflate":
            decompress(data, algorithm: COMPRESSION_ZLIB)
        case "br":
            decompress(data, algorithm: COMPRESSION_BROTLI)
        default:
            nil
        }
    }

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

        let bufferSize = 64 * 1_024
        let destBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destBuffer.deallocate() }

        return data.withUnsafeBytes { sourcePtr -> Data? in
            guard let baseAddress = sourcePtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return nil
            }

            var stream = compression_stream(
                dst_ptr: destBuffer,
                dst_size: bufferSize,
                src_ptr: baseAddress,
                src_size: data.count,
                state: nil
            )
            let initStatus = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, algorithm)
            guard initStatus == COMPRESSION_STATUS_OK else {
                logger.debug("Decompression stream init failed for algorithm \(algorithm.rawValue)")
                return nil
            }
            defer { compression_stream_destroy(&stream) }
            stream.src_ptr = baseAddress
            stream.src_size = data.count

            var result = Data()
            while true {
                stream.dst_ptr = destBuffer
                stream.dst_size = bufferSize
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = bufferSize - stream.dst_size
                guard produced <= maxDecompressedSize - result.count else {
                    logger.warning("Decompressed data exceeds \(maxDecompressedSize) byte limit")
                    return nil
                }
                if produced > 0 {
                    result.append(destBuffer, count: produced)
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
