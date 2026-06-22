import SwiftUI

// A single chat bubble: user messages hug the trailing edge in a coral card;
// coach messages lead with a small Buddy and tint to the reply's mood, with an
// amber shield when the answer carries a safety flag.
struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(LinearGradient(colors: [Palette.brand, Palette.brandDeep],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
            }
        case .coach:
            HStack(alignment: .top, spacing: 8) {
                PuffyBuddy(mood: message.mood, size: 30)
                VStack(alignment: .leading, spacing: 6) {
                    if message.safetyFlag {
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.shield.fill")
                                .foregroundColor(Palette.amber)
                            Text("SAFETY FIRST")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundColor(Palette.amber)
                        }
                    }
                    Text(message.text)
                        .font(.system(size: 15))
                        .foregroundColor(Palette.ink.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(message.safetyFlag
                              ? Palette.amber.opacity(0.12)
                              : message.mood.accent.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke((message.safetyFlag ? Palette.amber : message.mood.accent).opacity(0.25), lineWidth: 1)
                )
                Spacer(minLength: 24)
            }
        }
    }
}
