import SwiftUI

// The Activity History screen's title bar: a small Buddy avatar beside the
// screen name and an "all activity" subtitle, with a trailing Done button that
// dismisses back to the dashboard.
struct ActivityHistoryHeader: View {
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            BuddyView(mood: .ready, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Activity History")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(Palette.ink)
                Text("Recent workouts & weekly load")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Palette.subtle)
            }
            Spacer()
            Button(action: onClose) {
                Text("Done")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(Palette.brandDeep)
            }
            .accessibilityLabel("Close activity history")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
