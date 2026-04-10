import Foundation
import os

// Built-in inspector plugin for JSON content. Declares support for JSON
// content type. View rendering is handled by JSONInspectorView in Views/.

// MARK: - JSONInspector

struct JSONInspector: InspectorPlugin {
    // MARK: Internal

    let name = "JSON Inspector"
    let supportedContentTypes: [ContentType] = [.json]

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "JSONInspector"
    )
}
