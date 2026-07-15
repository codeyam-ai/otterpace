import SwiftUI

// MARK: - Weekly Review screen
//
// A read-only weekly recap the coach generates from the same `WeeklyLoad`
// context the Today dashboard and Ask Coach already use. It presents five
// sections — what went well, what changed, training risk, suggested next week —
// and ends on a single highlighted "one focus area" callout, fronted by Buddy at
// the review's mood. Encouraging and never shame-based, with the training-risk
// section taking the amber, shield-marked safety treatment when the week's load
// warrants caution.
//
// The view is pure composition over a `WeeklyReview` value built by
// `WeeklyReviewEngine`: header, hero, the section cards, and the focus callout
// each live in their own component file. This view only arranges them and
// branches between the activity recap and the empty first-week prompt.

public struct WeeklyReviewView: View {
    // Re-render this screen when the theme changes so Palette retints live.
    @ObservedObject private var themeStore = ThemeStore.shared
    let review: WeeklyReview
    var onClose: () -> Void

    public init(review: WeeklyReview, onClose: @escaping () -> Void = {}) {
        self.review = review
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.bgTop, Palette.bgBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                WeeklyReviewHeader(onClose: onClose)
                Divider().opacity(0.4)
                ScrollView {
                    VStack(spacing: Layout.cardSpacing) {
                        WeeklyReviewHero(mood: review.buddyMood, headline: review.headline)
                        if review.hasActivity {
                            WeeklyReviewSection(icon: "checkmark.seal.fill", tint: Palette.go,
                                                title: "What went well", body: review.wentWell)
                            WeeklyReviewSection(icon: "arrow.triangle.swap", tint: Palette.sky,
                                                title: "What changed", body: review.whatChanged)
                            WeeklyReviewRiskSection(body: review.trainingRisk, safetyFlag: review.safetyFlag)
                            WeeklyReviewSection(icon: "calendar", tint: Palette.brand,
                                                title: "Suggested next week", body: review.nextWeek)
                        } else {
                            WeeklyReviewSection(icon: "figure.walk", tint: Palette.go,
                                                title: "Where to begin", body: review.wentWell)
                            WeeklyReviewSection(icon: "calendar", tint: Palette.brand,
                                                title: "This week", body: review.nextWeek)
                        }
                        WeeklyReviewFocusCallout(focus: review.focusArea)
                    }
                    .screenScrollContent()
                }
            }
        }
    }
}
