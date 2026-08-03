import SwiftUI

// The ice-breaker chip row shared by the Ask Coach empty and locked states.
//
// When `onPick` is nil the chips render as non-tappable examples. That is how the
// locked state uses them: an unconnected user still learns the shape of a good
// question, without the app implying it will answer one.
struct StarterQuestionChips: View {
    let questions: [StarterQuestion]
    var onPick: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.sm) {
            ForEach(questions) { q in
                if let onPick {
                    Button { onPick(q.text) } label: { chip(q.text, tappable: true) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Ask: \(q.text)")
                        .accessibilityHint("Sends this question to Buddy")
                } else {
                    chip(q.text, tappable: false)
                        .accessibilityLabel("Example question: \(q.text)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ text: String, tappable: Bool) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(Typography.callout)
                .foregroundColor(tappable ? Palette.ink : Palette.subtle)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if tappable {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Palette.brand)
            }
        }
        .padding(.horizontal, Layout.md)
        .padding(.vertical, Layout.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tappable ? Palette.brand.opacity(0.10) : Palette.subtle.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke((tappable ? Palette.brand : Palette.subtle).opacity(0.22), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}
