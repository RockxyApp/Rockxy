import Foundation

// MARK: - JSONPathEvaluator

struct JSONPathEvaluator: Sendable {
    let document: JSONPathDocument
    let limits: JSONPathEvaluationLimits

    init(document: JSONPathDocument, limits: JSONPathEvaluationLimits = .default) {
        self.document = document
        self.limits = limits
    }

    func evaluate(_ query: String) throws -> JSONPathQueryResult {
        var parser = try JSONPathParser(source: query, limits: limits)
        let expression = try parser.parse()
        let matches = try evaluate(expression, current: document.root)
        return queryResult(matches: matches)
    }

    func evaluate(_ expression: JSONPathExpression, current: JSONPathNode) throws -> [JSONPathNode] {
        var nodes: [JSONPathNode] = switch expression.origin {
        case .root: [document.root]
        case .current: [current]
        }

        var visited = 0
        for segment in expression.segments {
            try Task.checkCancellation()
            nodes = try apply(segment, to: nodes, visited: &visited)
            if nodes.count > limits.maxResultNodes {
                nodes = Array(nodes.prefix(limits.maxResultNodes + 1))
                break
            }
        }

        if let tailFunction = expression.tailFunction {
            return try applyTailFunction(tailFunction, to: nodes)
        }
        return nodes
    }

    func keyPath(_ query: String) throws -> JSONPathQueryResult {
        let path = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return .empty
        }
        let converted = "$." + path
        return try evaluate(converted)
    }

    func search(_ query: String, mode: JSONTreeFilterMode) throws -> JSONPathQueryResult {
        switch mode {
        case .jsonPath:
            return try evaluate(query)
        case .keyPath:
            return try keyPath(query)
        case .allKeys,
             .allValues:
            return try textSearch(query, mode: mode)
        }
    }

    private func apply(
        _ segment: JSONPathSegment,
        to nodes: [JSONPathNode],
        visited: inout Int
    ) throws -> [JSONPathNode] {
        let isDescendant: Bool
        let selectors: [JSONPathSelector]
        switch segment {
        case let .child(value):
            isDescendant = false
            selectors = value
        case let .descendant(value):
            isDescendant = true
            selectors = value
        }

        var results: [JSONPathNode] = []
        for node in nodes {
            let candidates = isDescendant ? descendants(of: node, includeSelf: false, visited: &visited) : [node]
            for candidate in candidates {
                for selector in selectors {
                    try Task.checkCancellation()
                    results.append(contentsOf: try apply(selector, to: candidate))
                    if results.count > limits.maxResultNodes {
                        return Array(results.prefix(limits.maxResultNodes + 1))
                    }
                }
            }
        }
        return unique(results)
    }

    private func apply(_ selector: JSONPathSelector, to node: JSONPathNode) throws -> [JSONPathNode] {
        switch selector {
        case let .name(name):
            guard case let .object(pairs) = node.value else {
                return []
            }
            return pairs.filter { $0.key == name }.map(\.value)
        case let .index(index):
            guard case let .array(items) = node.value else {
                return []
            }
            let normalized = index < 0 ? items.count + index : index
            guard items.indices.contains(normalized) else {
                return []
            }
            return [items[normalized]]
        case .wildcard:
            return node.children
        case let .slice(start, end, step):
            guard case let .array(items) = node.value else {
                return []
            }
            return slice(items, start: start, end: end, step: step)
        case let .filter(expr):
            return try node.children.filter { child in
                try booleanValue(evaluateFilter(expr, current: child))
            }
        }
    }

    private func slice(_ items: [JSONPathNode], start: Int?, end: Int?, step: Int?) -> [JSONPathNode] {
        guard !items.isEmpty else {
            return []
        }
        let count = items.count
        let step = step ?? 1
        guard step != 0 else {
            return []
        }
        func normalize(_ value: Int?, default defaultValue: Int) -> Int {
            guard let value else {
                return defaultValue
            }
            return value < 0 ? count + value : value
        }
        var index = normalize(start, default: step > 0 ? 0 : count - 1)
        let stop = normalize(end, default: step > 0 ? count : -1)
        var result: [JSONPathNode] = []
        while step > 0 ? index < stop : index > stop {
            if items.indices.contains(index) {
                result.append(items[index])
            }
            index += step
        }
        return result
    }

    private func descendants(of node: JSONPathNode, includeSelf: Bool, visited: inout Int) -> [JSONPathNode] {
        var result = includeSelf ? [node] : []
        for child in node.children {
            visited += 1
            guard visited <= limits.maxVisitedNodes else {
                break
            }
            result.append(child)
            result.append(contentsOf: descendants(of: child, includeSelf: false, visited: &visited))
        }
        return result
    }

    private func applyTailFunction(_ function: JSONPathFunctionCall, to nodes: [JSONPathNode]) throws -> [JSONPathNode] {
        let value = try functionValue(name: function.name, nodes: nodes, current: document.root, arguments: function.arguments)
        return [JSONPathNode.synthetic(value: value, path: "$.\(function.name)()")]
    }

    private func textSearch(_ query: String, mode: JSONTreeFilterMode) throws -> JSONPathQueryResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .empty
        }
        let matcher = try JSONTreeTextMatcher(query: trimmed, limits: limits)
        let matches = document.flattenedNodes.filter { node in
            switch mode {
            case .allKeys:
                guard let key = node.key else {
                    return false
                }
                return matcher.matches(key)
            case .allValues:
                guard !node.isContainer else {
                    return false
                }
                return matcher.matches(node.scalarDescription)
            case .jsonPath,
                 .keyPath:
                return false
            }
        }
        return queryResult(matches: matches)
    }

    private func queryResult(matches: [JSONPathNode]) -> JSONPathQueryResult {
        let limited = Array(matches.prefix(limits.maxResultNodes))
        let paths = ancestorPaths(for: limited)
        return JSONPathQueryResult(
            matches: limited,
            includedPaths: paths,
            selectedIndex: limited.isEmpty ? 0 : 1,
            diagnostic: nil,
            isTruncated: matches.count > limits.maxResultNodes
        )
    }

    private func ancestorPaths(for nodes: [JSONPathNode]) -> Set<String> {
        var paths: Set<String> = []
        let allNodes = document.flattenedNodes
        for node in nodes {
            for candidate in allNodes where node.path == candidate.path || node.path.hasPrefix(candidate.path + "[")
                || node.path.hasPrefix(candidate.path + "['")
            {
                paths.insert(candidate.path)
            }
            paths.insert(node.path)
        }
        return paths
    }

    private func unique(_ nodes: [JSONPathNode]) -> [JSONPathNode] {
        var seen: Set<String> = []
        var result: [JSONPathNode] = []
        for node in nodes where seen.insert(node.path).inserted {
            result.append(node)
        }
        return result
    }
}

