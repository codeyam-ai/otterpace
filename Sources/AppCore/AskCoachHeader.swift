import SwiftUI

// The Ask Coach screen's title bar: a small Buddy avatar beside the screen name
// and a "mock coach" subtitle that's honest about the current coaching mode.
struct AskCoachHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            PuffyBuddy(mood: .ready, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Ask Coach")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(Palette.ink)
                Text("Buddy • mock coach")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Palette.subtle)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
