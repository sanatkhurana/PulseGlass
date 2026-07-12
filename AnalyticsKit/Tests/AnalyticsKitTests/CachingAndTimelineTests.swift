import XCTest
@testable import AnalyticsKit

final class CachePolicyTests: XCTestCase {

    let t0 = Date(timeIntervalSince1970: 1_780_000_000)

    func testUnknownKeyAlwaysRefetches() {
        let policy = CachePolicy()
        XCTAssertTrue(policy.shouldRefetch(key: "pulseglass.trend.daily", now: t0))
    }

    func testClientTTLShortCircuits() {
        var policy = CachePolicy(clientTTL: 300)
        policy.recordFetch(key: "q", at: t0, cacheTargetAge: nil)

        XCTAssertFalse(policy.shouldRefetch(key: "q", now: t0.addingTimeInterval(299)))
        XCTAssertTrue(policy.shouldRefetch(key: "q", now: t0.addingTimeInterval(301)))
    }

    func testServerCacheTargetAgeIsHonoredBeyondClientTTL() {
        // §7: the client persists cache_target_age and will not re-issue an
        // identical query before that timestamp.
        var policy = CachePolicy(clientTTL: 300)
        let target = t0.addingTimeInterval(1800)
        policy.recordFetch(key: "q", at: t0, cacheTargetAge: target)

        XCTAssertFalse(policy.shouldRefetch(key: "q", now: t0.addingTimeInterval(900)))
        XCTAssertFalse(policy.shouldRefetch(key: "q", now: target.addingTimeInterval(-1)))
        XCTAssertTrue(policy.shouldRefetch(key: "q", now: target.addingTimeInterval(1)))
    }

    func testKeysAreIndependent() {
        var policy = CachePolicy(clientTTL: 300)
        policy.recordFetch(key: "a", at: t0, cacheTargetAge: nil)
        XCTAssertTrue(policy.shouldRefetch(key: "b", now: t0))
        XCTAssertFalse(policy.shouldRefetch(key: "a", now: t0))
    }
}

final class SnapshotStoreTests: XCTestCase {

    var store: SnapshotStore!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "pulseglass-tests-\(UUID().uuidString)")
        store = SnapshotStore(directory: dir)
    }

    override func tearDownWithError() throws {
        try? store.wipeAll()
    }

    func testSaveAndLoadRoundTrip() throws {
        let snapshot = SampleData.snapshot(asOf: Date(timeIntervalSince1970: 1_780_000_000))
        try store.save(snapshot)

        let loaded = store.load(profileID: SampleData.profileID, range: .week)
        XCTAssertEqual(loaded, snapshot)
    }

    func testSnapshotsArePerProfileAndPerRange() throws {
        let base = SampleData.snapshot(asOf: Date(timeIntervalSince1970: 1_780_000_000))
        try store.save(base)

        XCTAssertNil(store.load(profileID: UUID(), range: .week), "other profiles see nothing")
        XCTAssertNil(store.load(profileID: SampleData.profileID, range: .month), "other ranges see nothing")
    }

    func testMissingSnapshotReturnsNil() {
        XCTAssertNil(store.load(profileID: UUID(), range: .week))
    }

    func testWipeAllRemovesEverything() throws {
        try store.save(SampleData.snapshot())
        try store.wipeAll()
        XCTAssertNil(store.load(profileID: SampleData.profileID, range: .week))
    }

    func testStalenessThreshold() {
        let now = Date()
        let fresh = SampleData.snapshot(asOf: now.addingTimeInterval(-11 * 3600))
        let stale = SampleData.snapshot(asOf: now.addingTimeInterval(-13 * 3600))

        XCTAssertFalse(fresh.isStale(asOf: now))
        XCTAssertTrue(stale.isStale(asOf: now))
    }
}

/// Widget timeline policy (§6.2): 2 h reload on success, 30 min retry with
/// the last-good snapshot flagged stale on failure.
final class TimelinePlannerTests: XCTestCase {

    let now = Date(timeIntervalSince1970: 1_780_000_000)

    func testSuccessSchedulesTwoHourReload() {
        let fetched = SampleData.snapshot(asOf: now)
        let plan = TimelinePlanner.plan(fetched: fetched, fallback: nil, now: now)

        XCTAssertEqual(plan.snapshot, fetched)
        XCTAssertFalse(plan.isStale)
        XCTAssertEqual(plan.reloadAfter, now.addingTimeInterval(2 * 3600))
    }

    func testFailureFallsBackToSnapshotFlaggedStaleWithThirtyMinuteRetry() {
        let fallback = SampleData.snapshot(asOf: now.addingTimeInterval(-3600))
        let plan = TimelinePlanner.plan(fetched: nil, fallback: fallback, now: now)

        XCTAssertEqual(plan.snapshot, fallback)
        XCTAssertTrue(plan.isStale)
        XCTAssertEqual(plan.reloadAfter, now.addingTimeInterval(30 * 60))
    }

    func testFailureWithNoFallbackStillRetriesInThirtyMinutes() {
        let plan = TimelinePlanner.plan(fetched: nil, fallback: nil, now: now)

        XCTAssertNil(plan.snapshot)
        XCTAssertTrue(plan.isStale)
        XCTAssertEqual(plan.reloadAfter, now.addingTimeInterval(30 * 60))
    }
}
