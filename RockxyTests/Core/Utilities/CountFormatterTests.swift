import Foundation
@testable import Rockxy
import Testing

/// Every bare count Rockxy shows comes from `CountFormatter`, so the same quantity reads the same
/// way in a table value and in the sentence beside it. A count interpolated into a
/// `String(localized:)` key is extracted as `%lld` and rendered with the locale's digit grouping,
/// while `"\(count)"` and `String(count)` are locale-blind — the captured-value picker printed a
/// badge of "1234" directly above its own tooltip's "1,234 captured requests".
struct CountFormatterTests {
    // MARK: Internal

    @Test("A count is grouped the way a localized count is")
    func countsMatchLocalizedRendering() {
        // This is the divergence itself: the two spellings of one number, side by side.
        let grouped = CountFormatter.format(Self.sample)
        let reference = Self.sample.formatted(.number.locale(RockxyLocalization.locale))

        #expect(grouped == reference)
        #expect(grouped != String(Self.sample))
        // A count small enough never to reach a grouping boundary must not gain a separator.
        #expect(CountFormatter.format(7) == 7.formatted(.number.locale(RockxyLocalization.locale)))
    }

    @Test("Grouping follows the locale, not the machine")
    func groupingIsLocaleDependent() {
        // `en_VN` — the maintainer's locale — spells this "128.000" and `fr_FR` "128 000", so a
        // surface that skips the formatter is wrong in a way no walk on this machine reveals.
        let unitedStates = Self.sample.formatted(.number.locale(Locale(identifier: "en_US")))
        let france = Self.sample.formatted(.number.locale(Locale(identifier: "fr_FR")))

        #expect(unitedStates != france)
        #expect(unitedStates != String(Self.sample))
        #expect(france != String(Self.sample))
    }

