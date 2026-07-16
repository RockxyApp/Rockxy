import Foundation

/// Applies the sidebar's lightweight search without changing its navigation hierarchy.
enum SidebarSearchFilter {
    static func matches(_ candidate: String, query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return true
        }
        return candidate.range(
            of: normalizedQuery,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    static func apps(_ apps: [AppInfo], query: String) -> [AppInfo] {
        guard hasQuery(query) else {
            return apps
        }
        return apps.compactMap { app in
            if matches(app.name, query: query) {
                return app
            }
            let matchingDomains = app.domains.filter { matches($0, query: query) }
            guard !matchingDomains.isEmpty else {
                return nil
            }
            return AppInfo(name: app.name, domains: matchingDomains, requestCount: app.requestCount)
        }
    }

    static func domainTree(_ nodes: [DomainNode], query: String) -> [DomainNode] {
        guard hasQuery(query) else {
            return nodes
        }
        return nodes.compactMap { node in
            if matches(node.domain, query: query)
                || matches(node.selectionDomain, query: query)
                || node.pathPrefix.map({ matches($0, query: query) }) == true
            {
                return node
            }
            let matchingChildren = domainTree(node.children, query: query)
            guard !matchingChildren.isEmpty else {
                return nil
            }
            var ancestor = node
            ancestor.children = matchingChildren
            return ancestor
        }
    }

    static func domainMatchCount(_ nodes: [DomainNode], query: String) -> Int {
        guard hasQuery(query) else {
            return nodes.reduce(0) { $0 + 1 + domainMatchCount($1.children, query: query) }
        }
        return nodes.reduce(0) { count, node in
            let nodeMatches = matches(node.domain, query: query)
                || matches(node.selectionDomain, query: query)
                || node.pathPrefix.map { matches($0, query: query) } == true
            return count + (nodeMatches ? 1 : 0) + domainMatchCount(node.children, query: query)
        }
    }

    static func focusSets(_ values: [FocusSet], query: String) -> [FocusSet] {
        values.filter { value in
            [
                value.name,
                value.appName,
                value.domain,
                value.pathPrefix,
                value.excludedDomain,
                value.excludedPathPrefix,
            ].contains { matches($0, query: query) }
        }
    }

    static func mutedSources(_ values: [MutedTrafficSource], query: String) -> [MutedTrafficSource] {
        values.filter { matches($0.title, query: query) }
    }

    static func transactions(_ values: [HTTPTransaction], query: String) -> [HTTPTransaction] {
        values.filter { transaction in
            [
                transaction.request.url.absoluteString,
                transaction.request.host,
                transaction.request.path,
                transaction.request.method,
                transaction.clientApp ?? "",
                transaction.comment ?? "",
            ].contains { matches($0, query: query) }
        }
    }

    static func favorites(_ values: [SidebarItem], query: String) -> [SidebarItem] {
        guard hasQuery(query) else {
            return values
        }
        return values.filter { value in
            switch value {
            case let .domainNode(domain):
                matches(domain, query: query)
            case let .domainPath(domain, pathPrefix):
                matches("\(domain)\(pathPrefix)", query: query)
            case let .app(name, _):
                matches(name, query: query)
            default:
                false
            }
        }
    }

    static func trafficSignals(_ values: [TrafficSignal], query: String) -> [TrafficSignal] {
        values.filter {
            matches($0.title, query: query) || matches($0.explanation, query: query)
        }
    }

    static func hasQuery(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
