import SwiftUI

/// The journal editor's top bar: Cancel, the entry's date, and Save.
///
/// Two accessibility accommodations live here rather than in the editor body:
/// at accessibility text sizes the date drops to its own line (three items
/// cannot share the row), and the bar caps its own type growth. Cancel and Save
/// are a fixed pair that must BOTH stay on screen — uncapped, their intrinsic
/// width exceeds the display and clips Save off the trailing edge. The editor's
/// content below still scales all the way up; only this chrome is bounded.
struct JournalEditorHeader: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    let date: String
    /// Nothing recorded means nothing to save. The button stays visible but
    /// disabled rather than vanishing, so the bar doesn't shift under the thumb.
    let canSave: Bool
    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.xs) {
            HStack {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(Typography.headline)
                        .foregroundColor(Palette.subtle)
                }
                .buttonStyle(.plain)
                if !typeSize.isAccessibilitySize {
                    Spacer()
                    dateLabel
                }
                Spacer()
                Button(action: onSave) {
                    Text("Save")
                        .font(Typography.headline)
                        .foregroundColor(canSave ? Palette.brand : Palette.subtle)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
            if typeSize.isAccessibilitySize { dateLabel }
        }
        .padding(.horizontal, Layout.screenGutter)
        .padding(.vertical, Layout.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private var dateLabel: some View {
        Text(prettyDate(date))
            .font(Typography.captionStrong)
            .foregroundColor(Palette.subtle)
    }
}
