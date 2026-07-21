import SwiftUI

// What a tapped heatmap day shows: the date, that day's workouts, and its step
// total. Rest days say so warmly rather than reading as an error — rest is a
// legitimate part of a training week in this app, not a gap in the data.
struct HeatmapDayDetail: View {
    let summary: HeatmapDaySummary
    /// Steps for this day, when a series is seeded — so a rest day still reports
    /// the walking that happened around it.
    let steps: Int?

    private var stepsLine: String? {
        steps.map { "\($0.formatted()) steps" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary.title)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(Palette.ink)

            if summary.isRestDay {
                Text(stepsLine ?? "Rest day")
                    .font(.system(size: 12))
                    .foregroundColor(Palette.subtle)
            } else {
                ForEach(Array(summary.workouts.enumerated()), id: \.offset) { _, w in
                    Text("\(w.type.capitalized) · \(miles(w.distanceMiles)) mi · \(w.durationMinutes) min")
                        .font(.system(size: 12))
                        .foregroundColor(Palette.subtle)
                }
                if let stepsLine {
                    Text(stepsLine)
                        .font(.system(size: 12))
                        .foregroundColor(Palette.subtle)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Layout.sm)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.ink.opacity(0.05))
        )
        .accessibilityElement(children: .combine)
    }
}
