import Compression
import Foundation
import os
import zlib

/// Decompresses HTTP response bodies based on the `Content-Encoding` header.
/// Supports gzip, deflate (zlib), and Brotli. Falls back to the raw data if
/// decompression fails or the encoding is unrecognized. Caps output at 50 MB
/// to prevent memory exhaustion from decompression bombs.
enum BodyDecoder {
    // MARK: Internal

    /// Optional caller budgets may lower the global cap, never raise it.
    static func decode(_ data: Data, encoding: String?, maxOutputSize: Int? = nil) -> Data {
        decodeReportingChange(data, encoding: encoding, maxOutputSize: maxOutputSize).data
    }

    /// Decodes `data` and reports whether every `Content-Encoding` stage was applied, i.e.
    /// the returned bytes are the fully decoded body. Callers that hand the decoded body to
    /// an editor (Map Local drafts, breakpoints) use the flag to drop the now-inaccurate
    /// `Content-Encoding` header. An unknown encoding or a failed stage reports `false`;
    /// the bytes then follow the same best-effort fallback as `decode`, so callers that
    /// need the untouched payload should keep their original copy when the flag is `false`.
    static func decodeReportingChange(
        _ data: Data,
        encoding: String?,
        maxOutputSize: Int? = nil
    )
        -> (data: Data, didDecode: Bool)
    {
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
        let outputLimit = min(max(0, maxOutputSize ?? maxDecompressedSize), maxDecompressedSize)
        var body = data
        var everyStageDecoded = true
        for encoding in encodings.reversed() {
            guard let decoded = decodeSingle(body, encoding: encoding, maxOutputSize: outputLimit) else {
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
    private static func decodeSingle(_ data: Data, encoding: String, maxOutputSize: Int) -> Data? {
        switch encoding {
        case "gzip":
            inflate(data, windowBits: 31, concatenated: true, maxOutputSize: maxOutputSize)
        case "deflate":
            inflateDeflate(data, maxOutputSize: maxOutputSize)
        case "br":
            decompress(data, algorithm: COMPRESSION_BROTLI, maxOutputSize: maxOutputSize)
        default:
            nil
        }
    }

    private static func inflateDeflate(_ data: Data, maxOutputSize: Int) -> Data? {
        // HTTP deflate uses the zlib wrapper, but legacy servers also send raw deflate.
        // A recognized wrapper must pass its checksum, rather than falling back to raw bytes.
        let header = Array(data.prefix(2))
        let hasZlibHeader = header.count == 2 && header[0] & 0x0F == 8 && header[0] >> 4 <= 7
            && (Int(header[0]) * 256 + Int(header[1])) % 31 == 0
        return inflate(data, windowBits: hasZlibHeader ? 15 : -15, maxOutputSize: maxOutputSize)
    }

    private static func inflate(
        _ data: Data,
        windowBits: Int32,
        concatenated: Bool = false,
        maxOutputSize: Int
    )
        -> Data?
    {
        guard !data.isEmpty, data.count <= Int(UInt32.max) else {
            return nil
        }
        // One scratch byte lets a valid empty stream complete even with a zero output budget.
        let bufferSize = max(1, min(64 * 1_024, maxOutputSize))
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destination.deallocate() }
        return data.withUnsafeBytes { source -> Data? in
            guard let base = source.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return nil
            }
            var stream = z_stream()
            guard inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                return nil
            }
            defer { inflateEnd(&stream) }
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = UInt32(data.count)
            var result = Data()
            while true {
                stream.next_out = destination
                stream.avail_out = UInt32(bufferSize)
                let inputBefore = stream.avail_in
                let status = zlib.inflate(&stream, Z_NO_FLUSH)
                let produced = bufferSize - Int(stream.avail_out)
                guard produced <= maxOutputSize - result.count else {
                    return nil
                }
                if produced > 0 {
                    result.append(destination, count: produced)
                }
                if status == Z_STREAM_END {
                    guard stream.avail_in > 0 else {
                        return result
                    }
                    // RFC 1952 allows multiple members. Reset preserves unconsumed input;
                    // every member must validate before any decoded body is published.
                    guard concatenated, inflateReset(&stream) == Z_OK else {
                        return nil
                    }
                } else {
                    guard status == Z_OK, produced > 0 || stream.avail_in < inputBefore else {
                        return nil
                    }
                }
            }
        }
    }

    private static func decompress(_ data: Data, algorithm: compression_algorithm, maxOutputSize: Int) -> Data? {
        guard !data.isEmpty else {
            return nil
        }

        let bufferSize = max(1, min(64 * 1_024, maxOutputSize))
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
                let inputBefore = stream.src_size
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = bufferSize - stream.dst_size
                guard produced <= maxOutputSize - result.count else {
                    logger.warning("Decompressed data exceeds \(maxOutputSize) byte limit")
                    return nil
                }
                if produced > 0 {
                    result.append(destBuffer, count: produced)
                }
                switch status {
                case COMPRESSION_STATUS_OK:
                    guard produced > 0 || stream.src_size < inputBefore else {
                        return nil
                    }
                    continue
                case COMPRESSION_STATUS_END:
                    return stream.src_size == 0 ? result : nil
                default:
                    logger.debug("Decompression failed for algorithm \(algorithm.rawValue)")
                    return nil
                }
            }
        }
    }
}
