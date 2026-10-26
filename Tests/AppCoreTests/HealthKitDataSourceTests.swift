import XCTest
@testable import AppCore

// XCTest (not swift-testing) so results land in the editor's --xunit-output file.
// HealthKitDataSource's queries are iOS-only glue; these cover what it does with
// the numbers HealthKit hands back, which builds on macOS.
final class HealthKitDataSourceTests: XCTestCase {

    private func workout(_ type: String, date: String, minutes: Int) -> LatestWorkout {
        LatestWorkout(type: type, distanceMiles: 1, durationMinutes: minutes, pace: "", date: date, source: "healthkit")
    }

    // Active minutes count only today's workouts, and the Today card prefers the
    // latest run over a newer walk.
    func testTodayStateCountsTodaysMinutesAndPrefersRun() {
        let history = [
            workout("walk", date: "2026-07-15", minutes: 20),   // newest-first
            workout("run", date: "2026-07-15", minutes: 35),
            workout("ride", date: "2026-07-14", minutes: 60),
        ]
        let state = HealthKitDataSource.todayState(steps: 6420.7, distanceMiles: 3.1, energyKcal: 412.9,
                                                   goalSteps: 10_000, history: history,
                                                   date: "2026-07-15", now: Date())
        XCTAssertEqual(state.steps, 6420)
        XCTAssertEqual(state.activeEnergyKcal, 412)
        XCTAssertEqual(state.activeMinutes, 55)
        XCTAssertEqual(state.latestWorkout?.type, "run")
        XCTAssertEqual(state.goalSteps, 10_000)
        XCTAssertTrue(state.healthKitConnected)
        XCTAssertNotNil(state.weeklyLoad)
    }

    // No workouts → no latest workout, no weekly load, and an empty series.
    func testTodayStateWithNoHistory() {
        let state = HealthKitDataSource.todayState(steps: 0, distanceMiles: 0, energyKcal: 0, goalSteps: 8_000,
                                                   history: [], date: "2026-07-15", now: Date())
        XCTAssertNil(state.latestWorkout)
        XCTAssertNil(state.weeklyLoad)
        XCTAssertEqual(state.loadHistory, [])
        XCTAssertEqual(state.activeMinutes, 0)
    }

    // A 5 km run in 30 minutes → 3.1 miles at 9:39/mi.
    func testWorkoutConvertsDistanceAndPace() {
        let w = HealthKitDataSource.workout(type: "run", meters: 5_000, durationSeconds: 1_800, date: "2026-07-15")
        XCTAssertEqual(w.distanceMiles, 3.1)
        XCTAssertEqual(w.durationMinutes, 30)
        XCTAssertEqual(w.pace, "9:39/mi")
        XCTAssertEqual(w.source, "healthkit")
    }

    // No recorded distance (e.g. yoga) → zero miles and no pace.
    func testWorkoutWithoutDistanceHasNoPace() {
        let w = HealthKitDataSource.workout(type: "workout", meters: 0, durationSeconds: 2_700, date: "2026-07-15")
        XCTAssertEqual(w.distanceMiles, 0)
        XCTAssertEqual(w.pace, "")
        XCTAssertEqual(w.durationMinutes, 45)
    }

    func testPacePerMilePadsSeconds() {
        XCTAssertEqual(HealthKitDataSource.pacePerMile(secondsPerMile: 605), "10:05/mi")
    }

    // Last movement is the newest of the step and distance samples, ignoring a
    // type with no samples.
    func testLatestMovementPicksNewestKnownSample() {
        let a = Date(timeIntervalSince1970: 1_000)
        let b = Date(timeIntervalSince1970: 2_000)
        XCTAssertEqual(HealthKitDataSource.latest([a, nil, b]), b)
        XCTAssertNil(HealthKitDataSource.latest([nil, nil]))
    }
}
