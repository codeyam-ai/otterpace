import XCTest
@testable import AppCore

// Covers the pure binning + layout behind the Activity History progress heatmap:
// Monday-start week columns, per-metric binning, range spans, and the rules that
// keep a rest day and an unparseable date from being confused with each other.
final class ActivityHeatmapTests: XCTestCase {

    // Mon 2026-06-22 is the anchor "today" used across these tests; the ISO week
    // containing it starts Mon 2026-06-22.
    private let todayISO = "2026-06-22"

    private func workout(_ date: String, miles: Double, minutes: Int, type: String = "run") -> LatestWorkout {
        LatestWorkout(type: type, distanceMiles: miles, durationMinutes: minutes,
                      pace: "10:00/mi", date: date, source: "healthkit")
    }

    // Every range renders full 7-day weeks, so the grid is always rectangular.
    func testGridIsRectangularMondayStartWeeks() {
        for range in HeatmapRange.allCases {
            let grid = ActivityHeatmap.heatmap(workouts: [], range: range, todayISO: todayISO)
            XCTAssertEqual(grid.count, range.weekCount, "\(range) week count")
            XCTAssertTrue(grid.allSatisfy { $0.count == 7 }, "\(range) rows are 7 days")
            // Oldest week first, and each week starts on a Monday.
            XCTAssertEqual(grid.last?.first?.dateISO, "2026-06-22", "\(range) current week starts Monday")
        }
    }

    // The distance metric bins by miles, relative to the busiest visible day.
    func testDistanceMetricBinsRelativeToWindowMax() {
        let grid = ActivityHeatmap.heatmap(
            workouts: [workout("2026-06-22", miles: 8, minutes: 80),   // window max -> level 4
                       workout("2026-06-24", miles: 2, minutes: 20)],  // 25% -> level 1
            metric: .distance, range: .week, todayISO: todayISO)

        let week = grid[0]
        XCTAssertEqual(week[0].level, 4, "busiest day is the top level")
        XCTAssertEqual(week[2].level, 1, "a quarter of the max bins to level 1")
        XCTAssertEqual(week[1].level, 0, "a rest day is level 0")
    }

    // Active minutes bins by duration and is independent of distance — a slow
    // long walk should read as a real day even though its mileage is modest.
    func testActiveMinutesMetricIsIndependentOfDistance() {
        let workouts = [workout("2026-06-22", miles: 8, minutes: 40),   // fast: most miles, fewest minutes
                        workout("2026-06-23", miles: 2, minutes: 80)]   // slow walk: most minutes
        let byDistance = ActivityHeatmap.heatmap(workouts: workouts, metric: .distance,
                                                 range: .week, todayISO: todayISO)[0]
        let byMinutes = ActivityHeatmap.heatmap(workouts: workouts, metric: .activeMinutes,
                                                range: .week, todayISO: todayISO)[0]

        XCTAssertEqual(byDistance[0].level, 4, "8 mi is the distance max")
        XCTAssertEqual(byMinutes[1].level, 4, "80 min is the active-minutes max")
        XCTAssertLessThan(byMinutes[0].level, byMinutes[1].level,
                          "the shorter-duration day ranks lower on active minutes")
    }

    // Steps bin against the goal, not the window max, so "hit 10k" is absolute.
    func testStepsMetricBinsAgainstGoal() {
        let grid = ActivityHeatmap.heatmap(
            workouts: [],
            dailySteps: ["2026-06-22": 10_000,   // exactly goal -> top
                         "2026-06-23": 5_000,    // half -> level 2
                         "2026-06-24": 12_500],  // over goal -> still top, not level 5
            goalSteps: 10_000, metric: .stepsGoal, range: .week, todayISO: todayISO)

        let week = grid[0]
        XCTAssertEqual(week[0].level, 4, "hitting the goal is the top level")
        XCTAssertEqual(week[1].level, 2, "half the goal bins to level 2")
        XCTAssertEqual(week[2].level, ActivityHeatmap.maxLevel, "over goal clamps to max")
    }

    // With no seeded step series the steps metric is empty rather than a wall of
    // zero-step days that would imply the user never moved.
    func testStepsMetricWithoutSeriesIsEmpty() {
        let grid = ActivityHeatmap.heatmap(
            workouts: [workout("2026-06-22", miles: 5, minutes: 50)],
            dailySteps: [:], metric: .stepsGoal, range: .week, todayISO: todayISO)

        XCTAssertTrue(ActivityHeatmap.isEmpty(grid),
                      "workouts must not leak into the steps metric")
    }

    // Range changes the visible span while keeping day-granular cells.
    func testRangeChangesVisibleSpanOnly() {
        let workouts = [workout("2026-06-22", miles: 5, minutes: 50),   // this week
                        workout("2026-05-20", miles: 4, minutes: 40)]   // ~5 weeks back

        let week = ActivityHeatmap.heatmap(workouts: workouts, range: .week, todayISO: todayISO)
        let quarter = ActivityHeatmap.heatmap(workouts: workouts, range: .threeMonth, todayISO: todayISO)

        XCTAssertEqual(week.flatMap { $0 }.count, 7)
        XCTAssertEqual(quarter.flatMap { $0 }.count, 13 * 7)
        // The older workout is outside the 1-week window but inside the 3-month one.
        XCTAssertEqual(week.flatMap { $0 }.filter { $0.level > 0 }.count, 1)
        XCTAssertEqual(quarter.flatMap { $0 }.filter { $0.level > 0 }.count, 2)
    }

