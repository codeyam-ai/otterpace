import SwiftUI

// MARK: - Progress heatmap section
//
// The activity calendar at the top of Activity History: a Monday-start grid of
// day cells whose color intensity reflects how active that day was, with a
// metric filter (distance / active minutes / steps vs. goal) and a range
// selector (week / month / 3-month).
//
// All binning lives in the pure `ActivityHeatmap`; this file only renders the
// result. Every color comes from `Palette`, which resolves through the currently
// selected theme, so the ramp retints across all five app looks rather than
// hardcoding coral.




// MARK: Section

/// The composed section mounted at the top of Activity History.
public struct ActivityHeatmapSection: View {
    // Re-render when the theme changes so the ramp retints live.
    @ObservedObject private var themeStore = ThemeStore.shared
    @ObservedObject var model: OtterpaceModel

    @State private var metric: HeatmapMetric
    @State private var range: HeatmapRange
    @State private var selectedDateISO: String?

    /// Defaults are Distance / Month. A scenario can pin the opening state via
    /// `rbHeatmapMetric` / `rbHeatmapRange` (same launch-seed pattern as the rest
    /// of the `rb*` keys) so each filter combination is capturable — this is a
    /// native stack, so there's no DOM to click a segment in at capture time.
    public init(model: OtterpaceModel, defaults: UserDefaults = .standard) {
        self.model = model
        let seededMetric = defaults.string(forKey: "rbHeatmapMetric")
            .flatMap { HeatmapMetric(rawValue: $0) } ?? .distance
        let seededRange = defaults.string(forKey: "rbHeatmapRange")
            .flatMap { HeatmapRange(rawValue: $0) } ?? .month
        _metric = State(initialValue: seededMetric)
        _range = State(initialValue: seededRange)
    }

    private var weeks: [[HeatmapDay]] {
        ActivityHeatmap.heatmap(
            workouts: model.today.workouts,
            dailySteps: model.today.dailySteps,
            goalSteps: model.today.goalSteps,
            metric: metric,
            range: range,
            todayISO: model.today.date
        )
    }

    /// The steps metric needs a per-day series HealthKit doesn't give us. Say so
    /// plainly rather than drawing a grid of zeroes that implies no movement.
    private var stepsSeriesMissing: Bool {
        metric == .stepsGoal && model.today.dailySteps.isEmpty
    }

    private var selectedSummary: HeatmapDaySummary? {
        selectedDateISO.flatMap {
            ActivityHeatmap.daySummary(dateISO: $0, workouts: model.today.workouts)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Layout.md) {
            Text("Progress")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(Palette.ink)

            HeatmapMetricPicker(metric: $metric)

            if stepsSeriesMissing {
                HeatmapNote(text: "No step data yet — daily steps show up here once they sync.")
            } else if ActivityHeatmap.isEmpty(weeks) {
                HeatmapEmptyState()
            } else {
                HeatmapGrid(weeks: weeks, metric: metric, selectedDateISO: $selectedDateISO)
                if let summary = selectedSummary {
                    HeatmapDayDetail(summary: summary,
                                     steps: model.today.dailySteps[summary.dateISO])
                }
                HStack {
                    HeatmapRangePicker(range: $range)
                    Spacer()
                    HeatmapLegend()
                }
            }
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}
