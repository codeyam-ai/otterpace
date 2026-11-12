import XCTest
@testable import AppCore

// XCTest (not swift-testing) so results land in the editor's --xunit-output file.
//
// The model side of the battery-light refresh (`Model+Refresh.swift`): the
// throttle is honoured, a locked-phone background read changes nothing, Strava
// stamps follow success not content, the foreground adopts a newer background
// cache, and two overlapping triggers never both read.
final class ModelRefreshTests: XCTestCase {

    /// A Health source that counts reads and serves a configurable step count.
    private final class CountingSource: HealthDataSource {
        var steps: Int
        var loads = 0
        init(steps: Int) { self.steps = steps }
        func authorizationState() -> HealthAuthState { .authorized }
        func requestAuthorization() async -> HealthAuthState { .authorized }
        func loadToday() async -> TodayState {
            loads += 1
            return TodayState(healthKitConnected: true, steps: steps)
        }
        func lastMovementDate() async -> Date? { nil }
    }

    /// A Strava fetcher that counts calls and returns a fixed result or throws.
    private final class FakeStrava {
        var result: [LatestWorkout]
        var fails = false
        var calls = 0
        init(_ result: [LatestWorkout] = []) { self.result = result }
        func fetch() async throws -> [LatestWorkout] {
            calls += 1
            if fails { throw URLError(.notConnectedToInternet) }
            return result
        }
    }

    private struct Fixture {
        let model: OtterpaceModel
        let source: CountingSource
        let defaults: UserDefaults
    }

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor
    private func makeModel(steps: Int = 4200, authorized: Bool = true) -> Fixture {
        let d = UserDefaults(suiteName: "ModelRefreshTests.\(UUID().uuidString)")!
        let source = CountingSource(steps: steps)
        let model = OtterpaceModel(today: TodayState(healthKitConnected: authorized), source: source, defaults: d)
        return Fixture(model: model, source: source, defaults: d)
    }

    private func run(_ date: String) -> LatestWorkout {
        LatestWorkout(type: "run", distanceMiles: 3, durationMinutes: 30, pace: "10:00/mi", date: date, source: "strava")
    }

    // MARK: Health throttle

    // The first automatic refresh reads Health, shows it, stamps it, and reports fresh.
    @MainActor func testFirstForegroundRefreshReadsAndStamps() async {
        let f = makeModel(steps: 4200)
        let fresh = await f.model.refreshIfDue(.foreground, now: t0)
        XCTAssertTrue(fresh)
        XCTAssertEqual(f.source.loads, 1)
        XCTAssertEqual(f.model.today.steps, 4200)
        XCTAssertEqual(RefreshStamps.lastHealth(f.defaults), t0)
    }

    // Returning again within 15 minutes does not spend another Health read.
    @MainActor func testForegroundRefreshWithinIntervalIsSkipped() async {
        let f = makeModel()
        await f.model.refreshIfDue(.foreground, now: t0)
        let fresh = await f.model.refreshIfDue(.foreground, now: t0.addingTimeInterval(10 * 60))
        XCTAssertFalse(fresh)
        XCTAssertEqual(f.source.loads, 1)
    }

    // Once the interval has passed the next return reads again.
    @MainActor func testForegroundRefreshAfterIntervalReadsAgain() async {
        let f = makeModel()
        await f.model.refreshIfDue(.foreground, now: t0)
        f.source.steps = 6000
        let fresh = await f.model.refreshIfDue(.foreground, now: t0.addingTimeInterval(15 * 60))
        XCTAssertTrue(fresh)
        XCTAssertEqual(f.source.loads, 2)
        XCTAssertEqual(f.model.today.steps, 6000)
    }

