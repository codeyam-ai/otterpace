import SwiftUI

/// The chips an entry recorded, rendered inline as a compact read-only strip.
/// Shared by the Today check-in card and the history row so a logged entry
/// looks the same wherever it appears. Renders nothing at all when the runner
/// recorded no chips — an entry that is just a feel rating and a note should
/// not leave a blank band behind.
struct JournalChipSummary: View {
    let entry: JournalEntry

    var body: some View {
        let parts = JournalSpoken.chips(entry)
        if !parts.isEmpty {
            HStack(spacing: Layout.xs) {
                ForEach(parts, id: \.text) { part in
                    Text(part.text)
                        .font(Typography.caption)
                        .foregroundColor(part.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(part.tint.opacity(0.14)))
                }
            }
        }
    }
}
