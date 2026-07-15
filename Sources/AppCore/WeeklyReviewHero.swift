import SwiftUI

// The recap's hero: Buddy at the review's mood, a mood chip, and the headline
// that sets the week's tone (celebratory, cautionary, gentle, or inviting).
struct WeeklyReviewHero: View {
    let mood: BuddyMood
    let headline: String

    var body: some View {
        VStack(spacing: 10) {
            BuddyView(mood: mood, size: 96)
            MoodChip(mood: mood)
            Text(headline)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(Palette.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
