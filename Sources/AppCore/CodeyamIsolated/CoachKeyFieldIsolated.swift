import SwiftUI

// Isolation scaffold for CoachKeyField — codeyam renders this View standalone on the
// booted iOS simulator. CODEYAM_ISOLATE_COMPONENT=CoachKeyField selects this struct in
// CodeyamIsolationHost.swift; CODEYAM_ISOLATE_SCENARIO picks the scenario below.
//
// The field has four states worth seeing: empty (the combined placeholder plus the
// "Get an API key" row), a recognized key (the detection confirmation), an
// unrecognized key (the "which provider is it from?" picker instead of a rejection),
// and the console chooser open. The draft is held here so each scenario renders its
// state on the first frame, with no typing required; the chooser's open state comes
// from the `rbShowKeyProviderPicker` default, seeded by the scenario itself.
struct CoachKeyFieldIsolated: View {
    let scenario: String

    @State private var draft: String
    @State private var unrecognized: Bool

    init(scenario: String) {
        self.scenario = scenario
        switch scenario {
        case "Detected Gemini":
            _draft = State(initialValue: "AIzaSyExampleGeminiKey")
            _unrecognized = State(initialValue: false)
        case "Detected OpenAI":
            _draft = State(initialValue: "sk-proj-ExampleOpenAIKey")
            _unrecognized = State(initialValue: false)
        case "Unrecognized Key":
            _draft = State(initialValue: "my-companys-internal-key")
            _unrecognized = State(initialValue: true)
        default:
            _draft = State(initialValue: "")
            _unrecognized = State(initialValue: false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CoachKeyField(draft: $draft, unrecognized: $unrecognized)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Full-bleed opaque backdrop: a plain `.background` stays inside the safe
        // area, so the launch screen shows through the gaps and a capture picks up
        // a ghost splash behind the component.
        .background(Palette.bgTop.ignoresSafeArea())
    }
}
