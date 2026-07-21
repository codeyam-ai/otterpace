import Foundation

// MARK: - Progress heatmap binning
//
// Pure, deterministic logic behind the Activity History progress heatmap: take
// the same workout list the weekly rollups use (plus an optional per-day steps
// series) and lay it out as Monday-start week columns of day cells, each binned
// to an intensity level 0–4. No SwiftUI, no I/O, so the view stays a thin
// renderer and every rule here is unit-testable.
//
// Week boundaries and date parsing come from `ActivityHistory` rather than being
// re-derived, so a day lands in the same week the list below it does.

/// Which activity measure the grid colors by.
public enum HeatmapMetric: String, CaseIterable, Equatable {
    case distance, activeMinutes, stepsGoal

    public var label: String {
        switch self {
        case .distance:     return "Distance"
        case .activeMinutes: return "Active min"
        case .stepsGoal:    return "Steps vs goal"
        }
    }
}

/// How much history the grid shows. Range changes the visible span only — cells
/// stay one-day granular at every range.
public enum HeatmapRange: String, CaseIterable, Equatable {
    case week, month, threeMonth

    public var label: String {
        switch self {
        case .week:       return "Week"
        case .month:      return "Month"
        case .threeMonth: return "3-Month"
        }
    }

    /// Number of Monday-start week columns rendered.
    public var weekCount: Int {
        switch self {
        case .week:       return 1
        case .month:      return 4
        case .threeMonth: return 13
        }
    }
}

/// One day cell: its ISO date, the raw metric value, and the 0–4 intensity.
public struct HeatmapDay: Equatable, Identifiable {
    public var id: String { dateISO }
    public var dateISO: String
    public var value: Double
    public var level: Int          // 0 = no activity, 4 = hottest in view

    public init(dateISO: String, value: Double, level: Int) {
        self.dateISO = dateISO
        self.value = value
        self.level = level
    }
}

public enum ActivityHeatmap {
    /// Highest intensity level; levels run 0...maxLevel.
    public static let maxLevel = 4

    /// Build Monday-start week columns of day cells over the selected range.
    ///
    /// Each returned inner array is one week, oldest week first, and always holds
    /// exactly 7 days (Monday…Sunday) so the grid is rectangular and the view can
    /// render it without bounds checks. Days with no activity are level 0 rather
    /// than being omitted — a rest day is meaningful in a heatmap.
    ///
    /// Binning: distance and active-minutes are relative to the busiest day in the
    /// visible window (so the grid always has contrast, whatever the athlete's
    /// scale), while steps-vs-goal bins against `goalSteps` (an absolute, meaningful
    /// target). Workouts whose `date` isn't a valid ISO date are dropped, matching
    /// `ActivityHistory.groupByWeek`.
    public static func heatmap(workouts: [LatestWorkout],
                               dailySteps: [String: Int] = [:],
                               goalSteps: Int = 10_000,
                               metric: HeatmapMetric = .distance,
                               range: HeatmapRange = .month,
                               todayISO: String) -> [[HeatmapDay]] {
        let cal = ActivityHistory.calendar
        let fmt = ActivityHistory.parser

        // Anchor on today's week; an unparseable anchor yields no grid at all
        // rather than a grid silently anchored on "now" (which would make a
        // seeded scenario capture differently over time).
        guard let today = fmt.date(from: todayISO),
              let thisWeekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start
        else { return [] }

        // Oldest visible Monday: step back (weekCount - 1) whole weeks.
        guard let firstWeekStart = cal.date(byAdding: .weekOfYear,
                                            value: -(range.weekCount - 1),
                                            to: thisWeekStart)
        else { return [] }

        // Sum each day's contribution once, keyed by ISO date.
        var perDay: [String: Double] = [:]
        for w in workouts {
            guard fmt.date(from: w.date) != nil else { continue }   // drop unparseable
            let contribution: Double
            switch metric {
            case .distance:      contribution = w.distanceMiles
            case .activeMinutes: contribution = Double(w.durationMinutes)
            case .stepsGoal:     contribution = 0                    // steps come from dailySteps
            }
            perDay[w.date, default: 0] += contribution
        }
        if metric == .stepsGoal {
            perDay = [:]
            for (dateISO, steps) in dailySteps where fmt.date(from: dateISO) != nil {
                perDay[dateISO] = Double(steps)
            }
        }

        // Lay out the rectangle first so we know the visible window before binning.
        var weeks: [[(iso: String, value: Double)]] = []
        for w in 0..<range.weekCount {
            guard let weekStart = cal.date(byAdding: .weekOfYear, value: w, to: firstWeekStart)
            else { continue }
            var days: [(iso: String, value: Double)] = []
            for d in 0..<7 {
                guard let day = cal.date(byAdding: .day, value: d, to: weekStart) else { continue }
                let iso = fmt.string(from: day)
                days.append((iso: iso, value: perDay[iso] ?? 0))
            }
            if days.count == 7 { weeks.append(days) }
        }

        // Relative metrics scale to the busiest visible day; steps use the goal.
        let windowMax = weeks.flatMap { $0 }.map(\.value).max() ?? 0
        let scale: Double = (metric == .stepsGoal) ? Double(max(goalSteps, 1)) : windowMax

        return weeks.map { week in
            week.map { day in
                HeatmapDay(dateISO: day.iso,
                           value: day.value,
                           level: level(for: day.value, scale: scale))
            }
        }
    }

