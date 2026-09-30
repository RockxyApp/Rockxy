import Foundation
@testable import Rockxy
import Testing

/// `SizeFormatter` is the single implementation behind every captured byte count Rockxy shows, so
/// the same number must read identically in the request list, the inspectors, the Context Dock,
/// the status bar, and the assistant's evidence. Surfaces that reached for `ByteCountFormatter`'s
/// decimal `.file` style rendered 999,999 bytes as "1 MB" next to the shared formatter's "977 KB".
///
/// Assertions here stay locale-independent: `ByteCountFormatter` uses the host's decimal
/// separator, so the expected values are derived rather than spelled out.
struct SizeFormatterTests {
    // MARK: Internal

    @Test("Captured byte counts are formatted in binary units, not decimal ones")
    func sharedFormatterUsesBinaryUnits() {
        let binary = ByteCountFormatter()
        binary.countStyle = .binary
        binary.allowsNonnumericFormatting = false
        let decimal = ByteCountFormatter()
        decimal.countStyle = .file

        for bytes in Self.divergentSamples {
            #expect(SizeFormatter.format(bytes: bytes) == binary.string(fromByteCount: Int64(bytes)))
            // Each sample is one where the two styles disagree, which is what made the same
            // payload read two different ways across surfaces.
            #expect(SizeFormatter.format(bytes: bytes) != decimal.string(fromByteCount: Int64(bytes)))
        }
    }

    @Test("An empty body reads as a number, not as \"Zero KB\"")
    func emptyBodiesRenderNumerically() {
        // The Context Dock's Payload rows and an empty WebSocket frame both reach the formatter
        // with 0, where `ByteCountFormatter`'s non-numeric spelling reads "Zero KB" beside its own
        // "1 byte" and "512 bytes".
        let numeric = ByteCountFormatter()
        numeric.countStyle = .binary
        numeric.allowsNonnumericFormatting = false
        let nonNumeric = ByteCountFormatter()
        nonNumeric.countStyle = .binary

        #expect(SizeFormatter.format(bytes: 0) == numeric.string(fromByteCount: 0))
        #expect(SizeFormatter.format(bytes: 0) != nonNumeric.string(fromByteCount: 0))
    }

    @Test("The Int and Int64 overloads never disagree")
    func overloadsAgree() {
        // Transferred totals and the footer's session total are Int64; body sizes are Int. The
        // Int64 overload exists so neither side has to cast at the call site and drift apart.
        for bytes in Self.divergentSamples + [0, 1, 512, 4_096] {
            #expect(SizeFormatter.format(bytes: bytes) == SizeFormatter.format(bytes: Int64(bytes)))
        }
    }

