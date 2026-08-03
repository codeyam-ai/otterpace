import XCTest
@testable import AppCore

/// How the journal changes coaching — and, more importantly, how it does NOT.
///
/// The load-bearing test here is `testEmptyJournalLeavesTheNudgeByteIdentical`:
/// every journal rule is layered below the existing safety rules and reads a
/// summary that is all-zero on an empty journal, so a user who has written
/// nothing must get exactly the coaching they got before this feature shipped.
final class JournalCoachingTests: XCTestCase {

    private let today = "2026-06-22"

    private func state(journal: [JournalEntry] = [],
                       steps: Int = 4000,
                       goalSteps: Int = 10000,
                       load: WeeklyLoad? = nil,
                       workout: LatestWorkout? = nil) -> TodayState {
        TodayState(healthKitConnected: true, date: today, steps: steps, goalSteps: goalSteps,
                   latestWorkout: workout, weeklyLoad: load, journal: journal)
    }

    private var steadyLoad: WeeklyLoad {
        WeeklyLoad(weeklyMileage: 14.6, daysRunThisWeek: 3, longestRunMiles: 6.1,
                   restDaysThisWeek: 2, loadTrend: "steady")
    }

    private func rough(_ date: String) -> JournalEntry {
        JournalEntry(date: date, feel: 2, energy: .low, soreness: .sore, sleep: .poor)
    }

    // MARK: The regression guard

    func testEmptyJournalLeavesTheNudgeByteIdentical() {
        let withoutJournal = state(load: steadyLoad)
        var withEmptyJournal = withoutJournal
        withEmptyJournal.journal = []

        let a = CoachEngine.dailyNudge(for: withoutJournal, asOf: today)
        let b = CoachEngine.dailyNudge(for: withEmptyJournal, asOf: today)
        XCTAssertEqual(a, b)
    }

    func testASingleRoughDayDoesNotChangeTheNudge() {
        // One bad day is just a day. The rule needs a pattern before it fires,
        // or the coach turns into a nag.
        let baseline = CoachEngine.dailyNudge(for: state(load: steadyLoad), asOf: today)
        let oneEntry = CoachEngine.dailyNudge(
            for: state(journal: [rough("2026-06-22")], load: steadyLoad), asOf: today)
        XCTAssertEqual(baseline, oneEntry)
    }

    // MARK: Rough patch softens the recommendation

    func testTwoRoughDaysSoftenTheRecommendation() {
        let nudge = CoachEngine.dailyNudge(
            for: state(journal: [rough("2026-06-22"), rough("2026-06-20")], load: steadyLoad),
            asOf: today)
        XCTAssertEqual(nudge.recommendationType, "rest")
        XCTAssertEqual(nudge.buddyMood, "recovery")
    }

    func testRoughPatchCopyReferencesWhatTheRunnerWrote() {
        let nudge = CoachEngine.dailyNudge(
            for: state(journal: [rough("2026-06-22"), rough("2026-06-20")], load: steadyLoad),
            asOf: today)
        XCTAssertTrue(nudge.body.lowercased().contains("sore") || nudge.body.lowercased().contains("rough"),
                      "the advice must be visibly grounded in what they logged: \(nudge.body)")
    }

    func testRoughPatchOutranksTheGoalCrushedCelebration() {
        // Clearing a step goal doesn't mean the week is going well. What the
        // runner said about feeling sore has to win over the confetti.
        let nudge = CoachEngine.dailyNudge(
            for: state(journal: [rough("2026-06-22"), rough("2026-06-20")],
                       steps: 12000, load: steadyLoad),
            asOf: today)
        XCTAssertNotEqual(nudge.recommendationType, "celebrate")
        XCTAssertEqual(nudge.buddyMood, "recovery")
    }

    func testOldRoughDaysOutsideTheWindowDoNotFire() {
        let stale = [rough("2026-06-01"), rough("2026-06-02")]
        let nudge = CoachEngine.dailyNudge(for: state(journal: stale, load: steadyLoad), asOf: today)
        XCTAssertEqual(nudge, CoachEngine.dailyNudge(for: state(load: steadyLoad), asOf: today),
                       "a rough patch three weeks ago is not today's story")
    }

    // MARK: Safety still wins

    func testASpikingLoadStillOutranksAGoodJournal() {
        let spiking = WeeklyLoad(weeklyMileage: 30, daysRunThisWeek: 6, longestRunMiles: 12,
                                 restDaysThisWeek: 0, loadTrend: "spiking")
        let happy = [JournalEntry(date: "2026-06-22", feel: 5, energy: .good, soreness: SorenessLevel.none, sleep: .good),
                     JournalEntry(date: "2026-06-21", feel: 5, energy: .good, soreness: SorenessLevel.none, sleep: .good)]
        let nudge = CoachEngine.dailyNudge(for: state(journal: happy, load: spiking), asOf: today)
        XCTAssertTrue(nudge.safetyFlag, "feeling great never licenses running through a load spike")
        XCTAssertEqual(nudge.recommendationType, "caution")
    }

