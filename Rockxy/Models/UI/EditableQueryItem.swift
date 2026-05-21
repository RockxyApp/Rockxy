import Foundation

// Defines the UI model for editable URL query entries.

// MARK: - EditableQueryItem

/// Editable key-value pair for URL query parameters. Used by the Compose window
/// and breakpoint editor for bidirectional query-URL synchronization.
struct EditableQueryItem: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var value: String

    init(id: UUID = UUID(), name: String, value: String) {
        self.id = id
        self.name = name
        self.value = value
    }
}