    @Test("Only download and on-disk sizes build their own ByteCountFormatter")
    func capturedTrafficSurfacesUseTheSharedFormatter() throws {
        // A surface that builds its own formatter picks its own unit system. Download progress,
        // installed model sizes, and file-picker sizes keep the decimal `.file` style on purpose
        // because that is what Finder shows; captured traffic must not.
        // Matched against code only: `DecimalFormatter` and `DurationFormatter` name
        // `ByteCountFormatter` in their doc comments precisely because it is the surface their own
        // separator has to agree with.
        let offenders = try Self.projectSources()
            .filter { !Self.formatterOwners.contains($0.path) && Self.callsByteCountFormatter($0.source) }
            .map(\.path)
        #expect(
            offenders.isEmpty,
            "These files format byte counts themselves instead of using SizeFormatter: \(offenders.sorted())"
        )
    }

    @Test("Durations are not re-derived with a hand-rolled time format")
    func durationSurfacesUseTheSharedFormatter() throws {
        // The gRPC inspector printed "90000 ms" for a stream the request list called "1m 30s", and
        // the Diff candidate table printed "923ms" without a space. Both were private copies.
        var offenders: [String] = []
        for (path, source) in try Self.projectSources() where !Self.durationFormatOwners.contains(path) {
            let literals = Self.formatLiterals(in: source).filter(Self.looksLikeATimeFormat)
            offenders.append(contentsOf: literals.map { "\(path): \($0)" })
        }
        #expect(
            offenders.isEmpty,
            "These files format durations themselves instead of using DurationFormatter: \(offenders.sorted())"
        )
    }

    @Test("Captured byte counts are never spelled out by string interpolation")
    func capturedTrafficSurfacesDoNotInterpolateByteCounts() throws {
        // `ByteCountFormatter` and `String(format:)` are not the only ways to drift. The Synopsis
        // inspector wrote its response size as "\\(body.count) bytes", so the same body read
        // "3070 bytes" there and "3 KB" in the request list, the Context Dock, and the AI tab —
        // ungrouped, in a fixed unit, and with an English "bytes" that never reached the catalog.
        var offenders: [String] = []
        for (path, source) in try Self.projectSources() where !Self.interpolatedSizeOwners.contains(path) {
            let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() {
                // The formatter wraps long log calls, so the `logger.warning(` that owns a literal
                // can sit two lines above it.
                let statement = lines[max(0, index - 2) ... index].joined(separator: " ")
                guard Self.interpolatesAByteCount(String(line), statement: statement) else {
                    continue
                }
                offenders.append("\(path): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(
            offenders.isEmpty,
            "These lines build a byte count by interpolation instead of using SizeFormatter: \(offenders.sorted())"
        )
    }

    // MARK: Private

    private enum ResolveError: Error {
        case rootNotFound(filePath: String)
    }

    /// Byte counts where `.binary` and `.file` disagree, so the assertions pin the unit system
    /// rather than an exact localized spelling.
    private static let divergentSamples = [1_000, 1_500, 999_999, 1_500_000, 12_345_678]

    /// The shared formatter plus the surfaces that legitimately show Finder-style decimal sizes:
    /// runtime and model downloads, software updates, the import file picker, and the Gist size
    /// limits, whose prose names its own "10 MB"/"25 MB" thresholds.
    private static let formatterOwners: Set<String> = [
        "Rockxy/Core/Utilities/SizeFormatter.swift",
        "Rockxy/Core/Assistant/AssistantLocalRuntimeInstaller.swift",
        "Rockxy/Core/Assistant/OllamaModelInstaller.swift",
        "Rockxy/Core/Plugins/BuiltInPlugins/GistPublishPayloadBuilder.swift",
        "Rockxy/Views/Import/ImportReviewSheet.swift",
        "Rockxy/Views/Settings/AssistantInstalledModelDetailFormatter.swift",
        "Rockxy/Views/Settings/AssistantRuntimeSetupSheet.swift",
        // Recommended unified memory for a local model — a RAM amount in the `.memory` style,
        // not a captured payload.
        "Rockxy/Views/Settings/AssistantSettingsTab.swift",
        "Rockxy/Views/Updates/SoftwareUpdatePanelView.swift",
    ]

    /// `DurationFormatter` is the only owner. The diff text and the waterfall's axis ticks still hold
    /// a duration to one fixed unit, but they spell it through `DecimalFormatter` now.
    private static let durationFormatOwners: Set<String> = [
        "Rockxy/Core/Utilities/DurationFormatter.swift",
    ]

    /// A `String(format:)` literal whose trailing unit is a time unit — "%.0fms", "%.2f s",
    /// "%.0f µs" — is a duration being formatted by hand.
    private static let timeFormatPattern = try? NSRegularExpression(
        pattern: "%[0-9.']*[fdl]+ ?(µs|ms|s)$"
    )

    /// The gRPC inspector's "Truncated · N/M bytes" is a ratio: both sides must stay exact and in
    /// one unit so the reader can compare them, so it keeps its raw counts on purpose.
    /// `ScriptResponseBodyLoader.LoadError` is built for the log only — `ScriptMultiArgBridge`
    /// catches it, writes it to `logger.warning`, and falls through to the inline body. Its exact
    /// cap in bytes is the useful thing to record there, and no user ever reads it.
    /// `CodeSnippetGenerator` writes a comment into generated source code; an exact byte count is
    /// what a developer pasting that code needs, and it is never localized.
    /// `CodeSnippetGenerator+MoreLanguages` does the same for more languages, and
    /// `PostmanCollectionExporter` notes an omitted binary body inside the exported collection.
    private static let interpolatedSizeOwners: Set<String> = [
        "Rockxy/Core/Utilities/CodeSnippetGenerator.swift",
        "Rockxy/Core/Utilities/CodeSnippetGenerator+MoreLanguages.swift",
        "Rockxy/Core/Plugins/BuiltInPlugins/PostmanCollectionExporter.swift",
        "Rockxy/Core/Plugins/ScriptResponseBodyLoader.swift",
        "Rockxy/Views/Inspector/GRPCInspectorView.swift",
    ]

    /// A byte unit sitting directly after a Swift interpolation is a hand-built size.
    private static let interpolatedSizePattern = try? NSRegularExpression(
        pattern: #"\\\([^)]*\) ?(bytes|byte|KB|MB|GB)"#
    )

    /// Log statements are diagnostic, never shown to anyone, so an exact byte count is the useful
    /// thing to record there.
    private static let loggingCalls = ["logger.", ".debug(", ".info(", ".notice(", ".warning(", ".error(", ".critical("]

    private static func interpolatesAByteCount(_ line: String, statement: String) -> Bool {
        guard let interpolatedSizePattern else {
            return false
        }
        guard !loggingCalls.contains(where: statement.contains) else {
            return false
        }
        // An inflected catalog key (`^[\(n) byte](inflect: true)`) is the project's own shape for
        // a count that must stay exact inside a translated sentence; it is localized and grouped.
        guard !line.contains("inflect: true") else {
            return false
        }
        let range = NSRange(line.startIndex ..< line.endIndex, in: line)
        return interpolatedSizePattern.firstMatch(in: line, range: range) != nil
    }

    /// A doc comment that names `ByteCountFormatter` is not a call site.
    private static func callsByteCountFormatter(_ source: String) -> Bool {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .contains { line in
                !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") && line.contains("ByteCountFormatter")
            }
    }

    private static func projectSources() throws -> [(path: String, source: String)] {
        let root = try resolveProjectRoot().appendingPathComponent("Rockxy")
        let prefix = root.deletingLastPathComponent().path + "/"
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        var sources: [(path: String, source: String)] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else {
                continue
            }
            let resolved = url.resolvingSymlinksInPath().path
            let path = resolved.hasPrefix(prefix) ? String(resolved.dropFirst(prefix.count)) : resolved
            try sources.append((path, String(contentsOf: url, encoding: .utf8)))
        }
        return sources
    }

    /// Extracts each `String(format: "…")` literal, stopping at the closing quote so a later
    /// word ending in "s" cannot be mistaken for a unit.
    private static func formatLiterals(in source: String) -> [String] {
        let marker = "String(format: \""
        var literals: [String] = []
        var searchRange = source.startIndex ..< source.endIndex
        while let start = source.range(of: marker, range: searchRange) {
            var index = start.upperBound
            var literal = ""
            while index < source.endIndex, source[index] != "\"" {
                // A backslash escape cannot end the literal.
                if source[index] == "\\", source.index(after: index) < source.endIndex {
                    literal.append(source[index])
                    index = source.index(after: index)
                }
                literal.append(source[index])
                index = source.index(after: index)
            }
            literals.append(literal)
            searchRange = index ..< source.endIndex
        }
        return literals
    }

    private static func looksLikeATimeFormat(_ literal: String) -> Bool {
        guard let timeFormatPattern else {
            return false
        }
        let range = NSRange(literal.startIndex ..< literal.endIndex, in: literal)
        return timeFormatPattern.firstMatch(in: literal, range: range) != nil
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
