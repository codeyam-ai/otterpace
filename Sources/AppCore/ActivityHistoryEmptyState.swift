import SwiftUI

// The day-one empty state for Activity History: friendly Buddy prompt shown when
// no workouts have been logged yet, encouraging a first easy session.
struct ActivityHistoryEmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            BuddyView(mood: .ready, size: 96)
            Text("No workouts yet")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(Palette.ink)
            Text("Once you log a run or walk, your weekly mileage and training load will show up here. An easy first session is all it takes to get started.")
                .font(.system(size: 15))
                .foregroundColor(Palette.ink.opacity(0.82))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .accessibilityElement(children: .combine)
    }
}
