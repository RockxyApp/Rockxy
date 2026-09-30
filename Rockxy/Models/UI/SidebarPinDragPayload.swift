import Foundation

// Text payload carried when a domain or app row is dragged onto the sidebar's Favorites.

// MARK: - SidebarPinDragPayload

enum SidebarPinDragPayload {
    private static let prefix = "rockxy-sidebar-pin:"

    /// Only domains and apps can be pinned by dragging.
    static func encode(_ item: SidebarItem) -> String? {
        switch item {
        case .domainNode,
             .domainPath,
             .app:
            guard let data = try? JSONEncoder().encode(item) else {
                return nil
            }
            return prefix + data.base64EncodedString()
        default:
            return nil
        }
    }

    static func decode(_ text: String) -> SidebarItem? {
        guard text.hasPrefix(prefix),
              let data = Data(base64Encoded: String(text.dropFirst(prefix.count))),
              let item = try? JSONDecoder().decode(SidebarItem.self, from: data) else
        {
            return nil
        }
        switch item {
        case .domainNode,
             .domainPath,
             .app:
            return item
        default:
            return nil
        }
    }
}
