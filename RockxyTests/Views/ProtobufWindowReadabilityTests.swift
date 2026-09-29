import Foundation
@testable import Rockxy
import Testing

// MARK: - ProtobufWindowReadabilityTests

/// Source-level contracts for the redesigned Protobuf mapping and local-schema tool windows.
/// These assert truthful copy about where schemas apply, native adaptive surfaces, honest action
/// routing, and the absence of the old dead controls, fake console, and pinned legacy frames.
@MainActor
struct ProtobufWindowReadabilityTests {
    // MARK: Internal

    @Test("Protobuf windows use the approved native structure and describe where schemas apply")
    func protobufWindowsUseApprovedNativeStructure() throws {
        let mapping = try readProjectFile("Rockxy/Views/Rules/ProtobufSettingsWindowView.swift")
        let schema = try readProjectFile("Rockxy/Views/Rules/ProtobufSchemaListWindowView.swift")
        let grpc = try readProjectFile("Rockxy/Views/Inspector/GRPCInspectorView.swift")
        let app = try readProjectFile("Rockxy/RockxyApp.swift")

        for source in [mapping, schema] {
            require(source, [
                "ProtobufLocalOnlyNotice", "ContentUnavailableView", "Color(nsColor: .textBackgroundColor)",
                "RoundedRectangle(cornerRadius: 6)", ".stroke(Color(nsColor: .separatorColor), lineWidth: 1)",
                ".padding(.vertical, toolMetrics.footerTopPadding)", "minWidth: max(", "minHeight: max(",
            ])
        }

        require(mapping, [
            "open in the Protobuf tab decoded as its", "stored locally",
            "minWidth: max(860, toolMetrics.bodyFontSize * 28 + 496)", "runtimeStatus(for: rule)",
            "Type not found", "messageTypeMenu(",
            "focused($focusedField", "inlineError", "footerButtonLabel", ".keyboardShortcut(.cancelAction)",
            ".keyboardShortcut(.defaultAction)", "withEditedFields", "Missing Schema", "ViewThatFits",
            ".accessibilityLabel(String(localized: \"HTTP method\", bundle: RockxyLocalization.bundle))",
            ".accessibilityLabel(String(localized: \"Match type\", bundle: RockxyLocalization.bundle))",
            ".accessibilityLabel(String(localized: \"Local schema\", bundle: RockxyLocalization.bundle))",
            ".accessibilityLabel(String(localized: \"Payload encoding\", bundle: RockxyLocalization.bundle))",
        ])
        forbid(mapping, [
            ".frame(width: 1_240, height: 660)", "Test your Rule", "questionmark.circle",
            ".keyboardShortcut(.space, modifiers: [])", ".onDeleteCommand",
        ])

        require(schema, [
            "Rockxy uses them to name fields", "minWidth: max(760,", "minHeight: max(520,",
            "importAvailability", "policyUnavailable", "limitReached", "storageUnavailable",
            "ProtobufDescriptorSetParser.fileExtensions", "ProtobufSchemaSourceValidator.loadValidatedSource",
            "schemaStore.messageNames(for: schema)",
            "Schema Import Unavailable", "Schema Limit Reached", "Schema Storage Unavailable",
            "No Local Schemas", "Local schema import is unavailable", #"Click \"+\" or press ⌘N to import"#,
            ".confirmationDialog(", "referenceCount(forSchema:", "detachSchema(id:",
        ])
        forbid(schema, [
            ".frame(width: 1_000, height: 860)", "Protobuf Console Log", "Empty Console Log",
            "consoleLines", "appendConsole", "How to get *.proto file",
            "Schema upload unavailable", "rejects schema uploads", "app policy",
        ])

        require(grpc, [
            "ProtobufPayloadInspectorView", "onOpenToolWindow(\"protobufSettings\")",
            "onOpenToolWindow(\"protobufSchemaList\")", "Wire-format heuristic", "Schema decoded",
            "field numbers and values are inferred from the wire format",
        ])
        forbid(grpc, [
            "Add Descriptor", "Schema: heuristic fallback", "Schema needed for field names",
            "not applied to gRPC traffic",
        ])
        forbid(mapping, ["not applied to captured traffic", "\"Not applied\""])
        forbid(schema, ["Schema-aware decoding is unavailable", "\"Not applied\""])

        require(app, [".defaultSize(width: 940, height: 620)", ".defaultSize(width: 820, height: 560)"])
    }

    // MARK: Private

    private func require(_ source: String, _ needles: [String]) {
        for needle in needles {
            #expect(source.contains(needle), "missing \(needle)")
        }
    }

    private func forbid(_ source: String, _ needles: [String]) {
        for needle in needles {
            #expect(!source.contains(needle), "kept \(needle)")
        }
    }

    private func readProjectFile(_ relativePath: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        url.deleteLastPathComponent()
        return try String(contentsOf: url.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
