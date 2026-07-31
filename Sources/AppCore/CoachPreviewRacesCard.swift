import SwiftUI

/// Upcoming races shared with the coach so it can shape advice toward a goal.
///
/// Calls out the goal-time note explicitly: it is free text the user typed, and
/// free text is the field people are most surprised to learn was forwarded.
struct CoachPreviewRacesCard: View {
    let races: [RaceGoal]

    var body: some View {
        CardSection(title: "Goals and races") {
            if races.isEmpty {
                Text("Not shared — no upcoming races set.")
                    .font(Typography.callout).foregroundColor(Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(races) { race in
                        CoachDataRow(label: race.name,
                                     value: "\(prettyDate(race.date)) · \(race.location)")
                    }
                }
                Text("Any goal-time note you added is shared too, so Buddy can pace advice to it.")
                    .font(Typography.caption).foregroundColor(Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
