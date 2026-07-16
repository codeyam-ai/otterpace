import SwiftUI

// Shown in the Ask Coach tab when no AI key is connected. The Today insights and
// weekly review are always free; the conversational chat needs the user's own
// key, so this invites them to connect one in Settings rather than faking a reply.
struct AskCoachLockedState: View {
    var onAddKey: () -> Void = {}

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            BuddyView(mood: .ready, size: 96)
            Text("Chat with Buddy")
                .font(Typography.title2)
                .foregroundColor(Palette.ink)
            Text("Your Today insights and weekly review are always free. To chat with Buddy for conversational coaching, connect your own AI key.")
                .font(Typography.body)
                .foregroundColor(Palette.subtle)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Button(action: onAddKey) {
                Text("Connect your AI key")
                    .font(Typography.headline)
                    .foregroundColor(Palette.onAccent)
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .background(Capsule().fill(Palette.brand))
            }
            .padding(.top, 4)
            .accessibilityLabel("Connect your AI key in Settings")
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
