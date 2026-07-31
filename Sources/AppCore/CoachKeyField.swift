import SwiftUI

// The paste-a-key field in the Settings AI Coach card.
//
// One field for all three providers: the provider is recognized from the key's
// shape as you type, and named back to you before you commit. A key whose shape
// matches nothing is NOT rejected — providers change their prefixes, and a
// perfectly valid key should never be turned away — so the field asks which
// provider it belongs to instead.
//
// Props-driven apart from the draft binding it owns with its parent, so the
// empty, detected, and unrecognized states are all capturable in isolation.
struct CoachKeyField: View {
    @Binding var draft: String
    /// Set by the parent when a Connect attempt matched no known provider.
    @Binding var unrecognized: Bool
    /// Called with the provider the key should be filed under.
    var onConnect: (CoachProvider) -> Void = { _ in }
    /// Called when Connect is pressed on a key matching no known shape.
    var onUnrecognized: () -> Void = {}

    /// The key as it would be saved, and the provider its shape identifies.
    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var detected: CoachProvider? { CoachProvider.detect(fromKey: trimmed) }


    var body: some View {
        SecureField("sk-ant-…, sk-…, or AIza…", text: $draft)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("AI provider API key")
            // Editing clears a stale "we didn't recognize that" so the picker
            // doesn't linger over a key the user has since corrected.
            .onChange(of: draft) { _ in unrecognized = false }

        if let detected, !trimmed.isEmpty {
            Label("Recognized as \(detected.displayName)", systemImage: "checkmark.seal")
                .font(Typography.caption).foregroundColor(Palette.brandDeep)
        }

        if unrecognized {
            Text("That key doesn't match a shape we recognize. Which provider is it from?")
                .font(Typography.caption).foregroundColor(Palette.amber)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(CoachProvider.displayOrder, id: \.self) { provider in
                SettingsActionRow(title: "Use as \(provider.displayName)", icon: "key", tint: Palette.sky) {
                    onConnect(provider)
                }
            }
        } else {
            SettingsActionRow(title: "Connect", icon: "sparkles", tint: Palette.brand) {
                guard !trimmed.isEmpty else { return }
                guard let provider = detected else {
                    onUnrecognized()
                    return
                }
                onConnect(provider)
            }
        }

        // Where to go if you don't have a key yet. Self-contained — it takes
        // nothing from this field's draft or detection state.
        CoachConsoleLinkRow()
    }
}
