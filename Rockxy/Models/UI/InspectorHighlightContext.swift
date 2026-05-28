import Foundation

struct InspectorHighlightContext: Equatable, Sendable {
    static let empty = InspectorHighlightContext()

    var literalTerms: [String] = []
    var regexPatterns: [String] = []

    var isEmpty: Bool {
        literalTerms.isEmpty && regexPatterns.isEmpty
    }

    var identity: String {
        (literalTerms + regexPatterns.map { "regex:\($0)" }).joined(separator: "|")
    }

    func containsMatch(in text: String) -> Bool {
        !matchRanges(in: text).isEmpty
    }

    func matchRanges(in text: String, limit: Int = 250) -> [NSRange] {
        guard !text.isEmpty, !isEmpty else {
            return []
        }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var ranges: [NSRange] = []

        for term in literalTerms where !term.isEmpty {
            var searchRange = fullRange
            while searchRange.length > 0, ranges.count < limit {
                let found = nsText.range(of: term, options: [.caseInsensitive], range: searchRange)
                guard found.location != NSNotFound else {
                    break
                }
                ranges.append(found)
                let nextLocation = found.location + max(found.length, 1)
                let remaining = max(0, nsText.length - nextLocation)
                searchRange = NSRange(location: nextLocation, length: remaining)
            }
        }

        for pattern in regexPatterns where ranges.count < limit {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }
            regex.enumerateMatches(in: text, range: fullRange) { match, _, stop in
                guard let match else {
                    return
                }
                ranges.append(match.range)
                if ranges.count >= limit {
                    stop.pointee = true
                }
            }
        }

        return normalized(ranges).prefix(limit).map { $0 }
    }

    private func normalized(_ ranges: [NSRange]) -> [NSRange] {
        ranges
            .filter { $0.length > 0 }
            .sorted { lhs, rhs in
                lhs.location == rhs.location ? lhs.length > rhs.length : lhs.location < rhs.location
            }
            .reduce(into: [NSRange]()) { result, range in
                guard let last = result.last else {
                    result.append(range)
                    return
                }
                if range.location >= last.location + last.length {
                    result.append(range)
                }
            }
    }
}
