import SwiftUI

// The AI coach recommendation card. Uses a calm brand/gold treatment normally,
// and an amber, shield-marked treatment when the recommendation carries a
// safety flag (injury-aware caution).
struct CoachCard: View {
    let coach: CoachRecommendation
    var onAskCoach: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: coach.safetyFlag ? "exclamationmark.shield.fill" : "sparkles")
                    .foregroundColor(coach.safetyFlag ? Palette.amber : Palette.brand)
                Text("Coach Buddy")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Palette.subtle)
                Spacer()
                Text(coach.recommendationType.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(coach.safetyFlag ? Palette.amber : Palette.go))
            }
            Text(coach.headline)
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundColor(Palette.ink)
            Text(coach.body)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(Palette.ink.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onAskCoach) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    Text("Ask Buddy")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundColor(Palette.brandDeep)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Capsule().fill(Palette.brand.opacity(0.14)))
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(
                    colors: [Palette.brand.opacity(0.10), Palette.gold.opacity(0.10)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Palette.brand.opacity(0.18), lineWidth: 1)
        )
    }
}
