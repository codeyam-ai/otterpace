import SwiftUI

// Isolation scaffold for ThemeSwatch — codeyam renders this View standalone on the
// booted iOS simulator. CODEYAM_ISOLATE_COMPONENT=ThemeSwatch selects this struct in
// CodeyamIsolationHost.swift; CODEYAM_ISOLATE_SCENARIO picks the scenario below.
//
// Each ThemeSwatch previews one theme's own colors + identity mark (PuffyBuddy for
// Default, the ThemeMark otherwise). The "All Themes" scenario shows every look at
// once; the singles isolate a light (Default) and a dark (Bolt) tile.
struct ThemeSwatchIsolated: View {
    let scenario: String

    private func swatch(_ id: ThemeID) -> some View {
        ThemeSwatch(id: id, tileSize: 72, corner: 14, markSize: 42, puffySize: 46)
    }

    var body: some View {
        Group {
            switch scenario {
            case "All Themes":
                VStack(spacing: 18) {
                    ForEach(ThemeID.allCases) { id in
                        HStack(spacing: 16) {
                            swatch(id)
                            Text(id.displayName).font(Typography.headline)
                            Spacer()
                        }
                    }
                }
            case "Bolt":
                swatch(.bolt)
            default:
                swatch(.default)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0xF2F2F7))
    }
}
