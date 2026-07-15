import SwiftUI

// The Weekly Review screen's title bar: a small Buddy avatar beside the screen
// name and a "generated recap" subtitle, with a trailing Done button that
// dismisses the recap back to the Coach chat.
struct WeeklyReviewHeader: View {
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            BuddyView(mood: .ready, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Weekly Review")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(Palette.ink)
                Text("Buddy • generated recap")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Palette.subtle)
            }
            Spacer()
            Button(action: onClose) {
                Text("Done")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(Palette.brandDeep)
            }
            .accessibilityLabel("Close weekly review")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
