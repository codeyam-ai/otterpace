import XCTest
@testable import AppCore

// Buddy's scripted opening in the Coach tab.
//
// The copy is app-authored, so the honesty constraints are testable: it must not
// promise run analysis on a day-one install, and the locked variant must point at
// the connect step rather than inviting a question the app cannot answer.
final class CoachTutorialTests: XCTestCase {

    private func dayOne() -> TodayState {
        TodayState(healthKitConnected: true, date: "2026-06-22", steps: 1200)
    }

    private func rich() -> TodayState {
        let w = LatestWorkout(type: "run", distanceMiles: 4.2, durationMinutes: 44,
                              pace: "10:28/mi", date: "2026-06-21", source: "healthkit")
        return TodayState(healthKitConnected: true,
                          date: "2026-06-22",
                          steps: 9180,
                          latestWorkout: w,
                          weeklyLoad: WeeklyLoad(weeklyMileage: 12.4, daysRunThisWeek: 3,
                                                 longestRunMiles: 5.0, restDaysThisWeek: 2,
                                                 loadTrend: "steady"),
                          workouts: [w],
                          loadHistory: [WeeklyLoadPoint(weekStartISO: "2026-06-15", miles: 12.4, daysRun: 3)],
                          races: [RaceGoal(name: "October Trail Half", distanceMiles: 13.1, date: "2026-10-10")])
    }

    func testOpeningTurnsAreNonEmptyForBothStates() {
        for connected in [true, false] {
            for context in [dayOne(), rich()] {
                let turns = CoachTutorial.openingTurns(for: context, connected: connected)
                XCTAssertGreaterThanOrEqual(turns.count, 2)
                for t in turns {
                    XCTAssertFalse(t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    func testIntroducesBuddyByName() {
        let turns = CoachTutorial.openingTurns(for: rich(), connected: true)
        XCTAssertTrue(turns.contains { $0.contains("Buddy") },
                      "The intro never says who the user is talking to.")
    }

    /// The whole point of the data turn: say what Buddy can actually see.
    func testNamesWhatItCanSee() {
        let turns = CoachTutorial.openingTurns(for: rich(), connected: true)
        let all = turns.joined(separator: " ")
        XCTAssertTrue(all.contains("steps"))
        XCTAssertTrue(all.contains("runs"))
    }

    /// A day-one install has no runs, so the intro must not claim to analyze them.
    func testDayOneDoesNotPromiseRunAnalysis() {
        let all = CoachTutorial.openingTurns(for: dayOne(), connected: true).joined(separator: " ")
        XCTAssertTrue(all.contains("Once you log"),
                      "Day one should set expectations about runs it cannot see yet.")
        XCTAssertFalse(all.contains("your recent runs and walks"),
                       "Day one claims to see runs that do not exist.")
    }

    func testRichStateDescribesRealData() {
        let all = CoachTutorial.openingTurns(for: rich(), connected: true).joined(separator: " ")
        XCTAssertTrue(all.contains("your recent runs and walks"))
        XCTAssertFalse(all.contains("Once you log"))
    }

    /// Locked: point at the connect step, never at "ask me something".
    func testLockedVariantNamesTheConnectStep() {
        let locked = CoachTutorial.openingTurns(for: rich(), connected: false).joined(separator: " ")
        XCTAssertTrue(locked.contains("Settings"), "Locked intro should name where to connect a key.")

        let unlocked = CoachTutorial.openingTurns(for: rich(), connected: true).joined(separator: " ")
        XCTAssertTrue(unlocked.contains("Tap one of the questions"),
                      "Unlocked intro should invite a question.")
    }

    /// Coaching is not medical advice, and the intro is where that is set.
    func testStatesTheSafetyBoundary() {
        let all = CoachTutorial.openingTurns(for: rich(), connected: true).joined(separator: " ")
        XCTAssertTrue(all.lowercased().contains("not a doctor"))
    }

    func testNoEmDashes() {
        for connected in [true, false] {
            for context in [dayOne(), rich()] {
                for t in CoachTutorial.openingTurns(for: context, connected: connected) {
                    XCTAssertFalse(t.contains("—"), "\"\(t)\" uses an em dash")
                }
            }
        }
    }

    /// No dangling separators from the list builder.
    func testDataTurnReadsAsASentence() {
        for context in [dayOne(), rich()] {
            for t in CoachTutorial.openingTurns(for: context, connected: true) {
                XCTAssertFalse(t.contains(" ,"), "\"\(t)\" has a stray separator")
                XCTAssertFalse(t.contains(",."), "\"\(t)\" has a stray separator")
                XCTAssertFalse(t.contains("and ,"), "\"\(t)\" has a stray separator")
            }
        }
    }

    func testDeterministic() {
        XCTAssertEqual(CoachTutorial.openingTurns(for: rich(), connected: true),
                       CoachTutorial.openingTurns(for: rich(), connected: true))
    }
}
