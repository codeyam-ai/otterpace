import SwiftUI

// The compose bar pinned to the bottom of the Ask Coach screen: a text field
// bound to the parent's draft and a send button that activates only when the
// draft has non-whitespace content.
struct AskCoachInputBar: View {
    @Binding var draft: String
    var onSend: () -> Void

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 10) {
            TextField("Ask Buddy a question…", text: $draft)
                .font(Typography.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Palette.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Palette.ink.opacity(0.08), lineWidth: 1)
                )
                .onSubmit(onSend)
                .accessibilityLabel("Ask Buddy a question")

            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Palette.onAccent)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle().fill(canSend
                            ? AnyShapeStyle(LinearGradient(colors: [Palette.brand, Palette.brandDeep],
                                                           startPoint: .top, endPoint: .bottom))
                            : AnyShapeStyle(Palette.ink.opacity(0.18)))
                    )
            }
            .disabled(!canSend)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Palette.card.opacity(0.6).ignoresSafeArea(edges: .bottom))
    }
}
