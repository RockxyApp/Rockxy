import Darwin
import Foundation
import os

// Out-of-process restoration for developer-application settings transactions, plus the bounded
// durable marker that keeps one monitor per transaction across Rockxy relaunches.

nonisolated private let developerApplicationMonitorLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "DeveloperApplicationRestorationMonitor"
)

// MARK: - DeveloperApplicationSettingsRestorationMonitoring

@MainActor
protocol DeveloperApplicationSettingsRestorationMonitoring {
    func startMonitoring(
        processIdentifier: Int32,
        preparation: DeveloperApplicationSettingsPreparation
    )
        throws
}

// MARK: - DeveloperApplicationRestorationMonitorMarker

/// Durable evidence that one restoration monitor already owns a settings transaction.
struct DeveloperApplicationRestorationMonitorMarker: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let monitorProcessIdentifier: Int32
    let monitorStartSignature: String
    let monitoredProcessIdentifier: Int32
}

// MARK: - DeveloperApplicationRestorationMonitorLedger

/// Prevents an orphaned but still valid monitor from being multiplied on every Rockxy relaunch.
/// Reuse requires exact process identity: the recorded monitor process must still be alive with
/// the same start signature and must still watch the same application process. Anything weaker —
/// a missing, corrupt, stale, or differently targeted marker — starts a fresh monitor, so a
/// damaged marker can never cost the user their recovery transaction.
enum DeveloperApplicationRestorationMonitorLedger {
    nonisolated static let schemaVersion = 1
    nonisolated static let maximumMarkerBytes: UInt64 = 4_096

    static func markerURL(for recoveryRecordURL: URL) -> URL {
        recoveryRecordURL.deletingPathExtension().appendingPathExtension("monitor")
    }

    /// Pure decision seam shared by production and tests.
    static func shouldStartMonitor(
        marker: DeveloperApplicationRestorationMonitorMarker?,
        monitoredProcessIdentifier: Int32,
        monitorIsAlive: (Int32, String) -> Bool
    )
        -> Bool
    {
        guard let marker,
              marker.schemaVersion == schemaVersion,
              marker.monitorProcessIdentifier > 0,
              marker.monitoredProcessIdentifier == monitoredProcessIdentifier,
              !marker.monitorStartSignature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              monitorIsAlive(marker.monitorProcessIdentifier, marker.monitorStartSignature) else
        {
            return true
        }
        return false
    }

    static func shouldStartMonitor(
        markerURL: URL,
        monitoredProcessIdentifier: Int32,
        fileManager: FileManager = .default,
        monitorIsAlive: (Int32, String) -> Bool = { processIdentifier, startSignature in
            DeveloperApplicationRecoveryLedger.isRecordedProcessAlive(
                processIdentifier: processIdentifier,
                expectedStartSignature: startSignature
            )
        }
    )
        -> Bool
    {
        shouldStartMonitor(
            marker: marker(at: markerURL, fileManager: fileManager),
            monitoredProcessIdentifier: monitoredProcessIdentifier,
            monitorIsAlive: monitorIsAlive
        )
    }

    /// Reads a bounded marker. Oversized, unreadable, or malformed markers read as absent.
    static func marker(
        at markerURL: URL,
        fileManager: FileManager = .default
    )
        -> DeveloperApplicationRestorationMonitorMarker?
    {
        guard fileManager.fileExists(atPath: markerURL.path),
              let size = try? DeveloperApplicationCaptureConfigurator.fileSize(
                  at: markerURL,
                  fileManager: fileManager
              ),
              size <= maximumMarkerBytes,
              let data = try? Data(contentsOf: markerURL, options: [.mappedIfSafe]) else
        {
            return nil
        }
        return try? JSONDecoder().decode(
            DeveloperApplicationRestorationMonitorMarker.self,
            from: data
        )
    }

    static func writeMarker(
        monitorProcessIdentifier: Int32,
        monitorStartSignature: String,
        monitoredProcessIdentifier: Int32,
        to markerURL: URL,
        fileManager: FileManager = .default
    )
        throws
    {
        let marker = DeveloperApplicationRestorationMonitorMarker(
            schemaVersion: schemaVersion,
            monitorProcessIdentifier: monitorProcessIdentifier,
            monitorStartSignature: monitorStartSignature,
            monitoredProcessIdentifier: monitoredProcessIdentifier
        )
        try JSONEncoder().encode(marker).write(to: markerURL, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: markerURL.path)
    }

    static func removeMarker(for recoveryRecordURL: URL, fileManager: FileManager = .default) {
        let url = markerURL(for: recoveryRecordURL)
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try? fileManager.removeItem(at: url)
    }
}

// MARK: - DeveloperApplicationSettingsRestorationMonitor

/// Runs a bounded, exact-path restoration monitor outside Rockxy's process. This closes the gap
/// where Rockxy exits before the prepared application. The monitor restores only when the live
/// settings still match Rockxy's prepared snapshot, so user edits made during the session win.
///
/// The monitor is also restart-aware. An application that replaces itself in place — a self
/// update or an internal restart — leaves a successor process running from the exact same
/// application bundle. Restoring underneath that successor would silently strip the proxy
/// settings the user asked Rockxy to prepare, so the monitor stands down and leaves the durable
/// transaction to Rockxy's semantic reconciler instead.
///
/// Ownership is deliberate: the in-process termination callback decides first with a short
/// window, and this monitor only acts after a strictly longer window, by which time the
/// callback's decision is already visible on disk as a removed snapshot or a rebound record.
@MainActor
final class DeveloperApplicationSettingsRestorationMonitor: DeveloperApplicationSettingsRestorationMonitoring {
    // MARK: Internal

