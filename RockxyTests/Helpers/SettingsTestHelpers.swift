import Darwin
import Foundation
@testable import Rockxy

/// All UserDefaults keys written by AppSettingsStorage.
let appSettingsKeys = TestIdentity.appSettingsKeys

/// Shared lock ensuring tests that mutate AppSettings UserDefaults keys do not race.
let settingsTestLock = NSLock()

private final class CrossProcessSettingsLock {
    init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    deinit {
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }

    private let fileDescriptor: Int32
}

private func acquireCrossProcessSettingsLock() throws -> CrossProcessSettingsLock {
    let lockURL = URL(fileURLWithPath: "/tmp/rockxy-settings-tests.lock", isDirectory: false)
    let fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard fd >= 0 else {
        throw CocoaError(.fileReadUnknown)
    }
    guard flock(fd, LOCK_EX) == 0 else {
        close(fd)
        throw CocoaError(.fileReadUnknown)
    }
    return CrossProcessSettingsLock(fileDescriptor: fd)
}

/// Captures current UserDefaults values for the provided keys, acquires the shared lock,
/// and returns a cleanup closure that restores originals and unlocks.
func installUserDefaultsGuard(keys: [String]) -> (() -> Void) {
    settingsTestLock.lock()
    let crossProcessLock = try? acquireCrossProcessSettingsLock()
    let defaults = UserDefaults.standard
    let originals = keys.map { ($0, defaults.object(forKey: $0)) }

    return {
        for (key, original) in originals {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        _ = crossProcessLock
        settingsTestLock.unlock()
    }
}

/// Captures current UserDefaults values for all AppSettings keys, acquires the shared lock,
/// and returns a cleanup closure that restores originals and unlocks.
func installSettingsTestGuard() -> (() -> Void) {
    installUserDefaultsGuard(keys: appSettingsKeys)
}
