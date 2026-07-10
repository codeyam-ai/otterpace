import XCTest
@testable import AppCore

// XCTest (not swift-testing) so results land in the editor's --xunit-output file.
final class ActivityHistoryTests: XCTestCase {

    private func wk(_ type: String, _ miles: Double, _ date: String, dur: Int = 40, src: String = "healthkit") -> LatestWorkout {
        LatestWorkout(type: type, distanceMiles: miles, durationMinutes: dur, pace: "10:00/mi", date: date, source: src)
    }

    // An empty workout list yields no week groups.
    func testEmptyYieldsNoGroups() {
        XCTAssertTrue(ActivityHistory.groupByWeek([]).isEmpty)
    }

    // Workouts in the same ISO week collapse into one group.
    func testSameWeekGroupsTogether() {
        // 2026-06-16 (Tue) and 2026-06-21 (Sun) are in the same Monday-start week.
        let groups = ActivityHistory.groupByWeek([wk("run", 3.0, "2026-06-16"), wk("walk", 2.0, "2026-06-21")])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].workouts.count, 2)
    }

    // Workouts in different weeks produce separate groups, newest week first.
    func testDifferentWeeksNewestFirst() {
        let groups = ActivityHistory.groupByWeek([wk("run", 3.0, "2026-06-09"), wk("run", 4.0, "2026-06-21")])
        XCTAssertEqual(groups.count, 2)
        XCTAssertGreaterThan(groups[0].weekStartISO, groups[1].weekStartISO)
    }

    // Total mileage sums every workout in the week.
    func testTotalMilesSums() {
        let groups = ActivityHistory.groupByWeek([wk("run", 4.2, "2026-06-21"), wk("walk", 2.0, "2026-06-19"), wk("run", 3.5, "2026-06-16")])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].totalMiles, 9.7, accuracy: 0.001)
    }

    // Run count includes only run-type workouts, not walks or rides.
    func testRunCountExcludesNonRuns() {
        let groups = ActivityHistory.groupByWeek([wk("run", 4.0, "2026-06-21"), wk("walk", 2.0, "2026-06-20"), wk("ride", 12.0, "2026-06-19")])
        XCTAssertEqual(groups[0].runCount, 1)
    }

    // Rest days are seven minus the number of distinct active days.
    func testRestDaysFromDistinctActiveDays() {
        // Three workouts across two distinct days => 5 rest days.
        let groups = ActivityHistory.groupByWeek([wk("run", 3.0, "2026-06-21"), wk("walk", 1.0, "2026-06-21"), wk("run", 4.0, "2026-06-18")])
        XCTAssertEqual(groups[0].restDays, 5)
    }

    // A full seven distinct active days leaves zero rest days, never negative.
    func testRestDaysNeverNegative() {
        let week = (15...21).map { wk("run", 3.0, "2026-06-\($0)") }  // Mon..Sun
        let groups = ActivityHistory.groupByWeek(week)
        XCTAssertEqual(groups[0].restDays, 0)
    }

    // Workouts with an unparseable date are dropped rather than crashing.
    func testInvalidDateDropped() {
        let groups = ActivityHistory.groupByWeek([wk("run", 3.0, "not-a-date"), wk("run", 4.0, "2026-06-21")])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].workouts.count, 1)
    }

    // Within a week, workouts are ordered newest-first by date.
    func testWithinWeekNewestFirst() {
        let groups = ActivityHistory.groupByWeek([wk("run", 3.0, "2026-06-16"), wk("run", 4.0, "2026-06-21")])
        XCTAssertEqual(groups[0].workouts.first?.date, "2026-06-21")
    }

    // The model decodes a seeded rbWorkoutsJSON list into the today state.
    func testModelDecodesWorkoutsJSON() {
        let suite = "ActivityHistoryTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        d.set(true, forKey: "rbConnected")
        d.set("[{\"type\":\"run\",\"distanceMiles\":4.2,\"durationMinutes\":44,\"pace\":\"10:00/mi\",\"date\":\"2026-06-21\",\"source\":\"strava\"}]", forKey: "rbWorkoutsJSON")
        let state = OtterpaceModel.readState(defaults: d)
        XCTAssertEqual(state.workouts.count, 1)
        XCTAssertEqual(state.workouts.first?.type, "run")
        XCTAssertEqual(state.workouts.first?.distanceMiles ?? 0, 4.2, accuracy: 0.001)
    }

    // With no rbWorkoutsJSON seeded, the workouts list is empty (day-one).
    func testModelEmptyWhenUnseeded() {
        let suite = "ActivityHistoryTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertTrue(OtterpaceModel.readState(defaults: d).workouts.isEmpty)
    }

    // MARK: weeklyLoad(from:asOf:) — the live HealthKit/Strava derivation (SW-1)

    // A fixed reference day inside the week of Mon 2026-06-22 (UTC ISO week).
    private static let asOf: Date = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: "2026-06-24")!   // Wednesday
    }()

    // Only the week containing `asOf` feeds the rollup; mileage, longest run,
    // run-days and rest-days come from that week alone.
    func testWeeklyLoadRollsUpCurrentWeek() {
        let load = ActivityHistory.weeklyLoad(from: [
            wk("run", 4.0, "2026-06-22"),   // current week (Mon)
            wk("run", 6.0, "2026-06-24"),   // current week (Wed) — longest
            wk("walk", 2.0, "2026-06-24"),  // same day, not a run
            wk("run", 9.0, "2026-06-15"),   // previous week — excluded from the rollup
        ], asOf: Self.asOf)
        XCTAssertEqual(load.weeklyMileage, 12.0, accuracy: 0.001)  // 4+6+2
        XCTAssertEqual(load.longestRunMiles, 6.0, accuracy: 0.001)
        XCTAssertEqual(load.daysRunThisWeek, 2)                    // Mon + Wed
        XCTAssertEqual(load.restDaysThisWeek, 5)                   // 7 - 2 active days
    }

    // A later reference day inside the same week (Sun), used to test the mid-week
    // guard: a down week only reads "recovering" once the week is mostly elapsed.
    private static let asOfSun: Date = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: "2026-06-28")!   // Sunday of the current week
    }()

    // Three prior weeks at a flat baseline, then a sudden 2x jump this week, is a
    // GENUINE spike against the multi-week baseline.
    func testWeeklyLoadSpikingVsBaseline() {
        let load = ActivityHistory.weeklyLoad(from: [
            wk("run", 5.0, "2026-06-01"),
            wk("run", 5.0, "2026-06-08"),
            wk("run", 5.0, "2026-06-15"),
            wk("run", 10.0, "2026-06-23"),   // current, chronic 5 => ratio 2.0
        ], asOf: Self.asOf)
        XCTAssertEqual(load.loadTrend, "spiking")
    }

    // A steady, progressive climb reads as "building", NOT "spiking" — the core
    // trustworthy-coaching fix (a ~10-25% rise above the baseline is the plan working).
    func testWeeklyLoadSteadyClimbIsBuilding() {
        let load = ActivityHistory.weeklyLoad(from: [
            wk("run", 14.0, "2026-06-01"),
            wk("run", 16.0, "2026-06-08"),
            wk("run", 18.0, "2026-06-15"),
            wk("run", 20.0, "2026-06-23"),   // current, chronic 16 => ratio 1.25
        ], asOf: Self.asOf)
        XCTAssertEqual(load.loadTrend, "building")
    }

    // A normal week following a deliberate CUTBACK week is NOT a false spike. The
    // old 2-week ratio (18/12 = 1.5) tripped "spiking"; the multi-week baseline
    // (18 vs ~17.3 avg) correctly reads it as steady. This is the reported bug.
    func testWeeklyLoadNormalWeekAfterCutbackIsNotSpike() {
        let load = ActivityHistory.weeklyLoad(from: [
            wk("run", 20.0, "2026-06-01"),
            wk("run", 20.0, "2026-06-08"),
            wk("run", 12.0, "2026-06-15"),  // cutback week
            wk("run", 18.0, "2026-06-23"),  // current, back to normal
        ], asOf: Self.asOf)
        XCTAssertNotEqual(load.loadTrend, "spiking")
        XCTAssertEqual(load.loadTrend, "steady")
    }

    // A deliberate down week vs. a solid baseline reads "recovering" — but only
    // once the week is mostly elapsed (asOf Sunday).
    func testWeeklyLoadRecoveringWhenWeekMostlyElapsed() {
        let load = ActivityHistory.weeklyLoad(from: [
            wk("run", 20.0, "2026-06-01"),
            wk("run", 20.0, "2026-06-08"),
            wk("run", 20.0, "2026-06-15"),
            wk("run", 8.0, "2026-06-22"),   // current, chronic 20 => ratio 0.4
        ], asOf: Self.asOfSun)
        XCTAssertEqual(load.loadTrend, "recovering")
    }

    // The SAME down-week data early in the week (asOf Wed) is NOT called
    // "recovering" — the partial week just hasn't accumulated yet (mid-week guard).
    func testWeeklyLoadMidWeekGuardSuppressesRecovering() {
        let workouts = [
            wk("run", 20.0, "2026-06-01"),
            wk("run", 20.0, "2026-06-08"),
            wk("run", 20.0, "2026-06-15"),
            wk("run", 8.0, "2026-06-22"),
        ]
        XCTAssertEqual(ActivityHistory.weeklyLoad(from: workouts, asOf: Self.asOf).loadTrend, "steady")
    }

    // Too little history to form a baseline (one prior week) is honest "insufficient"
    // rather than a guessed verdict.
    func testWeeklyLoadInsufficientWithThinHistory() {
        let load = ActivityHistory.weeklyLoad(from: [
            wk("run", 10.0, "2026-06-15"),  // only one prior week
            wk("run", 12.0, "2026-06-23"),  // current
        ], asOf: Self.asOf)
        XCTAssertEqual(load.loadTrend, "insufficient")
    }

    // Activity this week with NO prior history is also "insufficient" — we don't
    // know the user's baseline yet, so we abstain instead of calling it "building".
    func testWeeklyLoadInsufficientFromFirstWeek() {
        let load = ActivityHistory.weeklyLoad(from: [wk("run", 4.0, "2026-06-23")], asOf: Self.asOf)
        XCTAssertEqual(load.loadTrend, "insufficient")
    }

    // No workouts at all: an all-rest week, steady, nothing logged.
    func testWeeklyLoadEmptyIsRestWeek() {
        let load = ActivityHistory.weeklyLoad(from: [], asOf: Self.asOf)
        XCTAssertEqual(load.weeklyMileage, 0)
        XCTAssertEqual(load.daysRunThisWeek, 0)
        XCTAssertEqual(load.restDaysThisWeek, 7)
        XCTAssertEqual(load.loadTrend, "steady")
    }

    // MARK: loadHistory(from:maxWeeks:) — the coach-facing weekly series

    // The series has one point per week, newest week first, with summed mileage.
    func testLoadHistoryNewestFirstPerWeek() {
        let series = ActivityHistory.loadHistory(from: [
            wk("run", 4.0, "2026-06-22"), wk("walk", 2.0, "2026-06-23"),  // week of 06-22 => 6.0
            wk("run", 10.0, "2026-06-15"),                                 // week of 06-15 => 10.0
            wk("run", 8.0, "2026-06-08"),                                  // week of 06-08 => 8.0
        ])
        XCTAssertEqual(series.count, 3)
        XCTAssertEqual(series[0].weekStartISO, "2026-06-22")
        XCTAssertEqual(series[0].miles, 6.0, accuracy: 0.001)
        XCTAssertGreaterThan(series[0].weekStartISO, series[1].weekStartISO)
    }

    // daysRun counts DISTINCT run days, not run workouts, and ignores non-runs.
    func testLoadHistoryDaysRunDistinct() {
        let series = ActivityHistory.loadHistory(from: [
            wk("run", 3.0, "2026-06-22"), wk("run", 2.0, "2026-06-22"),  // two runs, one day
            wk("walk", 1.0, "2026-06-24"),                                // walk, not a run day
        ])
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0].daysRun, 1)
    }

    // The series is capped to maxWeeks (most recent weeks kept).
    func testLoadHistoryCapsToMaxWeeks() {
        let weeks = ["2026-06-22", "2026-06-15", "2026-06-08", "2026-06-01"].map { wk("run", 5.0, $0) }
        let series = ActivityHistory.loadHistory(from: weeks, maxWeeks: 2)
        XCTAssertEqual(series.count, 2)
        XCTAssertEqual(series[0].weekStartISO, "2026-06-22")   // newest kept
        XCTAssertEqual(series[1].weekStartISO, "2026-06-15")
    }

    // No workouts yields an empty series (not shared with the coach).
    func testLoadHistoryEmpty() {
        XCTAssertTrue(ActivityHistory.loadHistory(from: []).isEmpty)
    }
}
