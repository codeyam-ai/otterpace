import SwiftUI

// Isolation scaffold for JournalEditorHeader — the editor's Cancel / date / Save bar.
//
// The pair below is the component's real contract: Save is DISABLED on a blank
// draft (nothing recorded means nothing to save) but stays visible so the bar
// never shifts under the thumb, and it becomes actionable the moment the runner
// records anything. Showing both states side by side is the only way to see that
// the difference reads as intentional rather than as a broken button.
struct JournalEditorHeaderIsolated: View {
    let scenario: String

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            switch scenario {
            case "Save Enabled":
                JournalEditorHeader(date: "2026-06-22", canSave: true, onCancel: {}, onSave: {})
            case "Both States":
                JournalEditorHeader(date: "2026-06-22", canSave: false, onCancel: {}, onSave: {})
                Divider()
                JournalEditorHeader(date: "2026-06-22", canSave: true, onCancel: {}, onSave: {})
            default:
                JournalEditorHeader(date: "2026-06-22", canSave: false, onCancel: {}, onSave: {})
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.bgTop.ignoresSafeArea())
    }
}
