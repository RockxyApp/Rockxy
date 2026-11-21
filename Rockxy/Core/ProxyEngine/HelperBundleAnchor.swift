import Foundation

// MARK: - HelperBundleAnchor

/// Whether the running copy of Rockxy sits somewhere that can anchor a helper registration.
///
/// `SMAppService` records the registering bundle in macOS's Background Task Management
/// database and stores the helper's program as a path *relative to that bundle*
/// (`Contents/Library/HelperTools/RockxyHelperTool`). When that bundle later disappears,
/// launchd can no longer resolve the program: it logs
/// `copy_bundle_path(<record uuid>) error 0x6f — Invalid or missing Program/ProgramArguments`
/// and the job spawn-fails with `EX_CONFIG` on every retry, indefinitely.
///
/// Nothing inside Rockxy can clear that record afterwards. Re-registering reuses it,
/// uninstalling cannot reach it, and deleting and reinstalling the app does not remove it —
/// the record outlives the bundle that created it, which is exactly how it became stale.
/// The only way out is a macOS-level reset of the whole database.
///
/// So a registration from a disappearing location has to be refused *before* it is made.
enum HelperBundleAnchor: Equatable, Sendable {
    /// A location that stays put, so the record it creates keeps resolving.
    case stable
    /// macOS is running a read-only copy from a randomised path because the app was opened
    /// under quarantine, typically straight out of Downloads. That copy is discarded when
    /// the app quits, taking the registration's anchor with it.
    case translocated
    /// A mounted volume: the disk image the app was downloaded in, or an external disk.
    /// Ejecting it strands the registration.
    case mountedVolume

    // MARK: Internal

    /// App Translocation runs the app from a randomised directory under this path component.
    nonisolated static let translocationPathComponent = "/AppTranslocation/"

    nonisolated static var current: HelperBundleAnchor {
        anchor(forBundlePath: Bundle.main.bundlePath)
    }

    var canAnchorRegistration: Bool {
        self == .stable
    }

    /// What the user has to do, naming the move rather than the macOS mechanism behind it.
    /// Both cases end in the same place: a copy in Applications, opened from there.
    var refusalMessage: String {
        switch self {
        case .stable:
            ""
        case .translocated:
            String(
                localized: """
                Rockxy cannot install its helper tool while macOS is running it from a temporary copy. \
                That happens when Rockxy is opened from Downloads. Move Rockxy to your Applications \
                folder, open it from there, and install the helper again.
                """,
                bundle: RockxyLocalization.bundle
            )
        case .mountedVolume:
            String(
                localized: """
                Rockxy cannot install its helper tool while it is running from a disk image or an \
                external disk, because ejecting that disk would leave the helper permanently \
                unusable. Drag Rockxy to your Applications folder, open it from there, and install \
                the helper again.
                """,
                bundle: RockxyLocalization.bundle
            )
        }
    }

    /// Pure mapping from a bundle path, so every case is testable without moving the app.
    nonisolated static func anchor(forBundlePath path: String) -> HelperBundleAnchor {
        if path.contains(translocationPathComponent) {
            return .translocated
        }
        // The startup disk is reached as `/`, so an app installed the normal way is never under
        // `/Volumes`. A copy that is means a disk image, a network share or an external disk —
        // each of which the user can detach while Rockxy is still registered against it.
        if path == "/Volumes" || path.hasPrefix("/Volumes/") {
            return .mountedVolume
        }
        return .stable
    }
}
