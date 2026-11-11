import XCTest
@testable import AppCore

/// The launch cache that lets a returning user land on their dashboard instead
/// of the Connect hero: round-trip, clear, a corrupt value decoding to nil, and
/// the day rollover that resets today's totals while keeping history.
final class SnapshotCacheTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SnapshotCacheTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func healthState(date: String) -> TodayState {
        var state = TodayState.empty
        state.healthKitConnected = true
        state.date = date
        state.steps = 8400
        state.activeMinutes = 45
        state.distanceMiles = 4.2
        state.activeEnergyKcal = 510
        state.minutesSinceLastMovement = 12
        state.workouts = [LatestWorkout(type: "run", distanceMiles: 4.2, durationMinutes: 42,
                                        pace: "10:00/mi", date: date, source: "healthkit")]
        return state
    }

    // An untouched store has no cached snapshot.
    func testLoadOnAnUntouchedStoreIsNil() {
        XCTAssertNil(SnapshotCache.load(defaults))
    }

    // A saved snapshot loads back unchanged.
    func testSaveThenLoadRoundTrips() {
        let strava = [LatestWorkout(type: "run", distanceMiles: 6.0, durationMinutes: 60,
                                    pace: "10:00/mi", date: "2026-10-19", source: "strava")]
        let snapshot = CachedSnapshot(health: healthState(date: "2026-10-20"), strava: strava,
                                      refreshedAt: Date(timeIntervalSince1970: 1_790_000_000))
        SnapshotCache.save(snapshot, defaults)
        XCTAssertEqual(SnapshotCache.load(defaults), snapshot)
    }

    // Clearing the cache makes the next load nil.
    func testClearEmptiesTheCache() {
        SnapshotCache.save(CachedSnapshot(health: nil, strava: [], refreshedAt: Date()), defaults)
        SnapshotCache.clear(defaults)
        XCTAssertNil(SnapshotCache.load(defaults))
    }

    // A corrupt stored value decodes to nil rather than crashing the launch.
    func testCorruptValueLoadsAsNil() {
        defaults.set(Data("not json".utf8), forKey: SnapshotCache.key)
        XCTAssertNil(SnapshotCache.load(defaults))
    }

    // On the same day the cached Health state renders exactly as cached.
    func testSameDayHealthStateIsUnchanged() {
        let state = healthState(date: "2026-10-20")
        let snapshot = CachedSnapshot(health: state, strava: [], refreshedAt: Date())
        XCTAssertEqual(snapshot.healthState(asOf: "2026-10-20"), state)
    }

    // On a new day today's totals reset to zero but the workout history carries over.
    func testNewDayResetsTodaysTotalsButKeepsHistory() {
        let state = healthState(date: "2026-10-20")
        let snapshot = CachedSnapshot(health: state, strava: [], refreshedAt: Date())
        let rolled = snapshot.healthState(asOf: "2026-10-21")
        XCTAssertEqual(rolled?.date, "2026-10-21")
        XCTAssertEqual(rolled?.steps, 0)
        XCTAssertEqual(rolled?.activeMinutes, 0)
        XCTAssertEqual(rolled?.distanceMiles, 0)
        XCTAssertEqual(rolled?.activeEnergyKcal, 0)
        XCTAssertEqual(rolled?.minutesSinceLastMovement, 0)
        XCTAssertEqual(rolled?.workouts, state.workouts)
        XCTAssertTrue(rolled?.healthKitConnected ?? false)
    }

    // With Health never read, there is no cached Health state on any day.
    func testNoHealthSnapshotStaysNil() {
        let snapshot = CachedSnapshot(health: nil, strava: [], refreshedAt: Date())
        XCTAssertNil(snapshot.healthState(asOf: "2026-10-21"))
    }
}
