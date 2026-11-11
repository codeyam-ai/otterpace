import XCTest
@testable import AppCore

/// The Apple Health + Strava merge: a run recorded on a watch lands in both
/// sources, so the history must show it once, keep every Health workout, and
/// let Strava fill only the gaps.
final class WorkoutMergeTests: XCTestCase {
    private func workout(_ type: String = "run", miles: Double, minutes: Int = 30,
                         date: String, source: String) -> LatestWorkout {
        LatestWorkout(type: type, distanceMiles: miles, durationMinutes: minutes,
                      pace: "10:00/mi", date: date, source: source)
    }

    // A Strava copy of a Health run (same day, type, distance within tolerance) is dropped.
    func testStravaCopyOfAHealthRunIsDropped() {
        let health = [workout(miles: 5.0, date: "2026-10-20", source: "healthkit")]
        let strava = [workout(miles: 5.2, date: "2026-10-20", source: "strava")]
        XCTAssertEqual(WorkoutMerge.merge(health: health, strava: strava), health)
    }

    // A Strava activity with no Health counterpart is added to the history.
    func testStravaOnlyActivityIsAdded() {
        let health = [workout(miles: 5.0, date: "2026-10-20", source: "healthkit")]
        let strava = [workout(miles: 3.0, date: "2026-10-19", source: "strava")]
        let merged = WorkoutMerge.merge(health: health, strava: strava)
        XCTAssertEqual(merged.map(\.source), ["healthkit", "strava"])
    }

    // Same day and distance but a different activity type is a different outing.
    func testADifferentTypeOnTheSameDayIsKept() {
        let health = [workout("run", miles: 5.0, date: "2026-10-20", source: "healthkit")]
        let strava = [workout("ride", miles: 5.0, date: "2026-10-20", source: "strava")]
        XCTAssertEqual(WorkoutMerge.merge(health: health, strava: strava).count, 2)
    }

    // A distance outside the tolerance is a second run, not a copy.
    func testADistanceOutsideToleranceIsKept() {
        let health = [workout(miles: 5.0, date: "2026-10-20", source: "healthkit")]
        let strava = [workout(miles: 8.0, date: "2026-10-20", source: "strava")]
        XCTAssertEqual(WorkoutMerge.merge(health: health, strava: strava).count, 2)
    }

    // Activities with no distance are matched by duration instead.
    func testDistanceLessActivitiesMatchByDuration() {
        let health = [workout("walk", miles: 0, minutes: 40, date: "2026-10-20", source: "healthkit")]
        let same = [workout("walk", miles: 0, minutes: 42, date: "2026-10-20", source: "strava")]
        let longer = [workout("walk", miles: 0, minutes: 90, date: "2026-10-20", source: "strava")]
        XCTAssertEqual(WorkoutMerge.merge(health: health, strava: same).count, 1)
        XCTAssertEqual(WorkoutMerge.merge(health: health, strava: longer).count, 2)
    }

    // Two genuine runs on the same day in one source are both kept.
    func testDuplicatesWithinOneSourceAreKept() {
        let health = [workout(miles: 3.0, date: "2026-10-20", source: "healthkit"),
                      workout(miles: 3.0, date: "2026-10-20", source: "healthkit")]
        XCTAssertEqual(WorkoutMerge.merge(health: health, strava: []).count, 2)
    }

    // One Health workout absorbs at most one Strava copy; a second copy stays.
    func testOneHealthWorkoutAbsorbsAtMostOneStravaCopy() {
        let health = [workout(miles: 5.0, date: "2026-10-20", source: "healthkit")]
        let strava = [workout(miles: 5.0, date: "2026-10-20", source: "strava"),
                      workout(miles: 5.0, date: "2026-10-20", source: "strava")]
        let merged = WorkoutMerge.merge(health: health, strava: strava)
        XCTAssertEqual(merged.map(\.source), ["healthkit", "strava"])
    }

    // The merged history is newest-first, and Health comes first on a tie.
    func testMergedHistoryIsNewestFirstWithHealthFirstOnTies() {
        let health = [workout(miles: 4.0, date: "2026-10-18", source: "healthkit"),
                      workout("ride", miles: 20.0, date: "2026-10-20", source: "healthkit")]
        let strava = [workout(miles: 6.0, date: "2026-10-20", source: "strava"),
                      workout(miles: 2.0, date: "2026-10-19", source: "strava")]
        let merged = WorkoutMerge.merge(health: health, strava: strava)
        XCTAssertEqual(merged.map(\.date), ["2026-10-20", "2026-10-20", "2026-10-19", "2026-10-18"])
        XCTAssertEqual(merged.first?.source, "healthkit")
    }

    // With nothing from either source the history is empty.
    func testEmptySourcesMergeToEmpty() {
        XCTAssertEqual(WorkoutMerge.merge(health: [], strava: []), [])
    }
}
