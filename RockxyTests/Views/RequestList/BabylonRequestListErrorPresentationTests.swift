import AppKit
@testable import Rockxy
import SwiftUI
import Testing

@MainActor
struct BabylonRequestListErrorPresentationTests {
    // MARK: Internal

    @Test("Request list status dot exposes the captured Babylon error")
    func statusDotShowsBabylonCapturedError() throws {
        #expect(statusDotTooltip(metadata: nil) == nil)
        let metadata = BabylonCaptureMetadata(
            identity: BabylonCaptureIdentity(
                clientID: "client",
                sessionID: "transport",
                projectName: "Example",
                bundleIdentifier: "com.example.app",
                deviceName: "iPhone",
                deviceModel: "iPhone 17"
            ),
            capabilities: nil,
            correlation: nil,
            error: .init(code: -1_000, message: "TLS handshake failed", domain: "NSURLErrorDomain", phase: nil),
            compatibilityDiagnostics: []
        )
        let tooltip = try #require(statusDotTooltip(metadata: metadata))
        #expect(tooltip == "NSURLErrorDomain · -1000: TLS handshake failed")

        var metadataWithoutCode = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(metadata)) as? [String: Any]
        )
        metadataWithoutCode.removeValue(forKey: "errorCode")
        metadataWithoutCode["errorDomain"] = nil
        metadataWithoutCode["failurePhase"] = "response"
        let decodedWithoutCode = try JSONDecoder().decode(
            BabylonCaptureMetadata.self,
            from: JSONSerialization.data(withJSONObject: metadataWithoutCode)
        )
        #expect(statusDotTooltip(metadata: decodedWithoutCode) == "response: TLS handshake failed")

        metadataWithoutCode.removeValue(forKey: "failurePhase")
        let messageOnly = try JSONDecoder().decode(
            BabylonCaptureMetadata.self,
            from: JSONSerialization.data(withJSONObject: metadataWithoutCode)
        )
        #expect(statusDotTooltip(metadata: messageOnly) == "TLS handshake failed")

        metadataWithoutCode.removeValue(forKey: "errorMessage")
        metadataWithoutCode["failurePhase"] = "response"
        let phaseOnly = try JSONDecoder().decode(
            BabylonCaptureMetadata.self,
            from: JSONSerialization.data(withJSONObject: metadataWithoutCode)
        )
        #expect(statusDotTooltip(metadata: phaseOnly) == "response")
    }

    // MARK: Private

    private func statusDotTooltip(metadata: BabylonCaptureMetadata?) -> String? {
        let transaction = TestFixtures.makeTransaction(state: .failed)
        transaction.babylonCaptureMetadata = metadata
        let row = RequestListRow(from: transaction)
        let parent = RequestTableView(
            workspaceID: UUID(),
            rows: [row],
            refreshToken: 0,
            isAppendOnly: false,
            selectedIDs: .constant([])
        )
        let coordinator = RequestTableView.Coordinator(parent: parent)
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 480, height: 28))
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status")))
        coordinator.tableView = table

        guard let cell = coordinator.tableView(table, viewFor: table.tableColumns[0], row: 0) else {
            return nil
        }
        return cell.toolTip
    }
}
