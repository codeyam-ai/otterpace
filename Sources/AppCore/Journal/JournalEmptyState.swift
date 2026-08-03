import SwiftUI

// The invitation shown where a journal history would be but nothing has been
// written yet. Buddy plus one low-stakes line.
//
// Deliberately no streak language, no "you haven't journaled in N days", no
// count of missed days — nothing that turns an empty journal into a failure.
// "A line about today is enough" sets the bar where it belongs: at one line.
struct JournalEmptyState: View {
    var body: some View {
        VStack(spacing: Layout.sm) {
            PuffyBuddy(mood: .ready, size: 72)
            Text("No notes yet")
                .font(Typography.headline)
                .foregroundColor(Palette.ink)
            Text("A line about today is enough.")
                .font(Typography.callout)
                .foregroundColor(Palette.subtle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Layout.lg)
        .padding(.horizontal, Layout.cardPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No journal notes yet. A line about today is enough.")
    }
}
