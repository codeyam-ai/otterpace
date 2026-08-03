import SwiftUI

// MARK: - Tap-to-reveal hint
//
// A small ⓘ button that toggles an inline explanatory caption beneath its host.
//
// Deliberately NOT a `.popover` or `.help()`: the macOS test build targets macOS
// 12 where `.help()` is macOS-only and popovers need anchor math, while an inline
// disclosure compiles everywhere, captures deterministically in a scenario, and
// reflows correctly at accessibility text sizes.

/// The ⓘ affordance itself. Pair it with `hintCaption(_:expanded:)` on the host,
/// or use the `hinted(_:)` modifier when the host has no room for its own row.
struct InfoHintButton: View {
    let topic: HintTopic
    @Binding var expanded: Bool

    var body: some View {
        Button {
            withAnimation(Motion.overlay) { expanded.toggle() }
        } label: {
            Image(systemName: expanded ? "info.circle.fill" : "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Palette.subtle)
                // A 13pt glyph is far below a comfortable tap target, so pad the
                // hit area out without pushing the glyph around in the layout.
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Explain \(topic.title)")
        .accessibilityHint(expanded ? "Hides the explanation" : "Shows a short explanation")
    }
}

/// The revealed caption. Rendered in the host's own layout so it never overlaps
/// neighboring cards and never needs an anchor.
struct InfoHintCaption: View {
    let topic: HintTopic

    var body: some View {
        Text(topic.body)
            .font(Typography.caption)
            .foregroundColor(Palette.subtle)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Layout.sm)
            .padding(.vertical, Layout.xs)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.subtle.opacity(0.10))
            )
            .accessibilityLabel("\(topic.title): \(topic.body)")
    }
}

/// Self-contained ⓘ + caption pair for hosts that can spare a row: the button sits
/// inline, and tapping it reveals the caption directly beneath.
struct InfoHint: View {
    let topic: HintTopic
    /// Optional lead-in text shown to the left of the ⓘ (e.g. a card caption).
    var label: String? = nil

    // Seeded in `init` (not `.onAppear`) so a launch-seeded capture renders the
    // revealed caption on the very first frame.
    @State private var expanded: Bool

    init(topic: HintTopic, label: String? = nil) {
        self.topic = topic
        self.label = label
        _expanded = State(initialValue: HintSeed.isOpen(topic))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.xs) {
            HStack(spacing: 2) {
                if let label {
                    Text(label)
                        .font(Typography.caption)
                        .foregroundColor(Palette.subtle)
                }
                InfoHintButton(topic: topic, expanded: $expanded)
                Spacer(minLength: 0)
            }
            if expanded {
                InfoHintCaption(topic: topic)
            }
        }
    }
}

extension View {
    /// Attach a hint beneath any view without restructuring its layout.
    func hinted(_ topic: HintTopic, label: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: Layout.xs) {
            self
            InfoHint(topic: topic, label: label)
        }
    }
}
