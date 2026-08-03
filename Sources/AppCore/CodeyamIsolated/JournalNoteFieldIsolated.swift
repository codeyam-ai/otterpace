import SwiftUI

// Isolation scaffold for JournalNoteField — the journal's optional free-text box.
//
// Empty is the state that matters most: it must read as an open invitation
// ("Anything else?") rather than an unfilled required field, because the whole
// design bet is that prose is optional. The filled state checks that real
// multi-line text sits comfortably in the card chrome.
struct JournalNoteFieldIsolated: View {
    let scenario: String

    private static let filled = "Legs were heavy the first mile, then it clicked. Held 10:15 without forcing it, and finished wanting one more."

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch scenario {
            case "Filled":
                JournalNoteField(text: .constant(JournalNoteFieldIsolated.filled), subject: "this workout")
            default:
                JournalNoteField(text: .constant(""), subject: "today")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.bgTop.ignoresSafeArea())
    }
}
