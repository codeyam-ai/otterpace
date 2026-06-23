import SwiftUI

// Small pill under Buddy that names the current mood in its accent color.
struct MoodChip: View {
    let mood: BuddyMood

    var body: some View {
        Text(mood.caption)
            .font(Typography.captionStrong)
            .foregroundColor(mood.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(mood.accent.opacity(0.16)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Buddy mood: \(mood.caption)")
    }
}
