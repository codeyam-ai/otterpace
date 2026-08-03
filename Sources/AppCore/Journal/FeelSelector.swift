import SwiftUI

// The 1–5 "how did it feel" row. One tap starts an entry, so this is the whole
// journal's front door — everything else in the editor is optional.
//
// Each option carries a full spoken label rather than a bare number: "3 out of
// 5, okay" tells a VoiceOver user what they're choosing, where "3" alone would
// not. The scale reads left-to-right rough → great, and is never framed as a
// score the runner passed or failed.
struct FeelSelector: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    var selection: Int?
    var onSelect: (Int) -> Void

    /// Short word under each number, so the scale means something without
    /// forcing the runner to infer what 3 stands for.
    static func word(for value: Int) -> String {
        switch value {
        case 1:  return "Rough"
        case 2:  return "Meh"
        case 3:  return "Okay"
        case 4:  return "Good"
        default: return "Great"
        }
    }

    /// Warm at the top of the scale, calm at the bottom — never red/alarming for
    /// a hard day. A rough day is information, not a failure.
    static func tint(for value: Int) -> Color {
        switch value {
        case 1:  return Palette.lilac
        case 2:  return Palette.sky
        case 3:  return Palette.subtle
        case 4:  return Palette.go
        default: return Palette.gold
        }
    }

    var body: some View {
        // Five options cannot share one row at accessibility text sizes without
        // clipping the last one off-screen — so the scale becomes a vertical
        // list there, keeping every option reachable and fully legible.
        if typeSize.isAccessibilitySize {
            VStack(spacing: Layout.xs) {
                ForEach(1...5, id: \.self) { option($0, stacked: true) }
            }
        } else {
            HStack(spacing: Layout.xs) {
                ForEach(1...5, id: \.self) { option($0, stacked: false) }
            }
        }
    }

    @ViewBuilder
    private func option(_ value: Int, stacked: Bool) -> some View {
        let isSelected = selection == value
        Button(action: { onSelect(value) }) {
            Group {
                if stacked {
                    HStack(spacing: Layout.sm) {
                        Text("\(value)")
                            .font(Typography.headline)
                            .foregroundColor(isSelected ? Palette.onAccent : Palette.ink)
                        Text(FeelSelector.word(for: value))
                            .font(Typography.callout)
                            .foregroundColor(isSelected ? Palette.onAccent : Palette.subtle)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Layout.md)
                } else {
                    VStack(spacing: 3) {
                        Text("\(value)")
                            .font(Typography.headline)
                            .foregroundColor(isSelected ? Palette.onAccent : Palette.ink)
                        Text(FeelSelector.word(for: value))
                            .font(Typography.caption)
                            .foregroundColor(isSelected ? Palette.onAccent : Palette.subtle)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Layout.sm)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected
                          ? FeelSelector.tint(for: value)
                          : FeelSelector.tint(for: value).opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) out of 5, \(FeelSelector.word(for: value))")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
