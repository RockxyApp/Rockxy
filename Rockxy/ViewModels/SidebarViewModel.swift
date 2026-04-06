import Foundation
import os

/// View model for sidebar state management (search text, selection).
/// Currently lightweight; sidebar logic is primarily driven by `MainContentCoordinator`.
@MainActor @Observable
final class SidebarViewModel {
    // MARK: Internal

    var searchText = ""
    var selectedItem: SidebarItem?

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "SidebarViewModel")
}
