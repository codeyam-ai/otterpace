import SwiftUI

// Isolation scaffold for CoachConsoleLinkRow — codeyam renders this View standalone on
// the booted iOS simulator. CODEYAM_ISOLATE_COMPONENT=CoachConsoleLinkRow selects this
// struct in CodeyamIsolationHost.swift; CODEYAM_ISOLATE_SCENARIO picks the scenario.
//
// Two states worth seeing: the collapsed row as it sits in the AI Coach card, and the
// chooser open showing all three consoles — the latter being the whole point of the
// component, since the row it replaced could only ever reach Anthropic.
//
// The open state is forced through the initializer rather than the UserDefaults seed,
// so the scenario does not depend on a preference surviving injection.
struct CoachConsoleLinkRowIsolated: View {
    let scenario: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CoachConsoleLinkRow(forcePickerOpen: scenario == "Picker Open")
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Full-bleed opaque backdrop: a plain `.background` stays inside the safe
        // area, so the launch screen shows through the gaps and a capture picks up
        // a ghost splash behind the component.
        .background(Palette.bgTop.ignoresSafeArea())
    }
}
