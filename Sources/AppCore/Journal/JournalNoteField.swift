import SwiftUI

/// The journal's free-text field: a labeled `TextEditor` in the app's card
/// chrome. Optional and always available, never required — the chips above it
/// carry the structured signal, and a journal that demands prose gets abandoned
/// in a week. So the label asks rather than instructs.
struct JournalNoteField: View {
    @Binding var text: String
    /// Names what the note is about, so the spoken label is "Note about this
    /// run" rather than a bare "Note".
    let subject: String

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.xs) {
            Text("Anything else?").cardSectionLabel()
            TextEditor(text: $text)
                .font(Typography.body)
                .foregroundColor(Palette.ink)
                .frame(minHeight: 110)
                .scrollContentBackgroundHidden()
                .padding(Layout.sm)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Palette.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Palette.ink.opacity(0.08), lineWidth: 1)
                )
                .accessibilityLabel("Note about \(subject)")
        }
    }
}

extension View {
    /// `scrollContentBackground` is iOS 16+/macOS 13+; without it a `TextEditor`
    /// paints its own opaque background over the themed card fill. Applied
    /// conditionally so the editor still builds against the package's macOS 12
    /// floor.
    @ViewBuilder
    func scrollContentBackgroundHidden() -> some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}
