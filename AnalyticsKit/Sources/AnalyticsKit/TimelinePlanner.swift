import Foundation

// MARK: - Widget refresh economics as pure, testable logic (§6.2)

/// Decides what the widget timeline should contain and when to reload,
/// independent of WidgetKit so the policy is unit-testable.
public enum TimelinePlanner {

    public struct Plan: Equatable, Sendable {
        public let snapshot: Snapshot?
        public let isStale: Bool
        public let reloadAfter: Date
    }

    /// 2 h cadence on success (~12 reloads/day, well inside the system budget);
    /// 30 min retry on failure, rendering the last-good snapshot flagged stale.
    public static func plan(
        fetched: Snapshot?,
        fallback: Snapshot?,
        now: Date
    ) -> Plan {
        if let fetched {
            return Plan(snapshot: fetched, isStale: false, reloadAfter: now.addingTimeInterval(2 * 3600))
        }
        return Plan(snapshot: fallback, isStale: true, reloadAfter: now.addingTimeInterval(30 * 60))
    }
}
