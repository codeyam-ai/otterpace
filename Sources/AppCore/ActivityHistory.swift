import Foundation

// MARK: - Activity history grouping
//
// Pure, deterministic logic behind the Activity History screen: take a flat,
// newest-first list of workouts and roll it up into per-week groups with the
// training-load basics (Milestone 4) — weekly mileage, run count, and rest
// days. No SwiftUI, no I/O, so it's straightforward to unit-test. The grouping
// uses a fixed Monday-start, POSIX calendar so the same workouts always produce
// the same weeks regardless of the device locale.

/// One week's worth of workouts plus its rolled-up training-load basics.
public struct WeekGroup: Equatable, Identifiable {
    public var id: String { weekStartISO }
    public var weekStartISO: String      // ISO date of the Monday that starts the week
    public var title: String             // human label, e.g. "Week of Jun 16"
    public var workouts: [LatestWorkout]  // newest-first within the week
    public var totalMiles: Double
    public var runCount: Int
    public var restDays: Int             // 7 minus the number of distinct active days

    public init(weekStartISO: String, title: String, workouts: [LatestWorkout],
                totalMiles: Double, runCount: Int, restDays: Int) {
        self.weekStartISO = weekStartISO
        self.title = title
        self.workouts = workouts
        self.totalMiles = totalMiles
        self.runCount = runCount
        self.restDays = restDays
    }
}

public enum ActivityHistory {
    // A fixed calendar so week boundaries are deterministic and locale-independent.
    // Internal (not private) so the progress heatmap lays its Monday-start week
    // columns out on exactly these boundaries instead of duplicating the rules.
    static var calendar: Calendar {
        var c = Calendar(identifier: .iso8601)   // Monday-start, ISO weeks
        c.locale = Locale(identifier: "en_US_POSIX")
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }

    // Shared with the heatmap so both drop unparseable dates the same way.
    static var parser: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }

    /// Group workouts into weeks, newest week first, each week newest-first
    /// inside it, with mileage / run-count / rest-day rollups. Workouts whose
    /// `date` isn't a valid ISO date are dropped (they can't be placed in a week).
    public static func groupByWeek(_ workouts: [LatestWorkout]) -> [WeekGroup] {
        let cal = calendar
        let fmt = parser

        // Bucket by the Monday that starts each workout's week.
        var buckets: [Date: [LatestWorkout]] = [:]
        for w in workouts {
            guard let d = fmt.date(from: w.date),
                  let weekStart = cal.dateInterval(of: .weekOfYear, for: d)?.start else { continue }
            buckets[weekStart, default: []].append(w)
        }

        let labeler = DateFormatter()
        labeler.dateFormat = "MMM d"
        labeler.locale = Locale(identifier: "en_US_POSIX")
        labeler.timeZone = TimeZone(identifier: "UTC")

        return buckets.keys.sorted(by: >).map { weekStart in
            let items = buckets[weekStart]!.sorted { ($0.date, $0.distanceMiles) > ($1.date, $1.distanceMiles) }
            let totalMiles = items.reduce(0) { $0 + $1.distanceMiles }
            let runCount = items.filter { $0.type == "run" }.count
            let activeDays = Set(items.map { $0.date }).count
            let restDays = max(0, 7 - activeDays)
            return WeekGroup(
                weekStartISO: fmt.string(from: weekStart),
                title: "Week of \(labeler.string(from: weekStart))",
                workouts: items,
                totalMiles: totalMiles,
                runCount: runCount,
                restDays: restDays
            )
        }
    }

    /// Derive the current-week training-load rollup (Milestone 4) from a flat,
    /// newest-first workout list — what the real HealthKit/Strava paths feed the
    /// Today dashboard's Weekly Load card. Pure + deterministic on the same
    /// Monday-start UTC ISO weeks as `groupByWeek`, so it's unit-testable:
    ///   • weeklyMileage / longestRun / daysRun / restDays come from the week
    ///     that contains `now`.
    ///   • loadTrend compares this week's mileage to a trailing MULTI-WEEK
    ///     baseline (acute vs. chronic), not just the single prior week, so a
    ///     steady ~10%/week build reads as "building" rather than tripping
    ///     "spiking" (the trustworthy-coaching fix). See `classifyTrend`.
    public static func weeklyLoad(from workouts: [LatestWorkout], asOf now: Date = Date()) -> WeeklyLoad {
        let cal = calendar
        let fmt = parser
        let weeks = groupByWeek(workouts)

        func weekStartISO(for date: Date) -> String? {
            guard let start = cal.dateInterval(of: .weekOfYear, for: date)?.start else { return nil }
            return fmt.string(from: start)
        }

        let thisISO = weekStartISO(for: now)
        let current = weeks.first { $0.weekStartISO == thisISO }

        let mileage = current?.totalMiles ?? 0
        let runs = current?.workouts.filter { $0.type == "run" } ?? []
        let longest = runs.map { $0.distanceMiles }.max() ?? 0
        let daysRun = Set(runs.map { $0.date }).count

        // The completed weeks strictly before the current one, newest-first — the
        // chronic baseline the current (acute) week is judged against.
        let priorWeeks = weeks.filter { w in
            guard let this = thisISO else { return false }
            return w.weekStartISO < this
        }

        let trend = classifyTrend(currentMileage: mileage, priorWeeks: priorWeeks, now: now, cal: cal)

        func round1(_ n: Double) -> Double { (n * 10).rounded() / 10 }
        return WeeklyLoad(
            weeklyMileage: round1(mileage),
            daysRunThisWeek: daysRun,
            longestRunMiles: round1(longest),
            restDaysThisWeek: current?.restDays ?? 7,
            loadTrend: trend
        )
    }

    /// Number of trailing weeks that must have logged activity before we trust a
    /// trend verdict. Below this we say "insufficient" rather than guess off one
    /// or two data points — "no coaching over bad coaching."
    private static let minBaselineWeeks = 2
    /// How many recent completed weeks form the chronic baseline.
    private static let baselineWindow = 4

    /// Classify the current week's load against a trailing multi-week baseline
    /// (acute:chronic). Pure + deterministic. Returns one of
    /// `spiking | building | recovering | steady | insufficient`:
    ///   • `insufficient` — fewer than `minBaselineWeeks` prior weeks of data, so
    ///     there's no honest baseline yet.
    ///   • `spiking` — this week is a genuine deviation ABOVE the baseline
    ///     (ratio ≥ 1.5), where a real one-week jump (not a sustained climb) lives.
    ///   • `building` — a modest, healthy rise above baseline (ratio ≥ 1.15), so a
    ///     ~10%/week progression reads as building, NOT spiking.
    ///   • `recovering` — a deliberate down week (ratio < 0.7), but only once the
    ///     week is mostly elapsed, so an unfinished partial week isn't mislabeled
    ///     "recovering" just for being early.
    ///   • `steady` — everything else.
    static func classifyTrend(currentMileage mileage: Double,
                              priorWeeks: [WeekGroup],
                              now: Date,
                              cal: Calendar) -> String {
        guard priorWeeks.count >= minBaselineWeeks else {
            // A truly blank slate (no history AND nothing logged this week) is just
            // "steady", preserving the day-one empty-state behavior; otherwise be
            // honest that there isn't enough history to judge the trend.
            return (mileage <= 0 && priorWeeks.isEmpty) ? "steady" : "insufficient"
        }

        let baseline = priorWeeks.prefix(baselineWindow)
        let chronic = baseline.map { $0.totalMiles }.reduce(0, +) / Double(baseline.count)
        guard chronic > 0 else { return mileage > 0 ? "building" : "steady" }

        let ratio = mileage / chronic

        // Mid-week guard: early in the current week the partial total always looks
        // low vs. completed weeks, so only call a down week "recovering" once most
        // of the week has actually elapsed.
        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start
        let daysElapsed = weekStart.map { now.timeIntervalSince($0) / 86_400.0 } ?? 7.0

        if ratio >= 1.5 { return "spiking" }
        if ratio >= 1.15 { return "building" }
        if ratio < 0.7 && daysElapsed >= 5.0 { return "recovering" }
        return "steady"
    }

    /// A compact, coach-facing weekly mileage series (most-recent weeks first),
    /// derived from the same `groupByWeek` rollups. Fed into the coach context so
    /// both the on-device and backend coaches can reason from the *shape* of the
    /// last several weeks instead of a single pre-chewed verdict. Capped to
    /// `maxWeeks` so it stays well under the backend context byte cap.
    public static func loadHistory(from workouts: [LatestWorkout], maxWeeks: Int = 8) -> [WeeklyLoadPoint] {
        func round1(_ n: Double) -> Double { (n * 10).rounded() / 10 }
        return groupByWeek(workouts).prefix(maxWeeks).map { g in
            let daysRun = Set(g.workouts.filter { $0.type == "run" }.map { $0.date }).count
            return WeeklyLoadPoint(weekStartISO: g.weekStartISO, miles: round1(g.totalMiles), daysRun: daysRun)
        }
    }
}