// MARK: - Filter Evaluation

private extension JSONPathEvaluator {
    func evaluateFilter(_ expression: JSONPathFilterExpression, current: JSONPathNode) throws -> JSONFilterValue {
        switch expression {
        case let .literal(literal):
            literal.filterValue
        case let .path(path):
            .nodes(try evaluate(path, current: current))
        case let .array(values):
            .array(try values.map { try evaluateFilter($0, current: current) })
        case let .function(function):
            try functionValue(name: function.name, nodes: [current], current: current, arguments: function.arguments)
        case let .unaryNot(expr):
            .bool(!(try booleanValue(evaluateFilter(expr, current: current))))
        case let .binary(lhs, op, rhs):
            try evaluateBinary(lhs: lhs, op: op, rhs: rhs, current: current)
        }
    }

    func evaluateBinary(
        lhs: JSONPathFilterExpression,
        op: JSONPathBinaryOperator,
        rhs: JSONPathFilterExpression,
        current: JSONPathNode
    ) throws -> JSONFilterValue {
        if op == .and {
            return .bool(try booleanValue(evaluateFilter(lhs, current: current))
                && booleanValue(evaluateFilter(rhs, current: current)))
        }
        if op == .or {
            return .bool(try booleanValue(evaluateFilter(lhs, current: current))
                || booleanValue(evaluateFilter(rhs, current: current)))
        }

        let left = try evaluateFilter(lhs, current: current)
        let right = try evaluateFilter(rhs, current: current)
        switch op {
        case .equal: return .bool(compare(left, right) == .orderedSame)
        case .notEqual: return .bool(compare(left, right) != .orderedSame)
        case .less: return .bool(compare(left, right) == .orderedAscending)
        case .lessOrEqual:
            let result = compare(left, right)
            return .bool(result == .orderedAscending || result == .orderedSame)
        case .greater: return .bool(compare(left, right) == .orderedDescending)
        case .greaterOrEqual:
            let result = compare(left, right)
            return .bool(result == .orderedDescending || result == .orderedSame)
        case .regexMatch:
            return .bool(regexMatches(left, right))
        case .in:
            return .bool(arrayValues(right).contains(scalar(left)))
        case .nin:
            return .bool(!arrayValues(right).contains(scalar(left)))
        case .subsetof:
            let lhs = Set(arrayValues(left))
            let rhs = Set(arrayValues(right))
            return .bool(!lhs.isEmpty && lhs.isSubset(of: rhs))
        case .anyof:
            let lhs = Set(arrayValues(left))
            let rhs = Set(arrayValues(right))
            return .bool(!lhs.intersection(rhs).isEmpty)
        case .noneof:
            let lhs = Set(arrayValues(left))
            let rhs = Set(arrayValues(right))
            return .bool(lhs.intersection(rhs).isEmpty)
        case .size:
            return .bool(collectionSize(left) == Int(numberValue(right) ?? -1))
        case .empty:
            return .bool((collectionSize(left) == 0) == booleanValue(right))
        case .and,
             .or:
            return .bool(false)
        }
    }

