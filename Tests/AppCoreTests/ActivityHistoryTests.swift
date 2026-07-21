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

    // A seeded weekly load carries only the flat rb* primitives, so the elapsed /
    // trailing-window fields have to be derived from the seeded workouts. Without
    // this a scenario could never show the in-progress or rolling-window states
    // that the real HealthKit path produces.
    func testSeededLoadDerivesElapsedAndRollingWindow() {
        let suite = "ActivityHistoryTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        d.set(true, forKey: "rbConnected")
        d.set("2026-06-23", forKey: "rbDate")          // Tuesday
        d.set("building", forKey: "rbLoadTrend")        // anchor key for the load group
        d.set(1, forKey: "rbDaysRunThisWeek")
        d.set(3.1, forKey: "rbWeeklyMileage")
        d.set("""
        [{"type":"run","distanceMiles":3.1,"durationMinutes":32,"pace":"10:19/mi","date":"2026-06-22","source":"healthkit"},\
        {"type":"run","distanceMiles":4.2,"durationMinutes":44,"pace":"10:28/mi","date":"2026-06-21","source":"strava"},\
        {"type":"run","distanceMiles":5.0,"durationMinutes":52,"pace":"10:24/mi","date":"2026-06-20","source":"strava"}]
        """, forKey: "rbWorkoutsJSON")

        let load = OtterpaceModel.readState(defaults: d).weeklyLoad
        XCTAssertEqual(load?.daysElapsedThisWeek, 2)     // Mon=1, Tue=2
        XCTAssertEqual(load?.rolling7DaysRun, 3)         // Sat + Sun + Mon
        XCTAssertEqual(load?.rolling7Miles ?? 0, 12.3, accuracy: 0.001)
    }

    // A seeded load with NO workouts keeps the defaults, so the existing
    // load-only Weekly Review scenarios are unchanged by the derivation above.
    func testSeededLoadWithoutWorkoutsKeepsDefaults() {
        let suite = "ActivityHistoryTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        d.set(true, forKey: "rbConnected")
        d.set("recovering", forKey: "rbLoadTrend")
        d.set(1, forKey: "rbDaysRunThisWeek")

        let load = OtterpaceModel.readState(defaults: d).weeklyLoad
        XCTAssertEqual(load?.daysElapsedThisWeek, 7)
        XCTAssertEqual(load?.rolling7DaysRun, 0)
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
        // Elapsed-aware: by Wednesday only 3 days have happened, 2 of them active,
        // so 1 rest day so far — Thu-Sun are not rest the user has chosen yet.
        XCTAssertEqual(load.restDaysThisWeek, 1)
        XCTAssertEqual(load.daysElapsedThisWeek, 3)                // Mon=1, Wed=3
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

    // No workouts at all: an all-rest week so far, steady, nothing logged. Rest
    // counts only COMPLETED days, so a blank Wednesday reads 2 (Mon + Tue), not a
    // full 7 that claims days the user has not reached, and not 3 — Wednesday is
    // still open, so it isn't a rest day yet.
    func testWeeklyLoadEmptyIsRestWeek() {
        let load = ActivityHistory.weeklyLoad(from: [], asOf: Self.asOf)
        XCTAssertEqual(load.weeklyMileage, 0)
        XCTAssertEqual(load.daysRunThisWeek, 0)
        XCTAssertEqual(load.restDaysThisWeek, 2)
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

    // MARK: Elapsed-aware weeks + the trailing 7-day window

    // Only the IN-PROGRESS week is capped at elapsed days. A finished week keeps
    // its honest 7 - activeDays, so history doesn't get retroactively rewritten.
    func testCompletedWeeksKeepFullRestDays() {
        let groups = ActivityHistory.groupByWeek([
            wk("run", 4.0, "2026-06-22"),   // week of Jun 22 — in progress on Wed Jun 24
            wk("run", 5.0, "2026-06-15"),   // week of Jun 15 — finished
        ], asOf: Self.asOf)

        let current = groups.first { $0.weekStartISO == "2026-06-22" }
        let finished = groups.first { $0.weekStartISO == "2026-06-15" }
        XCTAssertEqual(current?.daysElapsed, 3)
        // Mon + Tue are complete; Mon was active, so 1 rest so far. Wednesday is
        // still open and is not counted.
        XCTAssertEqual(current?.restDays, 1)
        XCTAssertEqual(finished?.daysElapsed, 7)
        XCTAssertEqual(finished?.restDays, 6)     // 7 - 1 active, unchanged
    }

    // The Monday-reset blind spot: a strong Sat/Sun plus a Monday run is barely
    // visible in the calendar week on Tuesday, but the rolling window still sees
    // all three days. This is the signal that stops the false "quiet week".
    func testRollingSevenDaySurvivesTheMondayReset() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        let tuesday = f.date(from: "2026-06-23")!

        let workouts = [
            wk("run", 3.1, "2026-06-22"),   // Mon — the only run in the calendar week
            wk("run", 4.2, "2026-06-21"),   // Sun — previous calendar week
            wk("run", 5.0, "2026-06-20"),   // Sat — previous calendar week
        ]
        let load = ActivityHistory.weeklyLoad(from: workouts, asOf: tuesday)

        XCTAssertEqual(load.daysRunThisWeek, 1)        // calendar week sees one run
        XCTAssertEqual(load.daysElapsedThisWeek, 2)    // Mon=1, Tue=2
        // Only Monday is complete and Monday was active, so zero rest days so
        // far — not 6, and not 1, because Tuesday is still open.
        XCTAssertEqual(load.restDaysThisWeek, 0)
        XCTAssertEqual(load.rolling7DaysRun, 3)        // rolling window sees all three
        XCTAssertEqual(load.rolling7Miles, 12.3, accuracy: 0.001)
    }

    // Today's mileage and runs count immediately, but today is not a rest day
    // until it is over. Ran Wednesday (today) having rested Mon+Tue: the miles
    // land right away, and the two genuinely-rested completed days still read as
    // rest — a run logged today must not cancel out earlier rest days.
    func testTodayCountsAsMileageButNotAsRest() {
        let groups = ActivityHistory.groupByWeek([
            wk("run", 5.0, "2026-06-24"),   // today (Wed)
        ], asOf: Self.asOf)

        let current = groups.first { $0.weekStartISO == "2026-06-22" }
        XCTAssertEqual(current?.totalMiles ?? 0, 5.0, accuracy: 0.001)  // counts now
        XCTAssertEqual(current?.runCount, 1)                            // counts now
        XCTAssertEqual(current?.restDays, 2)                            // Mon + Tue only
        XCTAssertEqual(current?.daysElapsed, 3)
    }

    // The mirror case: resting today after running earlier. Monday was active and
    // Tuesday was not, so exactly one completed rest day, with Wednesday still open.
    func testRestTodayDoesNotCountUntilDayEnds() {
        let groups = ActivityHistory.groupByWeek([
            wk("run", 4.0, "2026-06-22"),   // Mon
        ], asOf: Self.asOf)

        let current = groups.first { $0.weekStartISO == "2026-06-22" }
        XCTAssertEqual(current?.restDays, 1)   // Tue only; Wed is not yet rest
    }

    // The rolling window is inclusive of the reference day and stops at 7 days
    // back, so an 8-day-old run is excluded while a same-day run counts.
    func testRollingSevenDayWindowBounds() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        let asOf = f.date(from: "2026-06-24")!

        let r = ActivityHistory.rollingSevenDay(from: [
            wk("run", 2.0, "2026-06-24"),   // today — included
            wk("run", 3.0, "2026-06-18"),   // 6 days back — included
            wk("run", 9.0, "2026-06-17"),   // 7 days back — outside the window
        ], asOf: asOf)

        XCTAssertEqual(r.daysRun, 2)
        XCTAssertEqual(r.miles, 5.0, accuracy: 0.001)
        XCTAssertEqual(r.longestRunMiles, 3.0, accuracy: 0.001)
    }
}
