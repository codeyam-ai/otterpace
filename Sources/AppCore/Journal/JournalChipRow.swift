import SwiftUI

// A labeled row of tappable capsules — the shared control behind the editor's
// energy / soreness / sleep pickers. Follows the capsule idiom the step-goal
// presets in Settings already use, so the journal reads as part of the app
// rather than a new visual language.
//
// Tapping the selected chip clears it: every field here is optional, and a
// runner who mis-taps must be able to get back to "not saying" without
// abandoning the entry.
//
// At accessibility text sizes the capsules stack vertically instead of being
// squeezed onto one line — four chips at accessibility3 cannot share a row and
// stay legible, and shrinking them to fit would defeat the setting.
struct JournalChipRow<Option: Hashable>: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    let title: String
    let options: [Option]
    let label: (Option) -> String
    let tint: Color
    var selection: Option?
    var onSelect: (Option?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.xs) {
            Text(title).cardSectionLabel()
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Layout.xs) {
                    ForEach(options, id: \.self) { chip($0) }
                }
            } else {
                HStack(spacing: Layout.xs) {
                    ForEach(options, id: \.self) { chip($0) }
                }
            }
        }
    }

    @ViewBuilder
    private func chip(_ option: Option) -> some View {
        let isSelected = selection == option
        Button(action: { onSelect(isSelected ? nil : option) }) {
            Text(label(option))
                .font(Typography.captionStrong)
                .foregroundColor(isSelected ? Palette.onAccent : Palette.ink)
                // Keep chips to one line ONLY while they share a row. Stacked,
                // each chip owns its line, and pinning lineLimit(1) there gives
                // a long label like "a little sore" an intrinsic width far wider
                // than the screen — which widened the whole editor and pushed
                // its content (and the Save button) off the trailing edge.
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.75)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(isSelected ? tint : tint.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(label(option))")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