    // A locked-phone (all-zero) background read keeps the cached picture, leaves the
    // stamp so the next wake retries, and is not fresh — so no heartbeat is sent.
    @MainActor func testLockedBackgroundReadKeepsCacheAndStamp() async {
        let f = makeModel(steps: 4200)
        await f.model.refreshIfDue(.foreground, now: t0)
        f.source.steps = 0
        let later = t0.addingTimeInterval(2 * 3600)
        let fresh = await f.model.refreshIfDue(.background, now: later)
        XCTAssertFalse(fresh)
        XCTAssertEqual(f.source.loads, 2)
        XCTAssertEqual(f.model.today.steps, 4200)
        XCTAssertEqual(RefreshStamps.lastHealth(f.defaults), t0)
    }

    // Without Health access nothing is read at all.
    @MainActor func testUnauthorizedRefreshDoesNotReadHealth() async {
        let f = makeModel(authorized: false)
        let fresh = await f.model.refreshIfDue(.foreground, now: t0)
        XCTAssertFalse(fresh)
        XCTAssertEqual(f.source.loads, 0)
        XCTAssertNil(RefreshStamps.lastHealth(f.defaults))
    }

    // MARK: Strava

    // An empty successful import stamps (a quiet account isn't re-polled) but is not fresh.
    @MainActor func testEmptyStravaSuccessStampsButIsNotFresh() async {
        let f = makeModel(authorized: false)
        let strava = FakeStrava([])
        let fresh = await f.model.refreshIfDue(.foreground, fetchStrava: strava.fetch, now: t0)
        XCTAssertFalse(fresh)
        XCTAssertEqual(strava.calls, 1)
        XCTAssertEqual(RefreshStamps.lastStrava(f.defaults), t0)
    }

    // A failed import leaves no stamp, so the next chance retries instead of waiting 3h.
    @MainActor func testFailedStravaImportLeavesNoStamp() async {
        let f = makeModel(authorized: false)
        let strava = FakeStrava()
        strava.fails = true
        let fresh = await f.model.refreshIfDue(.foreground, fetchStrava: strava.fetch, now: t0)
        XCTAssertFalse(fresh)
        XCTAssertNil(RefreshStamps.lastStrava(f.defaults))
    }

    // New runs replace what is on screen and count as fresh; the same runs 3h later don't.
    @MainActor func testNewStravaRunsAreFreshAndUnchangedAreNot() async {
        let f = makeModel(authorized: false)
        let strava = FakeStrava([run("2026-11-11")])
        let first = await f.model.refreshIfDue(.foreground, fetchStrava: strava.fetch, now: t0)
        XCTAssertTrue(first)
        XCTAssertEqual(f.model.stravaWorkouts, [run("2026-11-11")])
        let again = await f.model.refreshIfDue(.foreground, fetchStrava: strava.fetch, now: t0.addingTimeInterval(3 * 3600))
        XCTAssertFalse(again)
        XCTAssertEqual(strava.calls, 2)
    }

    // Strava is not called again inside its 3h window, even when Health is due.
    @MainActor func testStravaIsThrottledToThreeHours() async {
        let f = makeModel()
        let strava = FakeStrava([run("2026-11-11")])
        await f.model.refreshIfDue(.foreground, fetchStrava: strava.fetch, now: t0)
        await f.model.refreshIfDue(.foreground, fetchStrava: strava.fetch, now: t0.addingTimeInterval(3600))
        XCTAssertEqual(strava.calls, 1)
        XCTAssertEqual(f.source.loads, 2)
    }

    // MARK: Adopting the background cache

    // When nothing new was read in the foreground but the background path wrote a
    // newer cache, the foreground shows that cache.
    @MainActor func testForegroundAdoptsANewerBackgroundCache() async {
        let f = makeModel()
        await f.model.refreshIfDue(.foreground, now: t0)
        SnapshotCache.save(CachedSnapshot(health: nil, strava: [run("2026-11-12")],
                                          refreshedAt: Date().addingTimeInterval(60)), f.defaults)
        let fresh = await f.model.refreshIfDue(.foreground, now: t0.addingTimeInterval(60))
        XCTAssertFalse(fresh)
        XCTAssertEqual(f.model.stravaWorkouts, [run("2026-11-12")])
    }

