import Foundation

/// Testable helper that builds MapLocalDraft from transaction or domain data.
/// Used by MainContentCoordinator context menu and sidebar menu actions.
enum MapLocalDraftBuilder {
    static func fromTransaction(_ transaction: HTTPTransaction) -> MapLocalDraft {
        let seed = editableResponseSeed(from: transaction.response)
        return MapLocalDraft(
            origin: .selectedTransaction,
            suggestedName: "Map Local — \(transaction.request.host)\(transaction.request.path)",
            sourceURL: transaction.request.url,
            sourceHost: transaction.request.host,
            sourcePath: transaction.request.path,
            sourceMethod: transaction.request.method,
            responseBody: seed.body,
            responseContentType: transaction.response?.headers.first {
                $0.name.lowercased() == "content-type"
            }?.value,
            inferredExtension: MimeTypeResolver.inferExtension(from: transaction),
            responseStatusCode: transaction.response?.statusCode,
            responseHeaders: seed.headers,
            graphQLOperationName: transaction.graphQLInfo?.operationName
        )
    }

    static func fromDomain(_ domain: String) -> MapLocalDraft {
        MapLocalDraft(
            origin: .domainQuickCreate,
            suggestedName: "Map Local — \(domain)",
            sourceHost: domain
        )
    }

    // MARK: Private

    /// Captured bodies are stored exactly as the origin sent them, so a `gzip`/`br`/`deflate`
    /// response would otherwise reach the editor as opaque binary bytes and be persisted
    /// compressed. Decode it up front — the way the inspector does for display — and drop the
    /// headers that only described the compressed representation (`Content-Encoding`, and the
    /// compressed `Content-Length`, which the serve path recomputes anyway). When decoding is
    /// not possible the raw bytes and their original headers are kept together unchanged.
    private static func editableResponseSeed(
        from response: HTTPResponseData?
    )
        -> (body: Data?, headers: [HTTPHeader])
    {
        guard let response else {
            return (nil, [])
        }
        guard let rawBody = response.body, !rawBody.isEmpty else {
            return (response.body, response.headers)
        }
        let contentEncoding = response.headers.first { $0.name.lowercased() == "content-encoding" }?.value
        let decoded = BodyDecoder.decodeReportingChange(rawBody, encoding: contentEncoding)
        guard decoded.didDecode else {
            return (rawBody, response.headers)
        }
        let headers = response.headers.filter { header in
            let name = header.name.lowercased()
            return name != "content-encoding" && name != "content-length"
        }
        return (decoded.data, headers)
    }
}
