import Foundation

// MARK: - HelperProxyRateLimitPolicy

/// Decides whether a system proxy override request arrives too soon after the previous one.
///
/// The decision and the timestamp it reads are both taken inside the privileged mutation gate.
/// Evaluating it outside would let two concurrently delivered XPC requests read the same stale
/// timestamp — and race on writing the new one — so neither the rate limit nor the stored value
/// would mean anything.
enum HelperProxyRateLimitPolicy {
    static func isRateLimited(
        lastChange: Date?,
        now: Date,
        interval: TimeInterval
    )
        -> Bool
    {
        guard let lastChange else {
            return false
        }
        let elapsed = now.timeIntervalSince(lastChange)
        return elapsed >= 0 && elapsed < interval
    }
}
