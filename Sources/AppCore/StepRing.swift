import SwiftUI

// Circular progress ring toward the daily step goal, with the count and a
// "to go" / "goal hit" caption in the center.
struct StepRing: View {
    let progress: Double
    let steps: Int
    let goal: Int
    let remaining: Int
    let reached: Bool

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
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(Palette.ink)
                Text(reached ? "goal hit! 🎉" : "of \(formatted(goal))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Palette.subtle)
                if !reached {
                    Text("\(formatted(remaining)) to go")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Palette.brand)
                }
            }
        }
        .frame(width: 150, height: 150)
    }
}
