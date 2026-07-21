import SwiftUI

// MARK: - Heatmap day grid

/// The day-cell grid: weekdays run across (Mon…Sun) and each week is a row,
/// oldest week at the top. On a phone this reads as a calendar and uses the full
/// card width — a contributions-style layout with weeks as columns would leave
/// most of the card empty at the 1- and 4-week ranges.
struct HeatmapGrid: View {
    let weeks: [[HeatmapDay]]
    let metric: HeatmapMetric
    /// Currently selected day, if any — tapping a cell drives the detail row.
    @Binding var selectedDateISO: String?

    private let weekdayLabels = ["M", "T", "W", "T", "F", "S", "S"]
    /// Left gutter carrying the month markers.
    private let railWidth: CGFloat = 30

    /// Cells are SQUARE at every range — a heatmap day that renders as a wide
    /// pill stops reading as a calendar square. The 3-month span therefore
    /// shrinks the square (and centers the grid) rather than flattening it to
    /// fit thirteen rows into the card.
    /// 21pt squares across 13 columns plus the weekday rail fill the card almost
    /// exactly at the 3-month span; the short spans get generous 40pt squares.
    private var cellSize: CGFloat { weeks.count > 4 ? 21 : 40 }
    private var spacing: CGFloat { weeks.count > 4 ? 3 : 6 }
    private var corner: CGFloat { weeks.count > 4 ? 5 : 6 }

    private var monthLabels: [String?] { ActivityHeatmap.monthLabels(for: weeks) }

    /// Orientation switches with the span, because one shape can't serve both.
    /// Short spans (1–4 weeks) read best as a CALENDAR — weeks as rows, weekdays
    /// across — which fills the card width. A 13-week span in that shape would be
    /// thirteen rows tall and only half as wide as the card, so the long span
    /// flips to the CONTRIBUTION shape — weeks as columns, seven rows tall —
    /// which uses the full width and scrolls horizontally if it overflows.
    private var usesContributionLayout: Bool { weeks.count > 4 }

    var body: some View {
        if usesContributionLayout { contributionLayout } else { calendarLayout }
    }

    // Weeks as columns, weekdays as rows; months labeled across the top.
    private var contributionLayout: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: spacing) {
                // Weekday rail
                VStack(spacing: spacing) {
                    Text("").font(.system(size: 10)).frame(height: 12)   // month-row gutter
                    ForEach(0..<7, id: \.self) { row in
                        Text(["M", "", "W", "", "F", "", ""][row])
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(Palette.subtle)
                            .frame(width: 14, height: cellSize, alignment: .leading)
                    }
                }

                ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                    VStack(spacing: spacing) {
                        Text(monthLabels[index] ?? "")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundColor(Palette.ink.opacity(0.75))
                            .fixedSize()
                            .frame(width: cellSize, height: 12, alignment: .leading)
                        ForEach(week) { day in
                            cell(for: day)
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private func cell(for day: HeatmapDay) -> some View {
        let isSelected = day.dateISO == selectedDateISO
        Button {
            selectedDateISO = isSelected ? nil : day.dateISO
        } label: {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(HeatmapRamp.fill(level: day.level))
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(isSelected ? Palette.ink : HeatmapRamp.stroke(level: day.level),
                                lineWidth: isSelected ? 2 : 1)
                )
                .frame(width: cellSize, height: cellSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.spokenLabel(for: day, metric: metric))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var calendarLayout: some View {
        VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                Color.clear.frame(width: railWidth, height: 1)   // align with month rail
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Palette.subtle)
                        .frame(width: cellSize)
                }
            }
            .accessibilityHidden(true)

            ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                HStack(spacing: spacing) {
                    // Month marker: only on the row where a new month starts, so
                    // a 13-week span reads as "Apr / May / Jun" at a glance.
                    Text(monthLabels[index] ?? "")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(Palette.ink.opacity(0.75))
                        .frame(width: railWidth, alignment: .leading)

                    ForEach(week) { day in
                        cell(for: day)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)   // center the grid within the card
    }

    /// VoiceOver reads a cell as its date plus what was actually done, so the
    /// grid is navigable without seeing the color at all.
    static func spokenLabel(for day: HeatmapDay, metric: HeatmapMetric) -> String {
        guard day.level > 0 else { return "\(day.dateISO), no activity" }
        switch metric {
        case .distance:      return "\(day.dateISO), \(Self.trim(day.value)) miles"
        case .activeMinutes: return "\(day.dateISO), \(Int(day.value)) active minutes"
        case .stepsGoal:     return "\(day.dateISO), \(Int(day.value)) steps"
        }
    }

    private static func trim(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}
