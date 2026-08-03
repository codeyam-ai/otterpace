import SwiftUI

// One journal entry rendered in Activity History: the date, how it felt, the
// chips that were recorded, and the note. A post-run note carries the workout's
// icon so the timeline reads as "this is about that run" at a glance; a
// standalone check-in gets a quieter pencil.
struct JournalEntryRow: View {
    let entry: JournalEntry

    private var icon: String {
        guard entry.isPostRunNote else { return "square.and.pencil" }
        switch entry.workoutType {
        case "ride": return "bicycle"
        case "walk": return "figure.walk"
        default:     return "figure.run"
        }
    }

    private var tint: Color {
        entry.isPostRunNote ? Palette.go : Palette.sky
    }

    var body: some View {
        HStack(alignment: .top, spacing: Layout.md) {
            ZStack {
                Circle().fill(tint.opacity(0.16)).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(tint)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Layout.xs) {
                    Text(entry.isPostRunNote ? "Note on this \(entry.workoutType ?? "run")" : "Check-in")
                        .cardSectionLabel()
                    Spacer()
                    Text(prettyDate(entry.date))
                        .font(Typography.caption)
                        .foregroundColor(Palette.subtle)
                }
                if let feel = entry.feel {
                    Text("\(FeelSelector.word(for: feel)) · \(feel)/5")
                        .font(Typography.headline)
                        .foregroundColor(Palette.ink)
                }
                JournalChipSummary(entry: entry)
                if let note = entry.trimmedNote {
                    Text(note)
                        .font(Typography.callout)
                        .foregroundColor(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Layout.cardPadding)
        .cardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(entry.isPostRunNote ? "Note on this \(entry.workoutType ?? "run")" : "Check-in"), "
            + "\(prettyDate(entry.date)). \(JournalSpoken.describe(entry))"
        )
    }
}
