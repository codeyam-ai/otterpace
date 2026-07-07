import SwiftUI

// Isolation scaffold for RaceImportSheet — codeyam renders this View standalone on the
// booted iOS simulator. CODEYAM_ISOLATE_COMPONENT=RaceImportSheet selects this struct in
// CodeyamIsolationHost.swift; CODEYAM_ISOLATE_SCENARIO picks the scenario below.
//
// TODO: seed real props per scenario (closures are stubbed — isolated rendering
// is about appearance, not behavior), then register each scenario:
//   codeyam-editor editor register '{"name":"RaceImportSheet - Default","componentName":"RaceImportSheet","deviceState":{"launchEnv":{"CODEYAM_ISOLATE_COMPONENT":"RaceImportSheet","CODEYAM_ISOLATE_SCENARIO":"Default"}},"dimensions":["iPhone 16"]}'
struct RaceImportSheetIsolated: View {
    let scenario: String

    var body: some View {
        switch scenario {
        case "No Key":
            // No coach key connected (the simulator has no keychain key) — the
            // graceful-degradation state: explain, and offer manual entry.
            RaceImportSheet(onPrefill: { _, _ in }, onManual: {}, onCancel: {})
        default:
            RaceImportSheet(onPrefill: { _, _ in }, onManual: {}, onCancel: {})
        }
    }
}
