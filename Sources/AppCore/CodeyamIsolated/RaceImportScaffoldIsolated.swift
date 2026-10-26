import SwiftUI

// Isolation scaffold for RaceImportScaffold — codeyam renders this View standalone on the
// booted iOS simulator. CODEYAM_ISOLATE_COMPONENT=RaceImportScaffold selects this struct in
// CodeyamIsolationHost.swift; CODEYAM_ISOLATE_SCENARIO picks the scenario below.
struct RaceImportScaffoldIsolated: View {
    let scenario: String

    var body: some View {
        RaceImportScaffold(title: "Import from URL", onCancel: {}) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Paste a race page link and Buddy will fill in the details.")
                    .font(Typography.callout).foregroundColor(Palette.ink)
                RoundedRectangle(cornerRadius: 12)
                    .fill(Palette.ink.opacity(0.06))
                    .frame(height: 48)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