    /// Bin a day's value into 0...maxLevel against `scale` (the window max, or the
    /// step goal). Any activity at all is at least level 1, so a short walk never
    /// renders as an empty day; hitting or beating `scale` is the top level.
    static func level(for value: Double, scale: Double) -> Int {
        guard value > 0 else { return 0 }
        guard scale > 0 else { return 1 }
        let fraction = value / scale
        if fraction >= 1.0 { return maxLevel }
        return min(maxLevel, max(1, Int(ceil(fraction * Double(maxLevel)))))
    }

    /// Whether the grid has anything worth showing. Drives the friendly empty
    /// state instead of rendering a full month of level-0 cells on day one.
    public static func isEmpty(_ weeks: [[HeatmapDay]]) -> Bool {
        !weeks.contains { $0.contains { $0.level > 0 } }
    }

    /// Short month label for a week row, or nil when the row continues the month
    /// above it. Lets the grid mark where each month begins so a long span is
    /// readable instead of an undifferentiated block of squares.
    ///
    /// A row is labeled when it is the first row, or when its Monday falls in a
    /// different month than the previous row's Monday.
    public static func monthLabels(for weeks: [[HeatmapDay]]) -> [String?] {
        let fmt = ActivityHistory.parser
        let namer = DateFormatter()
        namer.dateFormat = "MMM"
        namer.locale = Locale(identifier: "en_US_POSIX")
        namer.timeZone = TimeZone(identifier: "UTC")

        var previousMonth: Int? = nil
        let cal = ActivityHistory.calendar
        return weeks.map { week in
            guard let firstISO = week.first?.dateISO,
                  let date = fmt.date(from: firstISO) else { return nil }
            let month = cal.component(.month, from: date)
            defer { previousMonth = month }
            return month == previousMonth ? nil : namer.string(from: date)
        }
    }

    /// Everything shown when a day cell is tapped: a human date plus that day's
    /// workouts. Returns nil for a date outside the series so the view can just
    /// clear the selection.
    public static func daySummary(dateISO: String, workouts: [LatestWorkout]) -> HeatmapDaySummary? {
        let fmt = ActivityHistory.parser
        guard let date = fmt.date(from: dateISO) else { return nil }

        let labeler = DateFormatter()
        labeler.dateFormat = "EEE, MMM d"
        labeler.locale = Locale(identifier: "en_US_POSIX")
        labeler.timeZone = TimeZone(identifier: "UTC")

        let onDay = workouts.filter { $0.date == dateISO }
        return HeatmapDaySummary(
            dateISO: dateISO,
            title: labeler.string(from: date),
            workouts: onDay,
            totalMiles: onDay.reduce(0) { $0 + $1.distanceMiles },
            totalMinutes: onDay.reduce(0) { $0 + $1.durationMinutes }
        )
    }
}

/// What a tapped day shows: the date plus that day's activity rollup.
public struct HeatmapDaySummary: Equatable {
    public var dateISO: String
    public var title: String            // e.g. "Tue, Jun 16"
    public var workouts: [LatestWorkout]
    public var totalMiles: Double
    public var totalMinutes: Int

    public var isRestDay: Bool { workouts.isEmpty }

    public init(dateISO: String, title: String, workouts: [LatestWorkout],
                totalMiles: Double, totalMinutes: Int) {
        self.dateISO = dateISO
        self.title = title
        self.workouts = workouts
        self.totalMiles = totalMiles
        self.totalMinutes = totalMinutes
    }
}
