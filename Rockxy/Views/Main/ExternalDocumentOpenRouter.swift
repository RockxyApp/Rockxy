import AppKit

// Routes capture documents opened from Finder or the Dock to the main workspace.

// MARK: - ExternalDocumentOpenRouter

/// Hands documents opened through the application delegate to the main
/// workspace. Opens that arrive before the workspace is ready are held and
/// delivered once it registers.
@MainActor
final class ExternalDocumentOpenRouter {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = ExternalDocumentOpenRouter()

    /// Reopens the main window when every window was closed. Registered by
    /// the main window content, which owns the SwiftUI `openWindow` action.
    var openMainWindow: (() -> Void)?

    func register(coordinator: MainContentCoordinator) {
        self.coordinator = coordinator
        deliverPendingURLs()
    }

    func open(_ urls: [URL]) {
        let supported = urls.filter { ExternalCaptureDocumentKind(url: $0) != nil }
        guard !supported.isEmpty else {
            return
        }
        pendingURLs = supported
        if RockxyWorkspaceWindowManager.shared.primaryWindow == nil {
            openMainWindow?()
        }
        deliverPendingURLs()
    }

    // MARK: Private

    private weak var coordinator: MainContentCoordinator?
    private var pendingURLs: [URL] = []

    private func deliverPendingURLs() {
        guard let coordinator, !pendingURLs.isEmpty else {
            return
        }
        let urls = pendingURLs
        pendingURLs = []
        RockxyWorkspaceWindowManager.shared.primaryWindow?.makeKeyAndOrderFront(nil)
        coordinator.openExternalDocuments(urls)
    }
}
