enum ProxyBackupRecoveryAction: Equatable {
    case restore
    case preserve
    case clear
}

/// Decides backup lifetime from live ownership instead of elapsed wall-clock time.
/// A healthy listener means the capture session still owns the override; an unreachable
/// listener means the owned override was stranded and must be restored immediately.
enum ProxyBackupRecoveryPolicy {
    static func action(
        proxyStillPointsAtRockxy: Bool,
        listenerIsReachable: Bool
    ) -> ProxyBackupRecoveryAction {
        guard proxyStillPointsAtRockxy else {
            return .clear
        }
        return listenerIsReachable ? .preserve : .restore
    }
}
