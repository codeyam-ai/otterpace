import SwiftUI

// The dashboard's top header: the "Today" title with the day, and the RunBuddy
// wordmark.
struct TodayHeader: View {
    let date: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(Palette.ink)
                Text(prettyDate(date))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Palette.subtle)
            }
            Spacer()
            Text("RunBuddy")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(Palette.brand)
        }
    }
}
