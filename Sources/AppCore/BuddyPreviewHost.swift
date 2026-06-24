import SwiftUI

// MARK: - Buddy preview host
//
// A scenario-only surface for showcasing the Buddy mascot in isolation. When a
// scenario seeds `rbPreviewMode`, `ContentView` renders this host instead of the
// normal app:
//
//   rbPreviewMode = "puffy-moods"  → Buddy across all 7 moods
//   rbPreviewMode = "puffy-loader" → the bouncy loading state
//
// Production (no `rbPreviewMode`) never shows this — it renders the real app.

public struct BuddyPreviewHost: View {
    public let mode: String

    public init(mode: String) {
        self.mode = mode
    }

    public var body: some View {
        switch mode {
        case "puffy-loader":
            PuffyBuddyLoader(size: 122)
        case "app-icon":
            AppIconPreviewGallery()
        default:
            PuffyBuddyGallery()
        }
    }
}
