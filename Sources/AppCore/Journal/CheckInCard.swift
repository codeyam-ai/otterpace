import SwiftUI

// The journal's home on the Today dashboard. Two states, one card:
//
//   • Nothing logged yet — "How'd today feel?" with the 1–5 row live on the
//     card, so a check-in is one tap away and never requires opening a sheet.
//   • Already checked in — today's entry in a compact read state with an edit
//     affordance.
//
// Deliberately never a streak, never a scold: no "you haven't journaled in 4
// days," no completion ring, no unbroken chain. The prompt invites; it doesn't
// guilt. That's the same never-shame rule Buddy already follows, and a
// journaling feature is exactly where a wellness app usually breaks it.
struct CheckInCard: View {
    let entry: JournalEntry?
    var onQuickFeel: (Int) -> Void
    var onOpenEditor: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.sm) {
            if let entry = entry {
                loggedState(entry)
            } else {
                promptState
            }
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: Prompt — nothing written yet

    private var promptState: some View {
        VStack(alignment: .leading, spacing: Layout.sm) {
            HStack {
                Text("Check in").cardSectionLabel()
                Spacer()
            }
            Text("How'd today feel?")
                .font(Typography.headline)
                .foregroundColor(Palette.ink)
            FeelSelector(selection: nil, onSelect: onQuickFeel)
            Button(action: onOpenEditor) {
                Text("Add a note")
                    .font(Typography.captionStrong)
                    .foregroundColor(Palette.brand)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a note about today")
        }
    }

    // MARK: Logged — today's entry, compact

    private func loggedState(_ entry: JournalEntry) -> some View {
        Button(action: onOpenEditor) {
            VStack(alignment: .leading, spacing: Layout.xs) {
                HStack {
                    Text("Today's check-in").cardSectionLabel()
                    Spacer()
                    Text("Edit")
                        .font(Typography.captionStrong)
                        .foregroundColor(Palette.brand)
                }
                if let feel = entry.feel {
                    HStack(spacing: Layout.xs) {
                        Text(FeelSelector.word(for: feel))
                            .font(Typography.headline)
                            .foregroundColor(Palette.ink)
                        Text("\(feel)/5")
                            .font(Typography.caption)
                            .foregroundColor(Palette.subtle)
                    }
                }
                JournalChipSummary(entry: entry)
                if let note = entry.trimmedNote {
                    Text(note)
                        .font(Typography.callout)
                        .foregroundColor(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today's check-in. \(JournalSpoken.describe(entry)). Tap to edit.")
        .accessibilityAddTraits(.isButton)
    }
}