    func functionValue(
        name: String,
        nodes: [JSONPathNode],
        current: JSONPathNode,
        arguments: [JSONPathFilterExpression]
    ) throws -> JSONFilterValue {
        let lower = name.lowercased()
        let argumentValue: (Int) throws -> JSONFilterValue = { index in
            guard arguments.indices.contains(index) else {
                return .nodes(nodes)
            }
            return try evaluateFilter(arguments[index], current: current)
        }

        switch lower {
        case "length":
            return .number(Double(collectionSize(try argumentValue(0))))
        case "count":
            return .number(Double(arrayValues(try argumentValue(0)).count))
        case "keys":
            let sourceNodes = nodesFrom(try argumentValue(0), fallback: nodes)
            let keys = sourceNodes.flatMap { node -> [JSONFilterValue] in
                if case let .object(pairs) = node.value {
                    return pairs.map { .string($0.key) }
                }
                return []
            }
            return .array(keys)
        case "min":
            return aggregate(nodes, using: Swift.min)
        case "max":
            return aggregate(nodes, using: Swift.max)
        case "avg":
            let numbers = nodes.compactMap { $0.value.doubleValue }
            guard !numbers.isEmpty else { return .null }
            return .number(numbers.reduce(0, +) / Double(numbers.count))
        case "sum":
            return .number(nodes.compactMap { $0.value.doubleValue }.reduce(0, +))
        case "stddev":
            let numbers = nodes.compactMap { $0.value.doubleValue }
            guard !numbers.isEmpty else { return .null }
            let avg = numbers.reduce(0, +) / Double(numbers.count)
            let variance = numbers.map { pow($0 - avg, 2) }.reduce(0, +) / Double(numbers.count)
            return .number(sqrt(variance))
        case "first":
            return nodes.first.map(JSONFilterValue.node) ?? .null
        case "last":
            return nodes.last.map(JSONFilterValue.node) ?? .null
        case "index":
            let index = Int(numberValue(try argumentValue(0)) ?? 0)
            let normalized = index < 0 ? nodes.count + index : index
            guard nodes.indices.contains(normalized) else {
                return .null
            }
            return .node(nodes[normalized])
        case "match":
            guard let text = stringValue(try argumentValue(0)),
                  let pattern = stringValue(try argumentValue(1)),
                  pattern.count <= limits.maxRegexPatternLength,
                  let regex = try? NSRegularExpression(pattern: pattern) else
            {
                return .bool(false)
            }
            let range = NSRange(location: 0, length: (text as NSString).length)
            guard let match = regex.firstMatch(in: text, range: range) else {
                return .bool(false)
            }
            return .bool(match.range.location == 0 && match.range.length == range.length)
        case "search":
            guard let text = stringValue(try argumentValue(0)),
                  let pattern = stringValue(try argumentValue(1)),
                  pattern.count <= limits.maxRegexPatternLength,
                  let regex = try? NSRegularExpression(pattern: pattern) else
            {
                return .bool(false)
            }
            return .bool(regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil)
        case "value":
            let sourceNodes = nodesFrom(try argumentValue(0), fallback: nodes)
            return sourceNodes.count == 1 ? .node(sourceNodes[0]) : .null
        default:
            throw JSONPathError.evaluationFailed(String(localized: "Unsupported function \(name)."))
        }
    }