    static let shared = DeveloperApplicationSettingsRestorationMonitor()

    /// One scan per second, long enough to outlast the in-process successor window.
    nonisolated static let successorScanAttempts = 12

    nonisolated static let script = """
    remaining=120960
    ps_command=${7:-/bin/ps}
    bundle_path=$8
    successor_attempts=${9:-12}
    started=$("$ps_command" -p "$1" -o lstart= 2>/dev/null)
    if [ -z "$started" ] && /bin/kill -0 "$1" 2>/dev/null; then
      # An unavailable identity is not proof that the process exited. Leave the durable
      # transaction for Rockxy's semantic reconciler instead of restoring prematurely.
      exit 0
    fi
    successor_present() {
      "$ps_command" -A -ww -o pid= -o comm= 2>/dev/null | /usr/bin/awk -v monitored="$1" -v prefix="$2" '
        {
          candidate = $1
          sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "")
          if (candidate != monitored && index($0, prefix) == 1) { found = 1; exit }
        }
        END { exit(found ? 0 : 1) }
      '
    }
    identity_changed=0
    while /bin/kill -0 "$1" 2>/dev/null && [ "$remaining" -gt 0 ]; do
      current=$("$ps_command" -p "$1" -o lstart= 2>/dev/null)
      if [ -z "$current" ]; then
        /bin/sleep 5
        remaining=$((remaining - 1))
        continue
      fi
      if [ "$current" != "$started" ]; then
        identity_changed=1
        break
      fi
      /bin/sleep 5
      remaining=$((remaining - 1))
    done
    current=$("$ps_command" -p "$1" -o lstart= 2>/dev/null)
    if /bin/kill -0 "$1" 2>/dev/null; then
      if [ "$identity_changed" -eq 0 ] || [ -z "$current" ] || [ "$current" = "$started" ]; then
        exit 0
      fi
    fi
    settings=$2
    backup=$3
    absent=$4
    prepared=$5
    recovery_record=$6
    monitor_marker="${recovery_record%.json}.monitor"
    if [ ! -f "$prepared" ]; then
      /bin/rm -f "$monitor_marker"
      exit 0
    fi
    # An in-place restart or self update leaves a successor executing from the exact same
    # application bundle. Identity is that executable path, never a process name.
    if [ -n "$bundle_path" ]; then
      attempts=$successor_attempts
      while [ "$attempts" -gt 0 ]; do
        if successor_present "$1" "$bundle_path/Contents/MacOS/"; then
          exit 0
        fi
        attempts=$((attempts - 1))
        if [ "$attempts" -gt 0 ]; then
          /bin/sleep 1
        fi
      done
    fi
    if [ ! -f "$settings" ] || ! /usr/bin/cmp -s "$settings" "$prepared"; then
      # A byte-level mismatch may be an application rewrite that preserved Rockxy's proxy
      # selector while changing unrelated settings. Keep the recovery transaction for Rockxy's
      # semantic reconciler instead of deleting the user's original configuration.
      exit 0
    fi
    if [ -f "$absent" ]; then
      /bin/rm -f "$settings" "$backup" "$absent" "$prepared" "$recovery_record" "$monitor_marker"
    elif [ -f "$backup" ]; then
      /bin/mv -f "$backup" "$settings"
      /bin/rm -f "$absent" "$prepared" "$recovery_record" "$monitor_marker"
    else
      # Never discard the ledger when the original recovery artifact is missing.
      # Rockxy's semantic reconciler may still diagnose or repair this transaction.
      exit 0
    fi
    """

    func startMonitoring(
        processIdentifier: Int32,
        preparation: DeveloperApplicationSettingsPreparation
    )
        throws
    {
        let markerURL = DeveloperApplicationRestorationMonitorLedger.markerURL(
            for: preparation.recoveryRecordURL
        )
        guard DeveloperApplicationRestorationMonitorLedger.shouldStartMonitor(
            markerURL: markerURL,
            monitoredProcessIdentifier: processIdentifier
        ) else {
            // A live monitor already owns this transaction. Starting another one would add a
            // duplicate on every Rockxy relaunch without improving recovery.
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            Self.script,
            "rockxy-settings-restoration-monitor",
            String(processIdentifier),
            preparation.settingsURL.path,
            preparation.backupURL.path,
            preparation.absenceMarkerURL.path,
            preparation.preparedSnapshotURL.path,
            preparation.recoveryRecordURL.path,
            "/bin/ps",
            preparation.applicationBundlePath ?? "",
            String(Self.successorScanAttempts),
        ]
        process.environment = ["PATH": "/usr/bin:/bin"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        recordMarker(
            monitorProcessIdentifier: process.processIdentifier,
            monitoredProcessIdentifier: processIdentifier,
            markerURL: markerURL
        )
    }

    // MARK: Private

    private func recordMarker(
        monitorProcessIdentifier: Int32,
        monitoredProcessIdentifier: Int32,
        markerURL: URL
    ) {
        guard let startSignature = DeveloperApplicationRecoveryLedger.processStartSignature(
            processIdentifier: monitorProcessIdentifier
        ) else {
            // A monitor whose identity cannot be proven is never recorded as the owner, so the
            // next Rockxy launch starts a fresh monitor rather than trusting a bare identifier.
            return
        }
        do {
            try DeveloperApplicationRestorationMonitorLedger.writeMarker(
                monitorProcessIdentifier: monitorProcessIdentifier,
                monitorStartSignature: startSignature,
                monitoredProcessIdentifier: monitoredProcessIdentifier,
                to: markerURL
            )
        } catch {
            developerApplicationMonitorLogger.error(
                "Could not record the developer-application restoration monitor marker: \(error.localizedDescription)"
            )
        }
    }
}
