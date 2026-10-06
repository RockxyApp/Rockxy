import Foundation

// Display labels for Map Remote rule rows, split out of `MapRemoteWindowView.swift`.

extension MapRemoteWindowViewModel {
    func methodLabel(for rule: ProxyRule) -> String {
        rule.matchCondition.method?.uppercased() ?? "ANY"
    }

    func matchingRuleLabel(for rule: ProxyRule) -> String {
        if let sourcePattern = rule.matchCondition.sourceURLPattern, !sourcePattern.isEmpty {
            let prefix = rule.matchCondition.matchType == .regex ? "Regex: " : "Wildcard: "
            return prefix + sourcePattern
        }
        guard let pattern = rule.matchCondition.urlPattern, !pattern.isEmpty else {
            return "<Missing URL>"
        }
        if MapLocalPatternFormatter.prefersWildcardPresentation(pattern) {
            return "Wildcard: \(MapLocalPatternFormatter.readablePattern(pattern))"
        }
        return "Regex: \(pattern)"
    }

    func destinationLabel(for rule: ProxyRule) -> String {
        guard case let .mapRemote(config) = rule.action else {
            return ""
        }
        guard let host = config.host, !host.isEmpty else {
            var overrides: [String] = []
            if let scheme = config.scheme {
                overrides.append("Protocol \(scheme.uppercased())")
            }
            if let port = config.port {
                overrides.append("Port \(port)")
            }
            if let path = config.path, !config.preserveOriginalURL {
                overrides.append("Path \(path)")
            }
            if let query = config.query, !config.preserveOriginalURL {
                overrides.append("Query \(query)")
            }
            if config.preserveOriginalURL {
                overrides.append("Original target")
            }
            overrides.append("Original host")
            return overrides.joined(separator: " · ")
        }
        var result = ""
        if let scheme = config.scheme {
            result += "\(scheme)://"
        }
        let displayHost = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        result += displayHost
        if let port = config.port {
            result += ":\(port)"
        }
        if let path = config.path, !config.preserveOriginalURL {
            if result.isEmpty {
                result += path
            } else {
                result += path.hasPrefix("/") ? path : "/\(path)"
            }
        }
        if let query = config.query, !config.preserveOriginalURL {
            result += "?\(query)"
        }
        if config.preserveOriginalURL {
            result += " · Original target"
        }
        return result.isEmpty ? "—" : result
    }

    func preservesHost(for rule: ProxyRule) -> Bool {
        if case let .mapRemote(config) = rule.action {
            return config.preserveHostHeader
        }
        return false
    }
}
