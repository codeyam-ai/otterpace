import SwiftUI

// The day-one empty state shown before Apple Health is connected: Buddy waving,
// a warm explainer, the connect call-to-action, and a privacy reassurance.
struct ConnectHero: View {
    let onConnect: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            PuffyBuddy(mood: .ready, size: 140)
            VStack(spacing: 8) {
                Text("Hi, I'm Buddy! 🐾")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(Palette.ink)
                Text("Connect Apple Health and I'll help you hit 10,000 steps a day and train without overdoing it.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(Palette.subtle)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Button(action: onConnect) {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                    Text("Connect Apple Health")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(colors: [Palette.brand, Palette.brandDeep],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(.horizontal, 24)
            Text("Your health data stays on your device.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Palette.subtle)
            Spacer()
        }
    }
}
