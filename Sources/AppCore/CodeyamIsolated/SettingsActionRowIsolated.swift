import SwiftUI

// Isolation scaffold for SettingsActionRow — codeyam renders this View standalone on the
// booted iOS simulator. CODEYAM_ISOLATE_COMPONENT=SettingsActionRow selects this struct in
// CodeyamIsolationHost.swift; CODEYAM_ISOLATE_SCENARIO picks the scenario below.
//
// The shared Settings row affordance has three looks: a normal action (tinted icon,
// trailing chevron), a destructive one (brand-deep title), and an external link
// (out-arrow instead of the chevron, rendered via SettingsActionRowLabel inside a Link).
// One scenario shows all three stacked so the variants can be compared directly.
struct SettingsActionRowIsolated: View {
    let scenario: String

    var body: some View {
        VStack(spacing: 0) {
            SettingsActionRow(title: "Connect", icon: "sparkles", tint: Palette.brand) {}
            Divider().opacity(0.25)
            SettingsActionRow(title: "Disconnect", icon: "xmark.circle",
                              tint: Palette.brandDeep, destructive: true) {}
            Divider().opacity(0.25)
            // The label alone is what a Link wraps for an external destination.
            SettingsActionRowLabel(title: "Get an Anthropic API key", icon: "key",
                                   tint: Palette.sky, external: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Full-bleed opaque backdrop: a plain `.background` stays inside the safe
        // area, so the launch screen shows through the gaps and a capture picks up
        // a ghost splash behind the component.
        .background(Palette.bgTop.ignoresSafeArea())
    }
}
