import Foundation

// MARK: - ProxyApplyDebtFileStore

/// Keeps `ProxyApplyDebt` in a small owner-only file beside the proxy backup.
///
/// It is deliberately not part of the backup: the backup is cleared the moment a restore reads as
/// finished, which is exactly when an unconfirmed apply is still owed.
struct ProxyApplyDebtFileStore: ProxyApplyDebtStore {
    // MARK: Lifecycle

    init(url: URL = Self.defaultURL) {
        self.url = url
    }

    // MARK: Internal

    static let defaultURL = RockxyIdentity.current.sharedSupportDirectory()
        .appendingPathComponent("proxy-apply-owed.json")

    func load() -> ProxyApplyDebtState {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .none
        }
        guard let data = try? Data(contentsOf: url),
              let debt = try? JSONDecoder().decode(ProxyApplyDebt.self, from: data) else
        {
            return .unreadable
        }
        return .owed(debt)
    }

    func save(_ debt: ProxyApplyDebt) throws {
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: ProxyBackupFilePublication.ownerOnlyDirectoryPermissions]
            )
        }
        try ProxyBackupFilePublication.publish(JSONEncoder().encode(debt), to: url)
    }

    func clear(ifID id: String?) throws {
        if let id {
            guard case let .owed(current) = load(), current.id == id else {
                // Already gone, or replaced by a newer transaction's debt that is not ours to clear.
                if case .none = load() {
                    return
                }
                if case .unreadable = load() {
                    try remove()
                }
                return
            }
        }
        try remove()
    }

    // MARK: Private

    private let url: URL

    private func remove() throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            return
        }
    }
}
