import SwiftUI

// A single labeled metric tile used in the dashboard's stats row.
struct StatTile: View {
    let icon: String
    let tint: Color
    let value: String
    let label: String
    /// Optional ⓘ explaining what the metric actually measures.
    var hint: HintTopic? = nil
    /// Optional line under the label, used to say "no data yet" out loud rather
    /// than leaving a bare `—` to read as a broken tile.
    var subtitle: String? = nil
    /// Spoken form for VoiceOver. Without it a no-data tile reads as
    /// "— active min", which is meaningless aloud.
    var accessibilityText: String? = nil

    // Seeded from the scenario so a capture can render an open hint on the first
    // frame — a simulator screenshot cannot tap the ⓘ itself.
    @State private var hintExpanded: Bool

    init(icon: String, tint: Color, value: String, label: String,
         hint: HintTopic? = nil, subtitle: String? = nil, accessibilityText: String? = nil) {
        self.icon = icon
        self.tint = tint
        self.value = value
        self.label = label
        self.hint = hint
        self.subtitle = subtitle
        self.accessibilityText = accessibilityText
        _hintExpanded = State(initialValue: hint.map { HintSeed.isOpen($0) } ?? false)
    }

    /// The metric itself: icon, value, label, and the optional "no data yet"
    /// line, collapsed into ONE VoiceOver element exactly as before. The ⓘ is
    /// deliberately kept outside this group so it stays separately focusable
    /// and its "Explain …" label is reachable.
    private var metric: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(Typography.headline)
                .foregroundColor(tint)
            Text(value)
                .font(Typography.title2)
                .foregroundColor(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(Typography.caption)
                .foregroundColor(Palette.subtle)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(Typography.caption)
                    .foregroundColor(Palette.subtle.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText ?? "\(value) \(label)")
    }

    var body: some View {
        VStack(spacing: 4) {
            metric
            if let hint {
                InfoHintButton(topic: hint, expanded: $hintExpanded)
                if hintExpanded {
                    InfoHintCaption(topic: hint)
                        .padding(.horizontal, Layout.xs)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .cardStyle()
    }
}
