import SwiftUI

// The week's training-load snapshot: mileage, run days, longest run, and rest
// days, with a trend badge.
struct WeeklyLoadCard: View {
    let load: WeeklyLoad

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("This week")
                    .font(Typography.captionStrong)
                    .foregroundColor(Palette.subtle)
                Spacer()
                TrendBadge(trend: load.loadTrend)
            }
            HStack(spacing: 0) {
                loadMetric(String(format: "%.1f", load.weeklyMileage), "miles")
                divider
                loadMetric("\(load.daysRunThisWeek)", "run days")
                divider
                loadMetric(String(format: "%.1f", load.longestRunMiles), "longest")
                divider
                loadMetric("\(load.restDaysThisWeek)", "rest days")
            }
        }
        .padding(16)
        .cardStyle()
    }

    private func loadMetric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(Typography.title3)
                .foregroundColor(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(Typography.caption)
                .foregroundColor(Palette.subtle)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }

    private var divider: some View {
        Rectangle().fill(Palette.ink.opacity(0.08)).frame(width: 1, height: 28)
    }
}
