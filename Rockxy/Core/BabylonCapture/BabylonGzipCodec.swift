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
        BoundedZlibDecoder.decode(data, windowBits: 31, concatenated: true, maxOutputSize: maximumOutputSize)
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
            let bufferSize = max(4_096, min(data.count, 32 * 1_024) * 2)
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            var stream = compression_stream(
                dst_ptr: buffer,
                dst_size: 0,
                src_ptr: source,
                src_size: 0,
                state: nil
            )
            guard compression_stream_init(&stream, operation, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
                return nil
            }
            defer { compression_stream_destroy(&stream) }

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
                    return stream.src_size == 0 ? result : nil
                default:
                    return nil
                }
            }
        }
    }

    private static func crc32(_ data: Data) -> UInt32 {
        ~data.reduce(~UInt32(0)) { checksum, byte in
            crcTable[Int((checksum ^ UInt32(byte)) & 0xFF)] ^ (checksum >> 8)
        }
    }
}
