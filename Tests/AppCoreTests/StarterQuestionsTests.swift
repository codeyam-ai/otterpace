import XCTest
@testable import AppCore

// The Ask Coach ice-breakers.
//
// The load-bearing assertion here is the intent round-trip: each suggestion
// declares the intent it targets, and `CoachIntent.classify` must actually route
// it there. Without that, a keyword change in the classifier could silently send
// "Should I run today or rest?" somewhere else — worst case into `.injuryPain`,
// where a friendly ice-breaker returns an injury-caution reply.
final class StarterQuestionsTests: XCTestCase {

    private func state(latestWorkout: LatestWorkout? = nil,
                       workouts: [LatestWorkout] = [],
                       loadHistory: [WeeklyLoadPoint] = [],
                       races: [RaceGoal] = [],
                       date: String = "2026-06-22") -> TodayState {
        TodayState(healthKitConnected: true,
                   date: date,
                   steps: 6000,
                   latestWorkout: latestWorkout,
                   workouts: workouts,
                   loadHistory: loadHistory,
                   races: races)
    }

    private func workout(date: String = "2026-06-21") -> LatestWorkout {
        LatestWorkout(type: "run", distanceMiles: 4.2, durationMinutes: 44,
                      pace: "10:28/mi", date: date, source: "healthkit")
    }

    private func loadPoint(_ weekStart: String, _ miles: Double) -> WeeklyLoadPoint {
        WeeklyLoadPoint(weekStartISO: weekStart, miles: miles, daysRun: 3)
    }

    // MARK: Round-trip

    /// Every suggestion, in every state, must classify to the intent it declares.
    func testEverySuggestionClassifiesToItsDeclaredIntent() {
        let states: [TodayState] = [
            state(),
            state(latestWorkout: workout(), workouts: [workout()]),
            state(loadHistory: [loadPoint("2026-06-15", 12), loadPoint("2026-06-08", 9)]),
            state(races: [RaceGoal(name: "October Trail Half", distanceMiles: 13.1, date: "2026-10-10")]),
        ]

        for s in states {
            for q in StarterQuestions.suggestions(for: s) {
                XCTAssertEqual(CoachIntent.classify(q.text), q.intent,
                               "\"\(q.text)\" declares \(q.intent) but classifies as \(CoachIntent.classify(q.text)).")
            }
        }
    }

    /// A friendly ice-breaker must never trip the injury-caution path.
    func testNoSuggestionRoutesToInjury() {
        let s = state(latestWorkout: workout(), workouts: [workout()],
                      races: [RaceGoal(name: "Half", distanceMiles: 13.1, date: "2026-10-10")])
        for q in StarterQuestions.suggestions(for: s) {
            XCTAssertNotEqual(CoachIntent.classify(q.text), .injuryPain,
                              "\"\(q.text)\" routes to the injury reply.")
        }
    }

    // MARK: Day one vs. rich state

    /// A day-one user has no runs, so offering "how did my last run go?" would
    /// point at data the app does not have.
    func testDayOneOffersNoPostRunOrRaceQuestion() {
        let intents = StarterQuestions.suggestions(for: state()).map(\.intent)
        XCTAssertFalse(intents.contains(.postRunReflection))
        XCTAssertFalse(intents.contains(.raceGoal))
        XCTAssertFalse(intents.contains(.mileageTooFast))
    }

    func testAlwaysOffersTheUniversalQuestions() {
        for s in [state(), state(latestWorkout: workout(), workouts: [workout()])] {
            let intents = StarterQuestions.suggestions(for: s).map(\.intent)
            XCTAssertTrue(intents.contains(.runOrRest))
            XCTAssertTrue(intents.contains(.hit10K))
        }
    }

    func testPostRunQuestionAppearsOnceThereIsARun() {
        let intents = StarterQuestions.suggestions(for: state(latestWorkout: workout(),
                                                              workouts: [workout()])).map(\.intent)
        XCTAssertTrue(intents.contains(.postRunReflection))
    }

    func testRaceQuestionAppearsOnlyForAnUpcomingRace() {
        let upcoming = state(races: [RaceGoal(name: "October Trail Half", distanceMiles: 13.1, date: "2026-10-10")])
        XCTAssertTrue(StarterQuestions.suggestions(for: upcoming).map(\.intent).contains(.raceGoal))

        // A finished race is not something to train toward.
        let past = state(races: [RaceGoal(name: "Spring 10K", distanceMiles: 6.2, date: "2026-04-01")])
        XCTAssertFalse(StarterQuestions.suggestions(for: past).map(\.intent).contains(.raceGoal))
    }

    func testMileageQuestionNeedsTwoLoadPoints() {
        let one = state(loadHistory: [loadPoint("2026-06-15", 12)])
        XCTAssertFalse(StarterQuestions.suggestions(for: one).map(\.intent).contains(.mileageTooFast))

        let two = state(loadHistory: [loadPoint("2026-06-15", 12), loadPoint("2026-06-08", 9)])
        XCTAssertTrue(StarterQuestions.suggestions(for: two).map(\.intent).contains(.mileageTooFast))
    }

    // MARK: Shape

    func testCappedAndDuplicateFree() {
        // The richest possible state, where every conditional suggestion fires.
        let rich = state(latestWorkout: workout(),
                         workouts: [workout()],
                         loadHistory: [loadPoint("2026-06-15", 12), loadPoint("2026-06-08", 9)],
                         races: [RaceGoal(name: "October Trail Half", distanceMiles: 13.1, date: "2026-10-10")])
        let suggestions = StarterQuestions.suggestions(for: rich)

        XCTAssertLessThanOrEqual(suggestions.count, StarterQuestions.maxCount)
        XCTAssertEqual(Set(suggestions.map(\.text)).count, suggestions.count, "duplicate suggestion text")
        XCTAssertEqual(Set(suggestions.map(\.intent)).count, suggestions.count, "two suggestions target the same intent")
    }

    func testNeverEmpty() {
        XCTAssertFalse(StarterQuestions.suggestions(for: state()).isEmpty)
    }

    func testCopyHasNoEmDashes() {
        let rich = state(latestWorkout: workout(), workouts: [workout()],
                         races: [RaceGoal(name: "Half", distanceMiles: 13.1, date: "2026-10-10")])
        for q in StarterQuestions.suggestions(for: rich) {
            XCTAssertFalse(q.text.contains("—"), "\"\(q.text)\" uses an em dash")
        }
    }

    func testDeterministic() {
        let s = state(latestWorkout: workout(), workouts: [workout()])
        XCTAssertEqual(StarterQuestions.suggestions(for: s), StarterQuestions.suggestions(for: s))
    }
}
