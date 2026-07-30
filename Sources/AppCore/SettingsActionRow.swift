import SwiftUI

// The two row affordances every Settings card is built from: a tappable action
// row (chevron) and its label, which a `Link` reuses so an external destination
// renders the same way with an arrow instead of a chevron.
//
// These began as private helpers inside `SettingsView`. They live here so cards
// extracted OUT of that file — `CoachProviderRow`, `CoachKeyField` — can render
// the same affordance instead of reimplementing it and drifting visually.
// `SettingsView` keeps thin private wrappers, so its other cards are untouched.

/// The visual content of an action row. Split from the button so a `Link` can
/// reuse it: `external` swaps the trailing chevron for an out-arrow.
struct SettingsActionRowLabel: View {
    let title: String
    let icon: String
    let tint: Color
    var destructive: Bool = false
    var external: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(tint).frame(width: 24)
            Text(title).font(Typography.headline).foregroundColor(destructive ? Palette.brandDeep : Palette.ink)
            Spacer()
            Image(systemName: external ? "arrow.up.right" : "chevron.right")
                .font(.system(size: 13, weight: .bold)).foregroundColor(Palette.subtle)
        }
        // 44pt is Apple's minimum comfortable tap target; the whole row is
        // tappable, not just the text.
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// A full-width tappable Settings row.
struct SettingsActionRow: View {
    let title: String
    let icon: String
    let tint: Color
    var destructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsActionRowLabel(title: title, icon: icon, tint: tint, destructive: destructive)
        }
        .buttonStyle(.plain)
    }
}