    // A background pass never adopts — it is the writer, not the reader, of that cache.
    @MainActor func testBackgroundDoesNotAdoptTheCache() async {
        let f = makeModel()
        await f.model.refreshIfDue(.foreground, now: t0)
        SnapshotCache.save(CachedSnapshot(health: nil, strava: [run("2026-11-12")],
                                          refreshedAt: Date().addingTimeInterval(60)), f.defaults)
        await f.model.refreshIfDue(.background, now: t0.addingTimeInterval(60))
        XCTAssertEqual(f.model.stravaWorkouts, [])
    }

    // A cache older than this model's own last compose is not re-adopted.
    @MainActor func testOlderCacheIsNotAdopted() async {
        let f = makeModel()
        await f.model.refreshIfDue(.foreground, now: t0)
        SnapshotCache.save(CachedSnapshot(health: nil, strava: [run("2026-11-01")],
                                          refreshedAt: Date().addingTimeInterval(-3600)), f.defaults)
        await f.model.refreshIfDue(.foreground, now: t0.addingTimeInterval(60))
        XCTAssertEqual(f.model.stravaWorkouts, [])
    }

    // MARK: In-flight guard

    // Only one restore/refresh holds the slot at a time; releasing it frees the slot.
    @MainActor func testRefreshSlotIsExclusiveUntilReleased() {
        let f = makeModel()
        XCTAssertTrue(f.model.beginRefresh())
        XCTAssertFalse(f.model.beginRefresh())
        f.model.endRefresh()
        XCTAssertTrue(f.model.beginRefresh())
    }

    // While another refresh holds the slot, refreshIfDue stands down without reading.
    @MainActor func testRefreshStandsDownWhileAnotherIsInFlight() async {
        let f = makeModel()
        XCTAssertTrue(f.model.beginRefresh())
        let fresh = await f.model.refreshIfDue(.foreground, now: t0)
        XCTAssertFalse(fresh)
        XCTAssertEqual(f.source.loads, 0)
    }

    // A seeded scenario never reads live data, so the slot is refused.
    @MainActor func testSeededScenarioRefusesTheRefreshSlot() {
        let f = makeModel()
        f.defaults.set(true, forKey: "rbConnected")
        XCTAssertFalse(f.model.beginRefresh())
    }

    // MARK: Launch restore + heartbeat

    // The launch restore stamps both sources, so the first foreground return right
    // after launch doesn't read them all over again.
    @MainActor func testRestoreOnLaunchStampsBothSources() async {
        let f = makeModel()
        await f.model.restoreOnLaunch(fetchStrava: { [] })
        XCTAssertNotNil(RefreshStamps.lastHealth(f.defaults))
        XCTAssertNotNil(RefreshStamps.lastStrava(f.defaults))
        let fresh = await f.model.refreshIfDue(.foreground)
        XCTAssertFalse(fresh)
        XCTAssertEqual(f.source.loads, 1)
    }

    // A failed Strava call during launch restore leaves no Strava stamp.
    @MainActor func testRestoreOnLaunchFailedStravaLeavesNoStamp() async {
        let f = makeModel()
        await f.model.restoreOnLaunch(fetchStrava: { throw URLError(.timedOut) })
        XCTAssertNil(RefreshStamps.lastStrava(f.defaults))
    }

    // The heartbeat is built from what is on screen after the refresh.
    @MainActor func testHeartbeatCarriesTheRefreshedTotals() async {
        let f = makeModel(steps: 7777)
        await f.model.refreshIfDue(.foreground, now: t0)
        let beat = await f.model.healthHeartbeat()
        XCTAssertEqual(beat.steps, 7777)
        XCTAssertEqual(beat.timeZone, TimeZone.current.identifier)
    }
}
