import XCTest
@testable import AppCore

// XCTest (not swift-testing) so results land in the editor's --xunit-output file.
//
// The battery-light throttle every automatic refresh asks first. Pure, so every
// interval and edge (never refreshed, skewed clock, locked-phone read) is pinned
// here without HealthKit.
final class RefreshPolicyTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func run(_ date: String) -> LatestWorkout {
        LatestWorkout(type: "run", distanceMiles: 3, durationMinutes: 30, pace: "10:00/mi", date: date, source: "strava")
    }

    // MARK: shouldRefresh

    // A source that has never refreshed is always due, so a first launch reads data.
    func testNeverRefreshedIsAlwaysDue() {
        XCTAssertTrue(RefreshPolicy.shouldRefresh(.foreground, lastRefreshed: nil, now: now))
        XCTAssertTrue(RefreshPolicy.shouldRefresh(.background, lastRefreshed: nil, now: now))
        XCTAssertTrue(RefreshPolicy.shouldRefresh(.strava, lastRefreshed: nil, now: now))
    }

    // Returning to the app re-reads Health at most once per 15 minutes.
    func testForegroundWaitsFifteenMinutes() {
        XCTAssertFalse(RefreshPolicy.shouldRefresh(.foreground, lastRefreshed: now.addingTimeInterval(-14 * 60), now: now))
        XCTAssertTrue(RefreshPolicy.shouldRefresh(.foreground, lastRefreshed: now.addingTimeInterval(-15 * 60), now: now))
    }

    // A background wake spends an OS-budgeted read, so it waits a full hour.
    func testBackgroundWaitsAnHour() {
        XCTAssertFalse(RefreshPolicy.shouldRefresh(.background, lastRefreshed: now.addingTimeInterval(-59 * 60), now: now))
        XCTAssertTrue(RefreshPolicy.shouldRefresh(.background, lastRefreshed: now.addingTimeInterval(-3600), now: now))
    }

    // Strava is a remote, rate-limited API, so it is polled at most every 3 hours.
    func testStravaWaitsThreeHours() {
        XCTAssertFalse(RefreshPolicy.shouldRefresh(.strava, lastRefreshed: now.addingTimeInterval(-2 * 3600), now: now))
        XCTAssertTrue(RefreshPolicy.shouldRefresh(.strava, lastRefreshed: now.addingTimeInterval(-3 * 3600), now: now))
    }

    // A stamp in the future (clock moved back) counts as just refreshed, so a skewed
    // clock cannot force a refresh storm.
    func testFutureStampCountsAsJustRefreshed() {
        let future = now.addingTimeInterval(6 * 3600)
        XCTAssertFalse(RefreshPolicy.shouldRefresh(.foreground, lastRefreshed: future, now: now))
        XCTAssertFalse(RefreshPolicy.shouldRefresh(.strava, lastRefreshed: future, now: now))
    }

    // The per-kind intervals are the ones the user approved in the plan.
    func testMinimumIntervalsMatchTheApprovedPlan() {
        XCTAssertEqual(RefreshPolicy.minimumInterval(for: .foreground), 15 * 60)
        XCTAssertEqual(RefreshPolicy.minimumInterval(for: .background), 3600)
        XCTAssertEqual(RefreshPolicy.minimumInterval(for: .strava), 3 * 3600)
        XCTAssertEqual(RefreshPolicy.backgroundTaskSpacing, 4 * 3600)
    }

    // MARK: isUsableRead

    // In the foreground HealthKit is readable, so even an all-zero day is trusted.
    func testForegroundTrustsAnEmptyRead() {
        XCTAssertTrue(RefreshPolicy.isUsableRead(.empty, for: .foreground))
    }

    // In the background an all-zero read means the phone is locked — unknown, not idle.
    func testBackgroundRejectsAnAllZeroRead() {
        XCTAssertFalse(RefreshPolicy.isUsableRead(.empty, for: .background))
    }

    // Any real signal (steps, a workout, or per-day history) makes a background read usable.
    func testBackgroundAcceptsAReadWithAnySignal() {
        var withSteps = TodayState.empty
        withSteps.steps = 1
        var withWorkout = TodayState.empty
        withWorkout.workouts = [run("2026-11-12")]
        var withHistory = TodayState.empty
        withHistory.dailySteps = ["2026-11-11": 4200]
        XCTAssertTrue(RefreshPolicy.isUsableRead(withSteps, for: .background))
        XCTAssertTrue(RefreshPolicy.isUsableRead(withWorkout, for: .background))
        XCTAssertTrue(RefreshPolicy.isUsableRead(withHistory, for: .background))
    }

    // MARK: isNewStravaImport

    // An empty import (not connected / quiet account) must never wipe cached runs.
    func testEmptyStravaImportIsNotNew() {
        XCTAssertFalse(RefreshPolicy.isNewStravaImport([], current: [run("2026-11-10")]))
        XCTAssertFalse(RefreshPolicy.isNewStravaImport([], current: []))
    }

    // An unchanged import is not fresh, so it triggers no recompose or heartbeat.
    func testUnchangedStravaImportIsNotNew() {
        XCTAssertFalse(RefreshPolicy.isNewStravaImport([run("2026-11-10")], current: [run("2026-11-10")]))
    }

    // A changed or first import replaces what is on screen.
    func testChangedStravaImportIsNew() {
        XCTAssertTrue(RefreshPolicy.isNewStravaImport([run("2026-11-11")], current: [run("2026-11-10")]))
        XCTAssertTrue(RefreshPolicy.isNewStravaImport([run("2026-11-11")], current: []))
    }

    // MARK: shouldAdoptCache

    // A model that has never composed adopts whatever the cache holds.
    func testNeverComposedAdoptsAnyCache() {
        XCTAssertTrue(RefreshPolicy.shouldAdoptCache(cachedAt: now, lastComposedAt: nil))
    }

    // A cache written after this model composed came from the background path — adopt it.
    func testNewerCacheIsAdopted() {
        XCTAssertTrue(RefreshPolicy.shouldAdoptCache(cachedAt: now, lastComposedAt: now.addingTimeInterval(-60)))
    }

    // A cache this model wrote itself (same time) or an older one is not adopted again.
    func testSameOrOlderCacheIsNotAdopted() {
        XCTAssertFalse(RefreshPolicy.shouldAdoptCache(cachedAt: now, lastComposedAt: now))
        XCTAssertFalse(RefreshPolicy.shouldAdoptCache(cachedAt: now.addingTimeInterval(-60), lastComposedAt: now))
    }

    // MARK: RefreshStamps

    // Stamps persist per source in the given defaults, so the throttle holds across
    // launches and between the foreground and background models.
    func testStampsRoundTripPerSource() {
        let d = UserDefaults(suiteName: "RefreshPolicyTests.\(UUID().uuidString)")!
        XCTAssertNil(RefreshStamps.lastHealth(d))
        XCTAssertNil(RefreshStamps.lastStrava(d))
        RefreshStamps.markHealth(now, d)
        XCTAssertEqual(RefreshStamps.lastHealth(d), now)
        XCTAssertNil(RefreshStamps.lastStrava(d))
        RefreshStamps.markStrava(now.addingTimeInterval(5), d)
        XCTAssertEqual(RefreshStamps.lastStrava(d), now.addingTimeInterval(5))
    }
}
