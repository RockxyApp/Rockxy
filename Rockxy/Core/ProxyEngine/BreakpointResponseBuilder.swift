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
        originalHead: HTTPResponseHead,
        originalBody: Data? = nil
    )
        -> Result
    {
        let status = HTTPResponseStatus(statusCode: modifiedData.statusCode)

        var headers = HTTPHeaders()
        for header in modifiedData.headers {
            guard BreakpointRequestData.isValidHTTPHeaderName(header.name),
                  BreakpointRequestData.isValidHTTPHeaderValue(header.value) else
            {
                continue
            }
            headers.add(name: header.name.trimmingCharacters(in: .whitespacesAndNewlines), value: header.value)
        }

        let body: Data?
        if responseMustNotIncludeBody(method: modifiedData.method, statusCode: modifiedData.statusCode) {
            body = nil
            headers.remove(name: "Content-Length")
            headers.remove(name: "Transfer-Encoding")
        } else if !modifiedData.isBodyEditable {
            body = originalBody
            headers.remove(name: "Transfer-Encoding")
            if let originalBody {
                headers.replaceOrAdd(name: "Content-Length", value: "\(originalBody.count)")
            } else {
                headers.replaceOrAdd(name: "Content-Length", value: "0")
            }
        } else if modifiedData.body.isEmpty {
            body = nil
            headers.remove(name: "Transfer-Encoding")
            headers.replaceOrAdd(name: "Content-Length", value: "0")
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

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "BreakpointResponseBuilder"
    )

    private static func responseMustNotIncludeBody(method: String, statusCode: Int) -> Bool {
        method.caseInsensitiveCompare("HEAD") == .orderedSame
            || (100 ..< 200).contains(statusCode)
            || statusCode == 204
            || statusCode == 205
            || statusCode == 304
    }
}
