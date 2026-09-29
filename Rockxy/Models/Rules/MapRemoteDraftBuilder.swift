import Foundation

/// Testable helper that builds MapRemoteDraft from transaction or domain data.
enum MapRemoteDraftBuilder {
    static func fromTransaction(_ transaction: HTTPTransaction) -> MapRemoteDraft {
        MapRemoteDraft(
            origin: .selectedTransaction,
            suggestedName: "Map Remote — \(transaction.request.host)\(transaction.request.path)",
            sourceURL: transaction.request.url,
            sourceHost: transaction.request.host,
            sourcePath: transaction.request.path,
            sourceMethod: transaction.request.method,
            graphQLOperationName: transaction.graphQLInfo?.operationName
        )
    }

    static func fromDomain(_ domain: String) -> MapRemoteDraft {
        MapRemoteDraft(
            origin: .domainQuickCreate,
            suggestedName: "Map Remote — \(domain)",
            sourceURL: nil,
            sourceHost: domain,
            sourcePath: nil,
            sourceMethod: nil
        )
    }
}
