import SwiftUI

// Isolation scaffold for MovementFreshnessNote — codeyam renders this View standalone on the
// booted iOS simulator. CODEYAM_ISOLATE_COMPONENT=MovementFreshnessNote selects this struct in
// CodeyamIsolationHost.swift; CODEYAM_ISOLATE_SCENARIO picks the scenario below.
//
// This component has exactly two states and they carry opposite meanings, so both
// are worth seeing. The stale one is the whole point of the feature — it is the
// app admitting it cannot tell what you have been doing — and it is the state a
// user only ever meets when something has already gone quiet, which makes it the
// easiest one to regress without noticing.
//
// Rendered on the card fill it actually sits on in Settings, at full width, so
// the amber/green weighting reads the same here as in the real reminders card.
struct MovementFreshnessNoteIsolated: View {
    let scenario: String

    /// The Settings card surface this note lives inside — without it the note
    /// floats on the page gradient and the icon contrast reads differently than
    /// it ever does in the app.
    private func onCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Layout.cardPadding)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.card))
            .padding(Layout.screenGutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Full-bleed backdrop: a plain `.background` stays inside the safe
            // area, so the launch screen shows through the gaps and the capture
            // picks up a ghost splash behind the component.
            .background(Palette.bgTop.ignoresSafeArea())
    }

    var body: some View {
        switch scenario {
        case "Stale":
            // The suppression promise: Buddy has gone quiet on purpose, and says so.
            onCard { MovementFreshnessNote(isStale: true) }
        case "Both States":
            // Side by side, because the pair has to be tellable apart at a glance —
            // one is reassurance, the other is an explanation for silence.
            onCard {
                VStack(alignment: .leading, spacing: Layout.md) {
                    MovementFreshnessNote(isStale: false)
                    Divider().opacity(0.3)
                    MovementFreshnessNote(isStale: true)
                }
            }
        default:
            // Fresh — the everyday state, shown as the default so the component
            // reads as working rather than as warning.
            onCard { MovementFreshnessNote(isStale: false) }
        }
    }
}
