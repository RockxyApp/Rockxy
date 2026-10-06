import AppKit
import Observation

// MARK: - RecentCaptureDocuments

/// Sessions and HAR files the user opened or saved, for File ▸ Open Recent. Backed by the
/// system recent-documents list, so the Dock menu shows the same files.
@MainActor @Observable
final class RecentCaptureDocuments {
    // MARK: Lifecycle

    init(controller: NSDocumentController = .shared) {
        self.controller = controller
        urls = Self.supported(controller.recentDocumentURLs)
    }

    // MARK: Internal

    static let shared = RecentCaptureDocuments()

    private(set) var urls: [URL]

    func note(_ url: URL) {
        guard ExternalCaptureDocumentKind(url: url) != nil else {
            return
        }
        controller.noteNewRecentDocumentURL(url)
        urls = Self.supported(controller.recentDocumentURLs)
    }

    func clear() {
        controller.clearRecentDocuments(nil)
        urls = []
    }

    /// Drops entries whose file has since been moved or deleted.
    func refresh() {
        urls = Self.supported(controller.recentDocumentURLs)
    }

    // MARK: Private

    private let controller: NSDocumentController

    private static func supported(_ urls: [URL]) -> [URL] {
        urls.filter { url in
            ExternalCaptureDocumentKind(url: url) != nil && FileManager.default.fileExists(atPath: url.path)
        }
    }
}