    func testARecentHardEffortStillOutranksAGoodJournal() {
        let hard = LatestWorkout(type: "run", distanceMiles: 11, durationMinutes: 95,
                                 pace: "8:38/mi", date: "2026-06-21", source: "strava")
        let happy = [JournalEntry(date: "2026-06-22", feel: 5, soreness: SorenessLevel.none)]
        let nudge = CoachEngine.dailyNudge(
            for: state(journal: happy, load: steadyLoad, workout: hard), asOf: today)
        XCTAssertEqual(nudge.recommendationType, "rest")
    }

    // MARK: Strong days get affirmed

    func testAStrongDayAfterRestIsAffirmed() {
        let good = [JournalEntry(date: "2026-06-22", feel: 5, energy: .good, soreness: SorenessLevel.none, sleep: .good)]
        let nudge = CoachEngine.dailyNudge(for: state(journal: good, load: steadyLoad), asOf: today)
        XCTAssertEqual(nudge.buddyMood, "cheering")
        XCTAssertEqual(nudge.recommendationType, "run")
    }

    func testAStrongDayWithNoRestDayDoesNotFire() {
        // Without a rest day the affirmation would fire on every good run and
        // become noise, so it stays quiet.
        let noRest = WeeklyLoad(weeklyMileage: 14.6, daysRunThisWeek: 7, longestRunMiles: 6.1,
                                restDaysThisWeek: 0, loadTrend: "steady")
        let good = [JournalEntry(date: "2026-06-22", feel: 5, soreness: SorenessLevel.none)]
        let nudge = CoachEngine.dailyNudge(for: state(journal: good, load: noRest), asOf: today)
        XCTAssertNotEqual(nudge.buddyMood, "cheering")
    }

    // MARK: Weekly review

    func testWeeklyReviewIsUnchangedWithoutJournalEntries() {
        let base = state(load: steadyLoad)
        var withEmpty = base
        withEmpty.journal = []
        XCTAssertEqual(WeeklyReviewEngine.generate(from: base, asOf: today),
                       WeeklyReviewEngine.generate(from: withEmpty, asOf: today))
    }

    func testWeeklyReviewNamesAHardStretch() {
        let review = WeeklyReviewEngine.generate(
            from: state(journal: [rough("2026-06-22"), rough("2026-06-21")], load: steadyLoad),
            asOf: today)
        XCTAssertTrue(review.whatChanged.contains("sore"),
                      "the recap should say what the week actually felt like: \(review.whatChanged)")
    }

    func testWeeklyReviewCreditsAStrongWeek() {
        let strong = [JournalEntry(date: "2026-06-22", feel: 5, soreness: SorenessLevel.none),
                      JournalEntry(date: "2026-06-21", feel: 4, soreness: SorenessLevel.none)]
        let review = WeeklyReviewEngine.generate(from: state(journal: strong, load: steadyLoad), asOf: today)
        XCTAssertTrue(review.wentWell.contains("felt strong"),
                      "a week that felt good should say so: \(review.wentWell)")
    }

    func testWeeklyReviewNeverMentionsStreaksOrMissedDays() {
        // A journaling feature is exactly where a wellness app usually starts
        // shaming. Guard the copy directly.
        let review = WeeklyReviewEngine.generate(
            from: state(journal: [rough("2026-06-22")], load: steadyLoad), asOf: today)
        let all = [review.wentWell, review.whatChanged, review.trainingRisk,
                   review.nextWeek, review.focusArea].joined(separator: " ").lowercased()
        for banned in ["streak", "you haven't", "you have not", "missed", "don't forget", "remember to log"] {
            XCTAssertFalse(all.contains(banned), "recap must not shame the runner — found “\(banned)”")
        }
    }

    // MARK: The wire payload is bounded

    func testTheContextPutOnTheWireCarriesOnlyTheBoundedSlice() {
        let long = String(repeating: "b", count: 400)
        let entries = [JournalEntry(date: "2026-06-22", feel: 3, note: long),
                       JournalEntry(date: "2026-05-01", feel: 3, note: "way outside the window")]
        let bounded = RemoteCoach().bounded(state(journal: entries, load: steadyLoad))

        XCTAssertEqual(bounded.journal.count, 1, "only the trailing 14 days ride along")
        XCTAssertEqual(bounded.journal.first?.note?.count, Journal.coachNoteLimit + 1)
    }

    func testBoundingLeavesEveryOtherFieldUntouched() {
        let context = state(journal: [JournalEntry(date: "2026-06-22", feel: 3)], load: steadyLoad)
        let bounded = RemoteCoach().bounded(context)
        XCTAssertEqual(bounded.weeklyLoad, context.weeklyLoad)
        XCTAssertEqual(bounded.steps, context.steps)
        XCTAssertEqual(bounded.date, context.date)
    }

    func testBoundingAnEmptyJournalIsAPassThrough() {
        let context = state(load: steadyLoad)
        XCTAssertEqual(RemoteCoach().bounded(context), context)
    }
}
