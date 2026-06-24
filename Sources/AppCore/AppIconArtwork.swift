import SwiftUI

// MARK: - App icon artwork
//
// The RunBuddy app icon, composed in code so it stays pixel-consistent with the
// in-app mascot and is regenerable when the art changes. Buddy the otter on a
// full-bleed, opaque coral background (the brand `Palette.brand → brandDeep`
// gradient), with the translucent mood halo suppressed so the silhouette reads
// cleanly. Authored at a nominal 512pt canvas and resolution-independent, so
// `ImageRenderer` can rasterize it to the 1024×1024 marketing icon.
//
// App Store constraints the artwork satisfies: fully opaque (no alpha), square,
// no rounded corners (iOS applies the superellipse mask itself), no text.

public struct AppIconArtwork: View {
    public var mood: BuddyMood
    public var canvas: CGFloat

    public init(mood: BuddyMood = .ready, canvas: CGFloat = 512) {
        self.mood = mood
        self.canvas = canvas
    }

    public var body: some View {
        ZStack {
            // Opaque coral background, edge to edge — the icon square is fully painted.
            LinearGradient(
                colors: [Palette.brand, Palette.brandDeep],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            // A soft top sheen for a little depth, still fully opaque.
            RadialGradient(
                colors: [Color.white.opacity(0.18), Color.clear],
                center: .init(x: 0.5, y: 0.32),
                startRadius: 0, endRadius: canvas * 0.7
            )

            // Buddy, centered, ~66% of the square, no halo, with a soft drop shadow
            // so the silhouette stays clear at small sizes.
            PuffyBuddy(mood: mood, size: canvas * 0.5, showHalo: false)
                .shadow(color: Palette.brandDeep.opacity(0.35), radius: canvas * 0.03, x: 0, y: canvas * 0.015)
        }
        .frame(width: canvas, height: canvas)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("RunBuddy app icon")
    }
}

// Scenario-only showcase of the app icon: the raw square as TestFlight/App Store
// sees it, the same artwork under iOS's rounded superellipse mask, a mood
// comparison, and a small-size legibility check. Rendered via `rbPreviewMode =
// "app-icon"` through `BuddyPreviewHost`.
public struct AppIconPreviewGallery: View {
    public init() {}

    private let candidateMoods: [BuddyMood] = [.ready, .celebrating, .cheering]

    public var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                Text("RunBuddy — App Icon")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(Palette.ink)
                    .padding(.top, 16)

                VStack(spacing: 10) {
                    AppIconArtwork(mood: .ready, canvas: 200)
                        .frame(width: 200, height: 200)
                    Text("Full square (1024 export)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Palette.subtle)
                }

                VStack(spacing: 10) {
                    AppIconArtwork(mood: .ready, canvas: 200)
                        .frame(width: 200, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 45, style: .continuous))
                        .shadow(color: Palette.ink.opacity(0.18), radius: 10, y: 6)
                    Text("On the home screen (masked)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Palette.subtle)
                }

                VStack(spacing: 10) {
                    HStack(spacing: 16) {
                        ForEach(candidateMoods, id: \.self) { m in
                            AppIconArtwork(mood: m, canvas: 84)
                                .frame(width: 84, height: 84)
                                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                        }
                    }
                    Text("Mood comparison")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Palette.subtle)
                }

                VStack(spacing: 10) {
                    AppIconArtwork(mood: .ready, canvas: 60)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Text("Small size (~60px legibility)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Palette.subtle)
                }
                .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
