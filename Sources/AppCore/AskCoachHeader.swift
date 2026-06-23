import SwiftUI

// The Ask Coach screen's title bar: a small Buddy avatar beside the screen name
// and a "mock coach" subtitle that's honest about the current coaching mode. A
// trailing "Weekly" pill opens the generated Weekly Review recap.
struct AskCoachHeader: View {
    var onWeeklyReview: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            PuffyBuddy(mood: .ready, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Ask Coach")
                    .font(Typography.title3)
                    .foregroundColor(Palette.ink)
                Text("Buddy • mock coach")
                    .font(Typography.caption)
                    .foregroundColor(Palette.subtle)
            }
            Spacer()
            Button(action: onWeeklyReview) {
                HStack(spacing: 5) {
                    Image(systemName: "calendar.badge.clock")
                        .font(Typography.caption)
                    Text("Weekly")
                        .font(Typography.captionStrong)
                }
                .foregroundColor(Palette.brandDeep)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(Palette.brand.opacity(0.14)))
            }
            .accessibilityLabel("Open weekly review")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
