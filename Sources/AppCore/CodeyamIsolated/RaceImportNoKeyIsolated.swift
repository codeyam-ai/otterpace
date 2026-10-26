import SwiftUI

// Isolation scaffold for RaceImportNoKey — codeyam renders this View standalone on the
// booted iOS simulator. CODEYAM_ISOLATE_COMPONENT=RaceImportNoKey selects this struct in
// CodeyamIsolationHost.swift; CODEYAM_ISOLATE_SCENARIO picks the scenario below.
struct RaceImportNoKeyIsolated: View {
    let scenario: String

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Palette.bgTop, Palette.bgBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            Group {
                switch scenario {
                case "Search With OpenAI":
                    // A key IS connected but it's not the provider the user expects —
                    // the sentence names the active provider rather than a fixed one.
                    RaceImportNoKey(action: "Searching", provider: .openai, onManual: {})
                default:
                    // Nothing connected: the import sheet's graceful-degradation state.
                    RaceImportNoKey(action: "Importing", provider: nil, onManual: {})
                }
            }
            .padding(20)
        }
    }
}
