import Foundation

extension HTTPResponseData {
    /// The response payload with its `Content-Encoding` removed, for readers that need to
    /// interpret the bytes (traffic detectors, exporters, diff). Captured bodies keep the
    /// wire encoding, so a gzip/deflate/Brotli JSON response would otherwise be parsed as
    /// binary and every payload-derived field would report unavailable.
    ///
    /// Bounded: a captured or expanded body larger than `limit` is returned as captured.
    /// Hot-path readers retain their size guards without inflating beyond their budget.
    func decodedBody(limit: Int) -> Data? {
        guard let body, !body.isEmpty, body.count <= limit else {
            return body
        }
        let contentEncoding = headers.first { $0.name.lowercased() == "content-encoding" }?.value
        return BodyDecoder.decode(body, encoding: contentEncoding, maxOutputSize: limit)
    }
}