    func aggregate(_ nodes: [JSONPathNode], using combine: (Double, Double) -> Double) -> JSONFilterValue {
        let numbers = nodes.compactMap { $0.value.doubleValue }
        guard let first = numbers.first else {
            return .null
        }
        return .number(numbers.dropFirst().reduce(first, combine))
    }
}

// MARK: - JSONFilterValue

private indirect enum JSONFilterValue: Equatable {
    case node(JSONPathNode)
    case nodes([JSONPathNode])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case regex(pattern: String, options: NSRegularExpression.Options)
    case array([JSONFilterValue])
}

private extension JSONPathLiteral {
    var filterValue: JSONFilterValue {
        switch self {
        case let .string(value): .string(value)
        case let .number(value): .number(value)
        case let .bool(value): .bool(value)
        case .null: .null
        case let .regex(pattern, options): .regex(pattern: pattern, options: options)
        }
    }
}

private extension JSONPathEvaluator {
    func booleanValue(_ value: JSONFilterValue) -> Bool {
        switch value {
        case let .bool(value): value
        case let .nodes(nodes): !nodes.isEmpty
        case let .node(node): node.value != .null
        case let .array(values): !values.isEmpty
        case let .string(value): !value.isEmpty
        case let .number(value): value != 0
        case .regex: true
        case .null: false
        }
    }

    func compare(_ lhs: JSONFilterValue, _ rhs: JSONFilterValue) -> ComparisonResult? {
        let left = scalar(lhs)
        let right = scalar(rhs)
        switch (left, right) {
        case let (.number(lhs), .number(rhs)):
            if lhs == rhs { return .orderedSame }
            return lhs < rhs ? .orderedAscending : .orderedDescending
        case let (.string(lhs), .string(rhs)):
            return lhs.compare(rhs)
        case let (.bool(lhs), .bool(rhs)):
            if lhs == rhs { return .orderedSame }
            return lhs == false ? .orderedAscending : .orderedDescending
        case (.null, .null):
            return .orderedSame
        default:
            return nil
        }
    }

    func regexMatches(_ lhs: JSONFilterValue, _ rhs: JSONFilterValue) -> Bool {
        guard let text = stringValue(lhs) else {
            return false
        }
        let regex: NSRegularExpression?
        switch rhs {
        case let .regex(pattern, options):
            regex = try? NSRegularExpression(pattern: pattern, options: options)
        case let .string(pattern):
            regex = try? NSRegularExpression(pattern: pattern)
        default:
            regex = nil
        }
        guard let regex else {
            return false
        }
        return regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    func scalar(_ value: JSONFilterValue) -> JSONScalarValue {
        switch value {
        case let .node(node):
            return scalar(.nodes([node]))
        case let .nodes(nodes):
            guard nodes.count == 1, let node = nodes.first else {
                return .array(nodes.map { scalar(.node($0)) })
            }
            switch node.value {
            case let .string(value): return .string(value)
            case let .number(value): return .number(Double(value) ?? 0)
            case let .bool(value): return .bool(value)
            case .null: return .null
            case .array,
                 .object: return .string(node.scalarDescription)
            }
        case let .string(value): return .string(value)
        case let .number(value): return .number(value)
        case let .bool(value): return .bool(value)
        case .null: return .null
        case .regex: return .null
        case let .array(values): return .array(values.map(scalar))
        }
    }

    func arrayValues(_ value: JSONFilterValue) -> [JSONScalarValue] {
        if case let .node(node) = value {
            return arrayValues(.nodes([node]))
        }
        if case let .nodes(nodes) = value,
           nodes.count == 1,
           let node = nodes.first,
           case let .array(items) = node.value
        {
            return items.map { scalar(.node($0)) }
        }
        switch scalar(value) {
        case let .array(values):
            return values
        case let scalar:
            return [scalar]
        }
    }

    func collectionSize(_ value: JSONFilterValue) -> Int {
        switch value {
        case let .nodes(nodes):
            guard nodes.count == 1, let node = nodes.first else {
                return nodes.count
            }
            return collectionSize(.node(node))
        case let .node(node):
            switch node.value {
            case let .string(value):
                return value.count
            case .array,
                 .object:
                return node.children.count
            default:
                return 0
            }
        case let .array(values): return values.count
        case let .string(value): return value.count
        default: return 0
        }
    }

    func numberValue(_ value: JSONFilterValue) -> Double? {
        switch scalar(value) {
        case let .number(value): value
        case let .string(value): Double(value)
        default: nil
        }
    }

    func stringValue(_ value: JSONFilterValue) -> String? {
        switch scalar(value) {
        case let .string(value): value
        case let .number(value): String(value)
        case let .bool(value): value ? "true" : "false"
        case .null: nil
        case .array: nil
        }
    }

    func nodesFrom(_ value: JSONFilterValue, fallback: [JSONPathNode]) -> [JSONPathNode] {
        switch value {
        case let .node(node): [node]
        case let .nodes(nodes): nodes
        default: fallback
        }
    }
}

// MARK: - JSONScalarValue

private indirect enum JSONScalarValue: Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONScalarValue])
}

