import Foundation
import NIOCore
import NIOHTTP1
import os

// Defines `BreakpointResponseBuilder`, which builds breakpoint response values for the
// proxy engine.

enum BreakpointResponseBuilder {
    // MARK: Internal

    struct Result {
        let head: HTTPResponseHead
        let body: Data?
    }

    static func build(
        modifiedData: BreakpointRequestData,
        originalHead: HTTPResponseHead
    )
        -> Result
    {
        let status = HTTPResponseStatus(statusCode: modifiedData.statusCode)

        var headers = HTTPHeaders()
        for header in modifiedData.headers {
            guard !header.name.isEmpty else {
                continue
            }
            headers.add(name: header.name, value: header.value)
        }

        let body: Data?
        if modifiedData.body.isEmpty {
            body = nil
            headers.remove(name: "Content-Length")
            headers.remove(name: "Transfer-Encoding")
        } else {
            let bodyData = Data(modifiedData.body.utf8)
            body = bodyData
            headers.remove(name: "Transfer-Encoding")
            headers.replaceOrAdd(name: "Content-Length", value: "\(bodyData.count)")
        }

        let head = HTTPResponseHead(
            version: originalHead.version,
            status: status,
            headers: headers
        )

        logger.debug("Built response: \(status.code) with \(body?.count ?? 0) bytes")
        return Result(head: head, body: body)
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "BreakpointResponseBuilder")
}
