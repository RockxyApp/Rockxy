import Foundation

/// Quick-filter buttons in the traffic list toolbar. Covers protocol type (HTTP, HTTPS, WebSocket),
/// content type (JSON, XML, JS, CSS, GraphQL, media, document), and HTTP status code ranges.
/// Each case knows how to match itself against an `HTTPTransaction`.
enum ProtocolFilter: String, CaseIterable, Hashable {
    case all
    case http
    case https
    case websocket
    case web3RPC
    case json
    case xml
    case js
    case css
    case graphql
    case grpc
    case document
    case media
    case form
    case font
    case other
    case status1xx
    case status2xx
    case status3xx
    case status4xx
    case status5xx

    // MARK: Internal

    static var contentFilters: [ProtocolFilter] {
        [.all, .http, .https, .websocket, .web3RPC, .json, .xml, .js, .css, .graphql, .grpc, .document, .media, .form, .font, .other]
    }

    static var statusFilters: [ProtocolFilter] {
        [.status1xx, .status2xx, .status3xx, .status4xx, .status5xx]
    }

    var displayName: String {
        switch self {
        case .all: "All"
        case .http: "HTTP"
        case .https: "HTTPS"
        case .websocket: "WebSocket"
        case .web3RPC: "Web3/RPC"
        case .json: "JSON"
        case .xml: "XML"
        case .js: "JS"
        case .css: "CSS"
        case .graphql: "GraphQL"
        case .grpc: "gRPC"
        case .document: "Document"
        case .media: "Media"
        case .form: "Form"
        case .font: "Font"
        case .other: "Other"
        case .status1xx: "1xx"
        case .status2xx: "2xx"
        case .status3xx: "3xx"
        case .status4xx: "4xx"
        case .status5xx: "5xx"
        }
    }

    var isStatusFilter: Bool {
        switch self {
        case .status1xx,
             .status2xx,
             .status3xx,
             .status4xx,
             .status5xx:
            true
        default:
            false
        }
    }

    func matches(_ transaction: HTTPTransaction) -> Bool {
        switch self {
        case .all:
            return true
        case .http:
            return transaction.request.url.scheme == "http"
        case .https:
            return transaction.request.url.scheme == "https"
        case .websocket:
            return transaction.webSocketConnection != nil
        case .web3RPC:
            return transaction.web3RPCInfo != nil
        case .json:
            return transaction.response?.contentType == .json || transaction.request.contentType == .json
        case .xml:
            return transaction.response?.contentType == .xml || transaction.request.contentType == .xml
        case .js:
            return contentTypeHeader(for: transaction).contains("javascript")
        case .css:
            return contentTypeHeader(for: transaction).contains("css")
        case .graphql:
            return transaction.graphQLInfo != nil
        case .grpc:
            return GRPCDetector.isGRPC(transaction: transaction)
        case .document:
            return transaction.response?.contentType == .html
        case .media:
            return transaction.response?.contentType == .image
        case .form:
            return transaction.request.contentType == .form || transaction.request.contentType == .multipartForm
        case .font:
            return isFontContent(for: transaction)
        case .other:
            let known: Set<ContentType> = [.json, .xml, .html, .image, .form, .multipartForm, .protobuf, .text]
            guard let respType = transaction.response?.contentType else {
                return true
            }
            return !known.contains(respType) && !isFontContent(for: transaction)
        case .status1xx:
            return statusInRange(transaction, range: 100 ..< 200)
        case .status2xx:
            return statusInRange(transaction, range: 200 ..< 300)
        case .status3xx:
            return statusInRange(transaction, range: 300 ..< 400)
        case .status4xx:
            return statusInRange(transaction, range: 400 ..< 500)
        case .status5xx:
            return statusInRange(transaction, range: 500 ..< 600)
        }
    }

    // MARK: Private

    private func contentTypeHeader(for transaction: HTTPTransaction) -> String {
        let headers = (transaction.response?.headers ?? []) + transaction.request.headers
        return headers.first { $0.name.lowercased() == "content-type" }?.value.lowercased() ?? ""
    }

    private func isFontContent(for transaction: HTTPTransaction) -> Bool {
        let header = contentTypeHeader(for: transaction)
        return header.contains("font/") || header.contains("font-woff") || header.contains("x-font-ttf")
            || header.contains("vnd.ms-fontobject") || header.contains("font-sfnt")
    }

    private func statusInRange(_ transaction: HTTPTransaction, range: Range<Int>) -> Bool {
        guard let code = transaction.response?.statusCode else {
            return false
        }
        return range.contains(code)
    }
}
