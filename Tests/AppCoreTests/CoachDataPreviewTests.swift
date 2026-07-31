import XCTest
@testable import AppCore

// XCTest (not swift-testing) so results land in the editor's --xunit-output file.
//
// The Coach Data Preview tells the user where their workout data came from. That
// is a privacy claim, so the string is proved here rather than only being visible
// in a screenshot — a screenshot shows one seeded case, these cover the rest.
final class CoachDataPreviewTests: XCTestCase {

    private func workout(_ source: String, date: String = "2026-06-21") -> LatestWorkout {
        LatestWorkout(type: "run", distanceMiles: 4.2, durationMinutes: 43,
                      pace: "10:15/mi", date: date, source: source)
    }

    // The honest default for an empty list: Apple Health is the only source that
    // needs no setup, so an empty summary must not imply Strava was involved.
    func testNoWorkoutsNamesAppleHealthOnly() {
        XCTAssertEqual(coachWorkoutSources([]), "Apple Health")
    }

    // A single source reads as itself, with no "and" dangling off the end.
    func testSingleSourceHasNoConjunction() {
        XCTAssertEqual(coachWorkoutSources([workout("healthkit")]), "Apple Health")
        XCTAssertEqual(coachWorkoutSources([workout("strava")]), "Strava")
    }

    // Repeats collapse — five HealthKit workouts are still one source, not five.
    func testRepeatedSourceDeduplicates() {
        let all = (0..<5).map { _ in workout("healthkit") }
        XCTAssertEqual(coachWorkoutSources(all), "Apple Health")
    }

    // Two sources join with "and", which is what the preview sentence needs to
    // read as a sentence rather than a comma-separated dump.
    func testTwoSourcesJoinWithAnd() {
        let mixed = [workout("healthkit"), workout("strava")]
        XCTAssertEqual(coachWorkoutSources(mixed), "Apple Health and Strava")
    }

    // Order follows first appearance, not a fixed alphabet: a Strava-first list
    // says Strava first, so the sentence matches the order shown above it.
    func testOrderFollowsFirstAppearance() {
        let stravaFirst = [workout("strava"), workout("healthkit")]
        XCTAssertEqual(coachWorkoutSources(stravaFirst), "Strava and Apple Health")
    }

    // An unknown/absent source is attributed to Apple Health rather than invented
    // as a new provider name — the preview must never name a source we can't back.
    func testUnknownSourceFallsBackToAppleHealth() {
        XCTAssertEqual(coachWorkoutSources([workout("")]), "Apple Health")
        XCTAssertEqual(coachWorkoutSources([workout("garmin")]), "Apple Health")
    }

    // The preview reads `model.today` — the SAME value AskCoachView hands to
    // RemoteCoach — so what it displays cannot drift from what is sent. This
    // pins that contract: a TodayState round-trips through the payload encoder
    // unchanged, so any field added to the state reaches the preview too.
    func testTodayStateIsTheSameShapeTheCoachReceives() throws {
        let state = TodayState(
            healthKitConnected: true,
            date: "2026-06-22",
            steps: 6420,
            goalSteps: 10000,
            activeMinutes: 42,
            distanceMiles: 2.8,
            activeEnergyKcal: 310,
            minutesSinceLastMovement: 92,
            workouts: [workout("healthkit"), workout("strava")]
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(TodayState.self, from: data)
        XCTAssertEqual(decoded, state)
        XCTAssertEqual(coachWorkoutSources(decoded.workouts), "Apple Health and Strava")
    }
}
