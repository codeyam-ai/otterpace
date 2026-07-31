import SwiftUI

/// "Get an API key" — one row that opens a chooser for all three provider
/// consoles.
///
/// This replaced a link that pointed at whichever provider was detected in the
/// pasted key, falling back to Anthropic while the field was empty. That
/// inverted the actual journey: you visit a provider's console in order to
/// CREATE a key you don't have yet, so keying the destination off a key you had
/// already pasted offered the link at precisely the moment it was useless — and
/// left OpenAI and Gemini unreachable for anyone who hadn't already got one of
/// their keys. A chooser makes all three reachable from the state that actually
/// needs them: empty-handed.
///
/// Self-contained by design: it holds no reference to the key field's draft or
/// detection state, which is why it lives here rather than inside
/// `CoachKeyField`. Rows are built from `CoachProvider.displayOrder` and
/// `consoleURL`, so adding a fourth provider needs no change here.
struct CoachConsoleLinkRow: View {
    /// Whether the chooser is up. Seeded from `rbShowKeyProviderPicker` in
    /// `init` (not `.onAppear`) so a scenario capture catches the dialog on the
    /// FIRST frame — the simulator screenshots before a post-appear
    /// presentation would land. Production never carries that key, and every
    /// scenario seeds its OFF value explicitly, because an omitted rb* key
    /// persists from whichever scenario ran previously.
    @State private var showConsolePicker: Bool

    init(forcePickerOpen: Bool? = nil) {
        _showConsolePicker = State(initialValue: forcePickerOpen
            ?? UserDefaults.standard.bool(forKey: "rbShowKeyProviderPicker"))
    }

    var body: some View {
        SettingsActionRow(title: "Get an API key", icon: "key", tint: Palette.sky) {
            showConsolePicker = true
        }
        .confirmationDialog("Where do you want to get a key?",
                            isPresented: $showConsolePicker,
                            titleVisibility: .visible) {
            // `if let` on the URL means a provider with no console would vanish
            // silently — exactly the bug this row exists to fix. CoachProviderConsoleTests
            // asserts every provider has one, so that can't regress unnoticed.
            ForEach(CoachProvider.displayOrder, id: \.self) { provider in
                if let url = provider.consoleURL {
                    Link(provider.displayName, destination: url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each provider bills you directly for what Buddy asks. Your key stays on this device.")
        }
    }
}
