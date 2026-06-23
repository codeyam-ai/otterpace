import SwiftUI

// The dashboard's top header: the "Today" title with the day, and the RunBuddy
// wordmark.
struct TodayHeader: View {
    let date: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .font(Typography.largeTitle)
                    .foregroundColor(Palette.ink)
                Text(prettyDate(date))
                    .font(Typography.caption)
                    .foregroundColor(Palette.subtle)
            }
            Spacer()
            Text("RunBuddy")
                .font(Typography.headline)
                .foregroundColor(Palette.brand)
        }
    }
}