// MARK: - Synthetic Nodes

private extension JSONPathNode {
    static func synthetic(value: JSONFilterValue, path: String) -> JSONPathNode {
        let object: Any = switch value {
        case let .node(node):
            node.scalarDescription
        case let .nodes(nodes):
            nodes.map(\.scalarDescription)
        case let .string(value):
            value
        case let .number(value):
            value
        case let .bool(value):
            value
        case .null:
            NSNull()
        case .regex:
            NSNull()
        case let .array(values):
            values.map { item -> Any in
                switch item {
                case let .string(value): value
                case let .number(value): value
                case let .bool(value): value
                case .null: NSNull()
                default: "\(item)"
                }
            }
        }
        var counter = 0
        return (try? JSONPathNode(
            object: object,
            key: nil,
            path: path,
            keyPath: path,
            depth: 0,
            counter: &counter,
            limits: .default
        )) ?? JSONPathNode.empty(path: path)
    }

    static func empty(path: String) -> JSONPathNode {
        var counter = 0
        do {
            return try JSONPathNode(
                object: NSNull(),
                key: nil,
                path: path,
                keyPath: path,
                depth: 0,
                counter: &counter,
                limits: .default
            )
        } catch {
            preconditionFailure("Unable to create empty JSONPath node: \(error)")
        }
    }
}

// MARK: - JSONTreeFilterMode

enum JSONTreeFilterMode: String, CaseIterable, Identifiable, Sendable {
    case jsonPath
    case keyPath
    case allKeys
    case allValues

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .jsonPath: "JSON Paths"
        case .keyPath: "Key Paths"
        case .allKeys: "All Keys"
        case .allValues: "All Values"
        }
    }

    var placeholder: String {
        switch self {
        case .jsonPath: "$.posts[*].user.name"
        case .keyPath: "posts[1].makers[2]"
        case .allKeys: "username"
        case .allValues: "/friedland/i"
        }
    }
}

// MARK: - JSONTreeTextMatcher

private struct JSONTreeTextMatcher {
    private let regex: NSRegularExpression?
    private let query: String

    init(query: String, limits: JSONPathEvaluationLimits) throws {
        if query.hasPrefix("/"), query.last == "/", query.count > 2 {
            let pattern = String(query.dropFirst().dropLast())
            guard pattern.count <= limits.maxRegexPatternLength else {
                throw JSONPathError.limitExceeded(String(localized: "Regex pattern is too long."))
            }
            regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            self.query = ""
        } else {
            regex = nil
            self.query = query.lowercased()
        }
    }

    func matches(_ value: String) -> Bool {
        if let regex {
            return regex.firstMatch(in: value, range: NSRange(location: 0, length: (value as NSString).length)) != nil
        }
        return value.lowercased().contains(query)
    }
}
