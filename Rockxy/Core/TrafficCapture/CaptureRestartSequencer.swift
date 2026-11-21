/// Restart follows actual shutdown completion, including slow system-proxy restoration.
/// Recheck state after the suspension: a restore failure or another Start must prevent
/// a duplicate listener. The caller's UI executor remains available while Stop is pending.
enum CaptureRestartSequencer {
    @MainActor
    static func restart(
        after stop: @MainActor () async -> Void,
        canStart: @MainActor () -> Bool,
        start: @MainActor () -> Void
    )
        async
    {
        await stop()
        guard canStart() else {
            return
        }
        start()
    }
}
