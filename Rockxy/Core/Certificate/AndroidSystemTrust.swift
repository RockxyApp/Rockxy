import CryptoKit
import Foundation
import SwiftASN1
import X509

// System-store trust for rooted Android emulators: the certificate file name Android
// expects and the shell scripts that add or remove it until the emulator restarts.

// MARK: - AndroidSystemTrust

enum AndroidSystemTrust {
    /// Emulator directory that holds the certificate and scripts while they run.
    static let workDirectory = "/data/local/tmp/rockxy-ca"
    static let installScriptName = "rockxy-trust.sh"
    static let removeScriptName = "rockxy-untrust.sh"
    static let installedMarker = "ROCKXY_SYSTEM_CA_OK"
    static let removedMarker = "ROCKXY_SYSTEM_CA_REMOVED"
    static let errorMarker = "ROCKXY_ERROR"

    /// Android's store of user-added CAs. Chrome verifies with its own root store and only
    /// adds user-added CAs to it, so a system-store certificate alone is not enough there.
    static let userStoreDirectory = "/data/misc/user/0/cacerts-added"

    /// Mounts a copy of the system CA directory with the certificate added, then binds it
    /// over the Conscrypt APEX directory in zygote and every app process so apps that
    /// trust only system CAs accept it. Nothing is written to the system image; a restart
    /// of the emulator removes it. The certificate is also added to the user CA store for
    /// Chrome, where it stays until `removeScript` runs. Argument: the certificate file name
    /// in `workDirectory`.
    static let installScript = """
    #!/system/bin/sh
    NAME="$1"
    WORK=\(workDirectory)
    SYS=/system/etc/security/cacerts
    APEX=/apex/com.android.conscrypt/cacerts
    USER_CA=\(userStoreDirectory)
    case "$NAME" in *[!0-9a-f.]*|"") echo "\(errorMarker) bad name"; exit 1;; esac
    [ "$(id -u)" = "0" ] || { echo "\(errorMarker) not root"; exit 1; }
    [ -f "$WORK/$NAME" ] || { echo "\(errorMarker) missing certificate"; exit 1; }
    if ! grep -q " $SYS tmpfs " /proc/mounts; then
      STAGE="$WORK/stage"
      rm -rf "$STAGE" && mkdir -p "$STAGE" && chmod 700 "$STAGE" || exit 1
      if [ -d "$APEX" ]; then cp "$APEX"/* "$STAGE"/; else cp "$SYS"/* "$STAGE"/; fi
      mount -t tmpfs tmpfs "$SYS" || { echo "\(errorMarker) mount failed"; exit 1; }
      cp "$STAGE"/* "$SYS"/
      rm -rf "$STAGE"
    fi
    cp "$WORK/$NAME" "$SYS/$NAME" || { echo "\(errorMarker) copy failed"; exit 1; }
    chown root:root "$SYS" "$SYS"/*
    chmod 755 "$SYS"
    chmod 644 "$SYS"/*
    chcon u:object_r:system_file:s0 "$SYS" "$SYS"/* 2>/dev/null
    if [ -d "$APEX" ]; then
      ZYGOTES=" $(pidof zygote zygote64) "
      for ZP in $ZYGOTES; do
        nsenter --mount=/proc/$ZP/ns/mnt -- sh -c "[ -f $APEX/$NAME ] || mount --bind $SYS $APEX"
      done
      ps -A -o PID=,PPID= | {
        while read -r P PP; do
          case "$ZYGOTES" in *" $PP "*)
            nsenter --mount=/proc/$P/ns/mnt -- sh -c "[ -f $APEX/$NAME ] || mount --bind $SYS $APEX" 2>/dev/null &
          ;; esac
        done
        wait
      }
      for ZP in $(pidof zygote zygote64); do
        nsenter --mount=/proc/$ZP/ns/mnt -- ls "$APEX/$NAME" >/dev/null 2>&1 \\
          || { echo "\(errorMarker) not visible to apps"; exit 1; }
      done
    fi
    if [ ! -f "$USER_CA/$NAME" ]; then
      mkdir -p "$USER_CA" && cp "$WORK/$NAME" "$USER_CA/$NAME" \\
        && chown system:system "$USER_CA" "$USER_CA/$NAME" && chmod 755 "$USER_CA" \\
        && chmod 644 "$USER_CA/$NAME" \\
        || { echo "\(errorMarker) user store failed"; exit 1; }
      chcon u:object_r:misc_user_data_file:s0 "$USER_CA" "$USER_CA/$NAME" 2>/dev/null
    fi
    echo \(installedMarker)
    """

    /// Undoes `installScript` in every mount namespace, removes the user-store copy only when
    /// it is byte-identical to the certificate Rockxy added, and deletes the work directory.
    static let removeScript = """
    #!/system/bin/sh
    WORK=\(workDirectory)
    SYS=/system/etc/security/cacerts
    APEX=/apex/com.android.conscrypt/cacerts
    [ "$(id -u)" = "0" ] || { echo "\(errorMarker) not root"; exit 1; }
    ZYGOTES=" $(pidof zygote zygote64) "
    ps -A -o PID=,PPID= | {
      while read -r P PP; do
        case "$ZYGOTES" in *" $P "*|*" $PP "*)
          nsenter --mount=/proc/$P/ns/mnt -- sh -c "grep -q ' $APEX tmpfs ' /proc/mounts && umount $APEX" 2>/dev/null &
        ;; esac
      done
      wait
    }
    if grep -q " $SYS tmpfs " /proc/mounts; then umount "$SYS"; fi
    for CERT in "$WORK"/*.0; do
      [ -f "$CERT" ] || continue
      ADDED=\(userStoreDirectory)/${CERT##*/}
      if [ -f "$ADDED" ] && cmp -s "$CERT" "$ADDED"; then rm -f "$ADDED"; fi
    done
    rm -rf "$WORK"
    echo \(removedMarker)
    """

    /// `<hash>.0`, where hash is OpenSSL's legacy subject-name hash (`x509 -subject_hash_old`):
    /// the first four bytes of the MD5 of the DER subject, read little-endian.
    static func certificateFileName(certificatePEM: String) throws -> String {
        let certificate = try Certificate(pemEncoded: certificatePEM)
        var serializer = DER.Serializer()
        try serializer.serialize(certificate.subject)
        let digest = Array(Insecure.MD5.hash(data: Data(serializer.serializedBytes)))
        let hash = UInt32(digest[0]) | UInt32(digest[1]) << 8 | UInt32(digest[2]) << 16 | UInt32(digest[3]) << 24
        return String(format: "%08x.0", hash)
    }
}
