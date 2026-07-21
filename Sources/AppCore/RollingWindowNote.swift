import SwiftUI

// The trailing-7-day line under the Weekly Load metrics. It exists because the
// Monday-start calendar week has a blind spot: a strong Saturday and Sunday
// vanish from "this week" at midnight Monday, so a runner can open the app on
// Tuesday and see almost nothing despite a heavy weekend. This line keeps that
// work visible without giving up the weekly reset the coaching copy is built on.
struct RollingWindowNote: View {
    let miles: Double
    let daysRun: Int

    var body: some View {
        Text(label)
            .font(Typography.caption)
            .foregroundColor(Palette.subtle)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(spokenLabel)
    }

    private var dayWord: String { daysRun == 1 ? "day" : "days" }

    private var label: String {
        "Last 7 days: \(String(format: "%.1f", miles)) mi · \(daysRun) run \(dayWord)"
    }

    private var spokenLabel: String {
        "Last 7 days, \(String(format: "%.1f", miles)) miles, \(daysRun) run \(dayWord)"
    }
}
