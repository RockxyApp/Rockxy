import Foundation

// MARK: - FocusNavigatorMode

enum FocusNavigatorMode: String, CaseIterable, Identifiable {
    case browse
    case focus
    case library

    var id: Self { self }

    var title: String {
        switch self {
        case .browse: String(localized: "Browse")
        case .focus: String(localized: "Focus")
        case .library: String(localized: "Library")
        }
    }
}

// MARK: - TrafficSignal

enum TrafficSignal: String, CaseIterable, Identifiable {
    case errors
    case slow
    case webSocket
    case graphQL
    case rulesHit

    var id: Self { self }

    var title: String {
        switch self {
        case .errors: String(localized: "Errors")
        case .slow: String(localized: "Slow")
        case .webSocket: String(localized: "WebSocket")
        case .graphQL: String(localized: "GraphQL")
        case .rulesHit: String(localized: "Rules Hit")
        }
    }

    var systemImage: String {
        switch self {
        case .errors: "exclamationmark.triangle"
        case .slow: "hourglass"
        case .webSocket: "arrow.left.arrow.right"
        case .graphQL: "point.3.connected.trianglepath.dotted"
        case .rulesHit: "wand.and.stars"
        }
    }

    var explanation: String {
        switch self {
        case .errors:
            String(localized: "HTTP 4xx/5xx responses and failed transports")
        case .slow:
            String(localized: "Requests taking at least one second")
        case .webSocket:
            String(localized: "WebSocket sessions and valid upgrade handshakes")
        case .graphQL:
            String(localized: "GraphQL operations confirmed from captured request data")
        case .rulesHit:
            String(localized: "Requests affected by a matching debugging rule")
        }
    }

    func matches(_ transaction: HTTPTransaction) -> Bool {
        switch self {
        case .errors:
            return transaction.state == .failed
                || transaction.response.map { (400 ... 599).contains($0.statusCode) } == true
        case .slow:
            guard let duration = transaction.timingInfo?.totalDuration ?? transaction.measuredDuration else {
                return false
            }
            return duration >= Self.slowThreshold
        case .webSocket:
            return isWebSocket(transaction)
        case .graphQL:
            return transaction.graphQLInfo != nil
        case .rulesHit:
            return transaction.matchedRuleID != nil
                || transaction.matchedRuleName != nil
                || transaction.matchedRuleActionSummary != nil
                || transaction.matchedRulePattern != nil
        }
    }

    private static let slowThreshold: TimeInterval = 1

    private func isWebSocket(_ transaction: HTTPTransaction) -> Bool {
        if transaction.webSocketConnection != nil {
            return true
        }
        let scheme = transaction.request.url.scheme?.lowercased()
        if scheme == "ws" || scheme == "wss" {
            return true
        }
        let upgrade = transaction.request.headers.contains {
            $0.name.caseInsensitiveCompare("Upgrade") == .orderedSame
                && $0.value.caseInsensitiveCompare("websocket") == .orderedSame
        }
        let connection = transaction.request.headers.contains {
            $0.name.caseInsensitiveCompare("Connection") == .orderedSame
                && $0.value.lowercased().split(separator: ",").contains {
                    $0.trimmingCharacters(in: .whitespaces) == "upgrade"
                }
        }
        return upgrade && connection
    }
}

// MARK: - FocusSet

/// A compact, reusable traffic scope. Empty fields are wildcards; exclusions always win.
struct FocusSet: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var appName: String
    var domain: String
    var pathPrefix: String
    var excludedDomain: String
    var excludedPathPrefix: String

    init(
        id: UUID = UUID(),
        name: String,
        appName: String = "",
        domain: String = "",
        pathPrefix: String = "",
        excludedDomain: String = "",
        excludedPathPrefix: String = ""
    ) {
        self.id = id
        self.name = name
        self.appName = appName
        self.domain = domain
        self.pathPrefix = pathPrefix
        self.excludedDomain = excludedDomain
        self.excludedPathPrefix = excludedPathPrefix
    }

    func matches(_ transaction: HTTPTransaction) -> Bool {
        let host = transaction.request.host
        let path = transaction.request.path
        if !excludedDomain.isEmpty, DomainGrouping.host(host, matchesDomain: excludedDomain) {
            return false
        }
        if !excludedPathPrefix.isEmpty, DomainGrouping.path(path, matchesPrefix: excludedPathPrefix) {
            return false
        }
        if !appName.isEmpty, transaction.clientApp != appName {
            return false
        }
        if !domain.isEmpty, !DomainGrouping.host(host, matchesDomain: domain) {
            return false
        }
        if !pathPrefix.isEmpty, !DomainGrouping.path(path, matchesPrefix: pathPrefix) {
            return false
        }
        return true
    }

    var ruleCount: Int {
        [appName, domain, pathPrefix, excludedDomain, excludedPathPrefix].count { !$0.isEmpty }
    }
}

// MARK: - FocusSetPersistence

enum FocusSetPersistence {
    static func load() -> [FocusSet] {
        guard !RockxyIdentity.isRunningTests,
              let data = UserDefaults.standard.data(forKey: storageKey),
              let values = try? JSONDecoder().decode([FocusSet].self, from: data) else
        {
            return []
        }
        return values
    }

    static func save(_ focusSets: [FocusSet]) {
        guard !RockxyIdentity.isRunningTests,
              let data = try? JSONEncoder().encode(focusSets) else {
            return
        }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static let storageKey = RockxyIdentity.current.defaultsKey("focusNavigator.focusSets")
}

// MARK: - MutedTrafficSource

enum MutedTrafficSource: Hashable, Identifiable {
    case host(String)
    case pathPrefix(String)

    var id: String {
        switch self {
        case let .host(value): "host:\(value)"
        case let .pathPrefix(value): "path:\(value)"
        }
    }

    var title: String {
        switch self {
        case let .host(value), let .pathPrefix(value): value
        }
    }

    var systemImage: String {
        switch self {
        case .host: "network.slash"
        case .pathPrefix: "eye.slash"
        }
    }

    func matches(_ transaction: HTTPTransaction) -> Bool {
        switch self {
        case let .host(value):
            DomainGrouping.host(transaction.request.host, matchesDomain: value)
        case let .pathPrefix(value):
            DomainGrouping.path(transaction.request.path, matchesPrefix: value)
        }
    }
}