    // Unparseable dates are dropped exactly as ActivityHistory.groupByWeek drops
    // them, rather than crashing or landing on an arbitrary day.
    func testUnparseableDatesAreDropped() {
        let grid = ActivityHeatmap.heatmap(
            workouts: [workout("not-a-date", miles: 9, minutes: 90),
                       workout("2026-06-22", miles: 3, minutes: 30)],
            range: .week, todayISO: todayISO)

        let active = grid.flatMap { $0 }.filter { $0.level > 0 }
        XCTAssertEqual(active.count, 1, "only the parseable workout is placed")
        XCTAssertEqual(active.first?.dateISO, "2026-06-22")
    }

    // Multiple workouts on one day sum into a single cell.
    func testSameDayWorkoutsAccumulate() {
        let grid = ActivityHeatmap.heatmap(
            workouts: [workout("2026-06-22", miles: 3, minutes: 30),
                       workout("2026-06-22", miles: 2, minutes: 20, type: "walk")],
            metric: .distance, range: .week, todayISO: todayISO)

        XCTAssertEqual(grid[0][0].value, 5, "both workouts land on the same cell")
    }

    // A day with any activity is never level 0, so a short recovery walk still
    // shows up instead of reading as a rest day.
    func testAnyActivityIsAtLeastLevelOne() {
        let grid = ActivityHeatmap.heatmap(
            workouts: [workout("2026-06-22", miles: 20, minutes: 200),  // huge max
                       workout("2026-06-25", miles: 0.3, minutes: 6)],  // tiny walk
            metric: .distance, range: .week, todayISO: todayISO)

        XCTAssertEqual(grid[0][3].level, 1, "a tiny day still registers")
    }

    // Day one: no workouts and no steps means an empty grid, which drives the
    // friendly Buddy empty state rather than a month of blank cells.
    func testDayOneIsEmpty() {
        let grid = ActivityHeatmap.heatmap(workouts: [], dailySteps: [:],
                                           range: .month, todayISO: todayISO)
        XCTAssertEqual(grid.count, 4, "the rectangle still exists")
        XCTAssertTrue(ActivityHeatmap.isEmpty(grid), "but nothing is active in it")
    }

    // An unparseable anchor yields no grid rather than silently anchoring on now,
    // which would make a seeded scenario capture differently over time.
    func testUnparseableTodayYieldsNoGrid() {
        let grid = ActivityHeatmap.heatmap(workouts: [], range: .month, todayISO: "")
        XCTAssertTrue(grid.isEmpty)
    }

    // MARK: Month markers

    // A month label appears only on the row where the month changes, so a long
    // span reads as "Mar / Apr / May / Jun" instead of repeating every row.
    func testMonthLabelsMarkOnlyMonthBoundaries() {
        let grid = ActivityHeatmap.heatmap(workouts: [], range: .threeMonth, todayISO: todayISO)
        let labels = ActivityHeatmap.monthLabels(for: grid)

        XCTAssertEqual(labels.count, grid.count, "one slot per week row")
        XCTAssertNotNil(labels.first!, "the first row is always labeled")
        let named = labels.compactMap { $0 }
        XCTAssertEqual(named, ["Mar", "Apr", "May", "Jun"], "each month named once, in order")
    }

    // A single-week span still names its month rather than rendering unlabeled.
    func testMonthLabelsOnSingleWeek() {
        let grid = ActivityHeatmap.heatmap(workouts: [], range: .week, todayISO: todayISO)
        XCTAssertEqual(ActivityHeatmap.monthLabels(for: grid), ["Jun"])
    }

    // MARK: Tapped-day detail

    // Tapping a day with workouts reports each one plus the day's totals.
    func testDaySummaryReportsThatDaysWorkouts() {
        let summary = ActivityHeatmap.daySummary(
            dateISO: "2026-06-22",
            workouts: [workout("2026-06-22", miles: 3, minutes: 30),
                       workout("2026-06-22", miles: 2, minutes: 25, type: "walk"),
                       workout("2026-06-21", miles: 9, minutes: 90)])

        XCTAssertEqual(summary?.title, "Mon, Jun 22")
        XCTAssertEqual(summary?.workouts.count, 2, "only that day's workouts")
        XCTAssertEqual(summary?.totalMiles, 5)
        XCTAssertEqual(summary?.totalMinutes, 55)
        XCTAssertEqual(summary?.isRestDay, false)
    }

    // A day with no workouts is a rest day, not an error or a missing summary —
    // rest is a legitimate part of a training week in this app.
    func testDaySummaryForRestDay() {
        let summary = ActivityHeatmap.daySummary(
            dateISO: "2026-06-23",
            workouts: [workout("2026-06-22", miles: 3, minutes: 30)])

        XCTAssertEqual(summary?.isRestDay, true)
        XCTAssertEqual(summary?.totalMiles, 0)
        XCTAssertEqual(summary?.title, "Tue, Jun 23")
    }

    // An unparseable date yields nil so the view can just clear the selection.
    func testDaySummaryRejectsUnparseableDate() {
        XCTAssertNil(ActivityHeatmap.daySummary(dateISO: "nope", workouts: []))
    }
}
