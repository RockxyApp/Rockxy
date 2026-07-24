import Compression
import Foundation

enum BabylonGzipCodec {
    // MARK: Internal

    static func gzip(_ data: Data) -> Data? {
        guard !data.isEmpty,
              let deflated = stream(data, operation: COMPRESSION_STREAM_ENCODE, maximumOutputSize: Int.max) else
        {
            return nil
        }

        var result = Data([0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03])
        result.append(deflated)
        var checksum = crc32(data).littleEndian
        result.append(Data(bytes: &checksum, count: MemoryLayout<UInt32>.size))
        var size = UInt32(truncatingIfNeeded: data.count).littleEndian
        result.append(Data(bytes: &size, count: MemoryLayout<UInt32>.size))
        return result
    }

    static func gunzip(_ data: Data, maximumOutputSize: Int) -> Data? {
        guard data.count >= 18, maximumOutputSize > 0 else {
            return nil
        }

        return data.withUnsafeBytes { rawBuffer -> Data? in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress,
                  bytes[0] == 0x1F,
                  bytes[1] == 0x8B,
                  bytes[2] == 0x08 else
            {
                return nil
            }

            let flags = bytes[3]
            guard flags & 0b11100000 == 0 else {
                return nil
            }
            var position = 10
            let footerStart = data.count - 8

            if flags & 0x04 != 0 {
                guard position + 2 <= footerStart else {
                    return nil
                }
                let extraLength = Int(bytes[position]) | (Int(bytes[position + 1]) << 8)
                position += 2 + extraLength
            }
            if flags & 0x08 != 0 {
                guard skipNullTerminated(bytes, position: &position, limit: footerStart) else {
                    return nil
                }
            }
            if flags & 0x10 != 0 {
                guard skipNullTerminated(bytes, position: &position, limit: footerStart) else {
                    return nil
                }
            }
            if flags & 0x02 != 0 {
                position += 2
            }
            guard position < footerStart else {
                return nil
            }

            let footer = bytes.advanced(by: footerStart)
            let expectedChecksum = readLittleEndianUInt32(footer)
            let expectedSize = readLittleEndianUInt32(footer.advanced(by: 4))
            let compressed = Data(bytes: bytes.advanced(by: position), count: footerStart - position)
            guard let inflated = stream(
                compressed,
                operation: COMPRESSION_STREAM_DECODE,
                maximumOutputSize: maximumOutputSize
            ), UInt32(truncatingIfNeeded: inflated.count) == expectedSize,
            crc32(inflated) == expectedChecksum else {
                return nil
            }
            return inflated
        }
    }

    // MARK: Private

    private static let crcTable: [UInt32] = (0 ..< 256).map { value in
        var checksum = UInt32(value)
        for _ in 0 ..< 8 {
            checksum = checksum & 1 == 1 ? 0xEDB88320 ^ (checksum >> 1) : checksum >> 1
        }
        return checksum
    }

    private static func stream(
        _ data: Data,
        operation: compression_stream_operation,
        maximumOutputSize: Int
    )
        -> Data?
    {
        guard !data.isEmpty else {
            return nil
        }
        return data.withUnsafeBytes { rawBuffer -> Data? in
            guard let source = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return nil
            }
            var stream = compression_stream(
                dst_ptr: UnsafeMutablePointer<UInt8>.allocate(capacity: 0),
                dst_size: 0,
                src_ptr: source,
                src_size: 0,
                state: nil
            )
            guard compression_stream_init(&stream, operation, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
                return nil
            }
            defer { compression_stream_destroy(&stream) }

            let bufferSize = max(4_096, min(data.count, 32 * 1_024) * 2)
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            var result = Data()
            stream.src_ptr = source
            stream.src_size = data.count
            stream.dst_ptr = buffer
            stream.dst_size = bufferSize
            let flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)

            while true {
                let status = compression_stream_process(&stream, flags)
                let produced = stream.dst_ptr - buffer
                guard produced <= maximumOutputSize,
                      result.count <= maximumOutputSize - produced else
                {
                    return nil
                }
                result.append(buffer, count: produced)
                switch status {
                case COMPRESSION_STATUS_OK:
                    guard stream.dst_size == 0 else {
                        return nil
                    }
                    stream.dst_ptr = buffer
                    stream.dst_size = bufferSize
                    continue
                case COMPRESSION_STATUS_END:
                    return result
                default:
                    return nil
                }
            }
        }
    }

    private static func skipNullTerminated(
        _ bytes: UnsafePointer<UInt8>,
        position: inout Int,
        limit: Int
    )
        -> Bool
    {
        while position < limit, bytes[position] != 0 {
            position += 1
        }
        guard position < limit else {
            return false
        }
        position += 1
        return true
    }

    private static func readLittleEndianUInt32(_ bytes: UnsafePointer<UInt8>) -> UInt32 {
        UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
    }

    private static func crc32(_ data: Data) -> UInt32 {
        ~data.reduce(~UInt32(0)) { checksum, byte in
            crcTable[Int((checksum ^ UInt32(byte)) & 0xFF)] ^ (checksum >> 8)
        }
    }
}
