import SwiftUI

// Circular progress ring toward the daily step goal, with the count and a
// "to go" / "goal hit" caption in the center.
struct StepRing: View {
    let progress: Double
    let steps: Int
    let goal: Int
    let remaining: Int
    let reached: Bool
    var exceeded: Bool = false

    // Ring diameter tracks the user's text size so the centered count never
    // overflows the circle at large Dynamic Type sizes.
    @ScaledMetric(relativeTo: .largeTitle) private var diameter: CGFloat = 150

    // Presentation logic lives in pure, unit-tested helpers (Formatters.swift).
    private var caption: String {
        stepGoalCaption(reached: reached, exceeded: exceeded, goal: goal)
    }

    private var accessibilityValue: String {
        stepGoalAccessibilityValue(steps: steps, goal: goal, remaining: remaining,
                                   reached: reached, exceeded: exceeded)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.brand.opacity(0.14), lineWidth: 14)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [Palette.brand, Palette.gold, Palette.go]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(formatted(steps))
                    .font(Typography.title2)
                    .foregroundColor(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(caption)
                    .font(Typography.caption)
                    .foregroundColor(Palette.subtle)
                    .multilineTextAlignment(.center)
                if !reached {
                    Text("\(formatted(remaining)) to go")
                        .font(Typography.caption)
                        .foregroundColor(Palette.brand)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily step goal")
        .accessibilityValue(accessibilityValue)
    }
}