    @Test("No surface renders a bare count without the shared formatter")
    func noSurfaceRendersABareCount() throws {
        var offenders: [String] = []
        for (path, source) in try Self.projectSources() where !Self.rawCountOwners.contains(path) {
            for (number, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let text = String(line)
                for expression in Self.wholeLiteralInterpolations(in: text) + Self.stringInitArguments(in: text)
                    where Self.looksLikeACount(expression)
                {
                    offenders.append("\(path):\(number + 1): \(text.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(
            offenders.isEmpty,
            "These lines render a count without CountFormatter: \(offenders.sorted())"
        )
    }

    @Test("No localized string groups a port number")
    func portsAreNeverGrouped() throws {
        // A port is an identifier, not a quantity. Interpolating an `Int` into a
        // `String(localized:)` key extracts it as `%lld`, which prints Rockxy's own default port
        // as "9,797" — the MCP settings row and the upstream-proxy result both did that.
        var offenders: [String] = []
        for (path, source) in try Self.projectSources(roots: Self.portScannedRoots) {
            for (number, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let text = String(line)
                guard text.contains("localized:") else {
                    continue
                }
                for expression in Self.wholeInterpolations(in: text)
                    where expression.lowercased().hasSuffix("port")
                {
                    offenders.append("\(path):\(number + 1): \(text.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(
            offenders.isEmpty,
            "These localized strings group a port number; wrap it in String(): \(offenders.sorted())"
        )
    }

    // MARK: Private

    private enum ResolveError: Error {
        case rootNotFound(filePath: String)
    }

    /// Large enough to cross a grouping boundary in every locale Rockxy ships.
    private static let sample = 128_000

    /// `PreviewTabContentView.renderID` builds a cache identity from body byte counts. It is never
    /// shown, and grouping it would make the key locale-dependent, so the snapshot would miss its
    /// own cache entry after a language change. The source says so at the call site.
    private static let rawCountOwners: Set<String> = [
        "Rockxy/Views/Inspector/PreviewTabContentView.swift",
    ]

    /// Directories whose strings reach a person. `Rockxy/Core` is excluded on purpose: a
    /// `Content-Length` header value is a wire quantity that must never carry a separator.
    /// `Shared/`, `RockxyHelperTool/` and `RockxyMCP/` are separate targets that cannot see
    /// `CountFormatter`, but their messages travel to the app's UI as error text and to AI clients
    /// as tool output, and scanning only sub-folders of `Rockxy/` let a bare count built there pass
    /// while the identical one in the app was caught. They hold no offender today, so a new one
    /// has to be reworded (unit before the number) or justified in `rawCountOwners`.
    private static let scannedRoots = [
        "Rockxy/Views", "Rockxy/Models/UI", "Rockxy/ViewModels",
        "Shared", "RockxyHelperTool", "RockxyMCP",
    ]

    /// The port check also covers `Rockxy/Core` and all of `Rockxy/Models`: any `String(localized:)`
    /// key is grouped wherever it is built.
    private static let portScannedRoots = [
        "Rockxy/Views", "Rockxy/Models", "Rockxy/ViewModels", "Rockxy/Core",
        "Shared", "RockxyHelperTool", "RockxyMCP",
    ]

    private static func looksLikeACount(_ expression: String) -> Bool {
        // `String(text.dropFirst(prefix.count))` converts a Substring; the count is an index, not
        // a quantity anyone reads.
        guard !expression.contains("drop") else {
            return false
        }
        return ["count", "Count", "Tokens", "Total"].contains { expression.contains($0) }
    }

    /// The expressions of literals that are nothing but one interpolation — `"\(node.errorCount)"`.
    /// A count with words around it goes through `String(localized:)` and is already grouped.
    private static func wholeLiteralInterpolations(in line: String) -> [String] {
        balancedExpressions(in: line, after: "\"\\(") { line, end in
            end < line.endIndex && line[end] == "\""
        }
    }

    /// The arguments of `String(…)` conversions that carry no argument label, so `String(localized:)`
    /// and its siblings are left alone.
    private static func stringInitArguments(in line: String) -> [String] {
        balancedExpressions(in: line, after: "String(") { _, _ in true }
            .filter { !$0.contains(":") }
    }

    private static func balancedExpressions(
        in line: String,
        after opening: String,
        isTerminated: (String, String.Index) -> Bool
    )
        -> [String]
    {
        var expressions: [String] = []
        var searchStart = line.startIndex
        while let range = line.range(of: opening, range: searchStart ..< line.endIndex) {
            var cursor = range.upperBound
            var depth = 1
            while cursor < line.endIndex, depth > 0 {
                if line[cursor] == "(" {
                    depth += 1
                } else if line[cursor] == ")" {
                    depth -= 1
                }
                cursor = line.index(after: cursor)
            }
            if depth == 0 {
                let close = line.index(before: cursor)
                if isTerminated(line, cursor) {
                    expressions.append(String(line[range.upperBound ..< close]))
                }
            }
            searchStart = range.upperBound
        }
        return expressions
    }

    /// Every `\\(…)` interpolation on a line, whatever surrounds it.
    private static func wholeInterpolations(in line: String) -> [String] {
        balancedExpressions(in: line, after: "\\(") { _, _ in true }
    }

    private static func projectSources(
        roots: [String] = scannedRoots
    )
        throws -> [(path: String, source: String)]
    {
        let root = try resolveProjectRoot()
        let prefix = root.path + "/"
        var sources: [(path: String, source: String)] = []
        for scanned in roots {
            let directory = root.appendingPathComponent(scanned)
            var contributed = 0
            let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "swift" else {
                    continue
                }
                let resolved = url.resolvingSymlinksInPath().path
                let path = resolved.hasPrefix(prefix) ? String(resolved.dropFirst(prefix.count)) : resolved
                try sources.append((path, String(contentsOf: url, encoding: .utf8)))
                contributed += 1
            }
            // A directory that is renamed or removed would silently shrink the scan.
            #expect(contributed > 0, "Scanned directory contributes no Swift sources: \(scanned)")
        }
        return sources
    }

    private static func resolveProjectRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        guard url.lastPathComponent == "RockxyTests" else {
            throw ResolveError.rootNotFound(filePath: #filePath)
        }
        url.deleteLastPathComponent()
        return url
    }
}
