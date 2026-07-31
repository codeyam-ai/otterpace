import SwiftUI

/// The weekly mileage series the coach uses to judge training trend.
///
/// `daysRun` counts runs only while `miles` includes walks, so a walk-only week
/// legitimately reads "1.8 mi · 0 runs". That pairing is what the coach actually
/// receives, so it is shown as-is rather than smoothed into something tidier.
struct CoachPreviewLoadCard: View {
    let loadHistory: [WeeklyLoadPoint]

    var body: some View {
        CardSection(title: "Weekly training load") {
            if loadHistory.isEmpty {
                Text("Not shared — not enough history yet.")
                    .font(Typography.callout).foregroundColor(Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(loadHistory.enumerated()), id: \.offset) { _, point in
                        CoachDataRow(
                            label: "Week of \(prettyDate(point.weekStartISO))",
                            value: "\(miles(point.miles)) mi · \(point.daysRun) \(point.daysRun == 1 ? "run" : "runs")"
                        )
                    }
                }
            }
        }
    }
}
