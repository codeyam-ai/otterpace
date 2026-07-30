import SwiftUI

// Isolation scaffold for CoachProviderRow — codeyam renders this View standalone on the
// booted iOS simulator. CODEYAM_ISOLATE_COMPONENT=CoachProviderRow selects this struct in
// CodeyamIsolationHost.swift; CODEYAM_ISOLATE_SCENARIO picks the scenario below.
//
// The row varies along three axes: which provider it names (each has its own display
// name and model family), whether it is the active coach, and whether there is anything
// to switch to. Each scenario lists providers together so the active/inactive contrast
// and the per-provider attribution copy read in one frame.
struct CoachProviderRowIsolated: View {
    let scenario: String

    private func list(_ providers: [CoachProvider], active: CoachProvider?, canSwitch: Bool = true) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(providers.enumerated()), id: \.element) { idx, provider in
                if idx > 0 { Divider().opacity(0.25) }
                CoachProviderRow(provider: provider,
                                 isActive: active == provider,
                                 canSwitch: canSwitch)
            }
        }
    }

    var body: some View {
        Group {
            switch scenario {
            case "Single Connected":
                // The migrated Anthropic-only user: active, and nothing to switch
                // to. Must render at full strength, never dimmed.
                list([.anthropic], active: .anthropic, canSwitch: false)
            case "OpenAI Active":
                list([.anthropic, .openai], active: .openai)
            case "Gemini Active":
                list(CoachProvider.displayOrder, active: .gemini)
            default:
                // Every provider, Anthropic active — shows all three names and the
                // attribution copy for the active one in a single frame.
                list(CoachProvider.displayOrder, active: .anthropic)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Full-bleed opaque backdrop: a plain `.background` stays inside the safe
        // area, so the launch screen shows through the gaps and a capture picks up
        // a ghost splash behind the component.
        .background(Palette.bgTop.ignoresSafeArea())
    }
}
