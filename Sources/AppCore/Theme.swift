import SwiftUI

// MARK: - Otterpace palette
//
// Warm, friendly, energetic — never clinical. Coral is the brand accent,
// green signals healthy "go" states, amber/blue carry caution and rest.

// Theme-resolved brand palette. Each token reads the currently selected theme
// (`ThemeStore.shared.current`), so every existing `Palette.X` call site retints
// when the user switches looks — Default keeps the warm coral values below (see
// `ThemeID.default`). The app root observes the same `ThemeStore` and keys its
// content on the theme id, so a switch re-themes the whole tree cleanly.
public enum Palette {
    private static var t: Theme { ThemeStore.shared.current }
    public static var brand: Color { t.brand }         // coral (Default)
    public static var brandDeep: Color { t.brandDeep }
    public static var go: Color { t.go }               // fresh green
    public static var sky: Color { t.sky }             // calm blue
    public static var amber: Color { t.amber }         // caution
    public static var gold: Color { t.gold }           // celebration
    public static var lilac: Color { t.lilac }         // recovery

    public static var ink: Color { t.ink }
    // Default's subtle clears WCAG AA 4.5:1 on both the white cards and the cream
    // `bgTop`; each theme defines its own subtle for its own surfaces.
    public static var subtle: Color { t.subtle }
    public static var card: Color { t.card }
    public static var bgTop: Color { t.bgTop }
    public static var bgBottom: Color { t.bgBottom }
}

// MARK: - Typography
//
// One source of truth mapping the app's text roles to SwiftUI text styles, so
// every label scales with the user's Dynamic Type setting instead of being
// pinned to a raw point size. The rounded design and heavy/bold weights keep the
// friendly, brand display look while gaining accessibility scaling. Replaces the
// scattered `.font(.system(size:))` calls across the section components.
public enum Typography {
    public static let largeTitle = Font.system(.largeTitle, design: .rounded).weight(.heavy)   // ~Today / hero titles
    public static let title = Font.system(.title, design: .rounded).weight(.heavy)             // screen / hero headlines
    public static let title2 = Font.system(.title2, design: .rounded).weight(.heavy)           // card values, big numbers
    public static let title3 = Font.system(.title3, design: .rounded).weight(.heavy)           // sub-headlines
    public static let headline = Font.system(.headline, design: .rounded).weight(.bold)        // emphasized rows / buttons
    public static let body = Font.system(.body)                                                // sentences / chat / coach copy
    public static let callout = Font.system(.callout)                                          // secondary body
    public static let captionStrong = Font.system(.caption, design: .rounded).weight(.bold)    // section labels, pills
    public static let caption = Font.system(.caption).weight(.medium)                          // metric labels, footnotes
    public static let caption2 = Font.system(.caption2, design: .rounded).weight(.heavy)       // tiny uppercase tags
}

// MARK: - Layout
//
// One spacing/chrome scale for the whole app, so screens stop hardcoding
// one-off paddings and corner radii. Every screen's scroll rhythm, every card's
// inset, and the shared `cardStyle()` corner now read from here — change a value
// once and it lands everywhere, and reviewers can see the rhythm at a glance.
public enum Layout {
    // Spacing scale — a small, named ramp. Reach for these instead of literals.
    public static let xs: CGFloat = 6
    public static let sm: CGFloat = 10
    public static let md: CGFloat = 14
    public static let lg: CGFloat = 18
    public static let xl: CGFloat = 24

    // Screen scroll rhythm — the page margins shared by every top-level surface.
    public static let screenGutter: CGFloat = 18    // horizontal page margin
    public static let screenTop: CGFloat = 14       // first content inset
    public static let screenBottom: CGFloat = 28    // last content inset
    public static let cardSpacing: CGFloat = 16     // gap between stacked cards

    // Card chrome — the inset and corner shared by `cardStyle()` and the cards
    // that paint their own background (CoachCard's gradient, the tiles).
    public static let cardPadding: CGFloat = 16
    public static let cardCorner: CGFloat = 22
}

// MARK: - Motion
//
// The app's shared easing language. Matches the StepRing's gentle ease-out so
// the dashboard's ring, card appearance, and screen/overlay transitions all
// move with one voice. Always pair these with a Reduce-Motion check (see
// `OverlayTransition` in ViewStyles) — never animate position when the user has
// asked for less motion.
public enum Motion {
    /// The standard ease-out used for content settling into place (rings, cards).
    public static let standard = Animation.easeOut(duration: 0.35)
    /// A slightly longer ease for full-screen overlays sliding in (history,
    /// weekly review, settings).
    public static let overlay = Animation.easeOut(duration: 0.4)
}

// MARK: - Buddy mood

public enum BuddyMood: String, CaseIterable {
    case resting, ready, jogging, cheering, concerned, celebrating, recovery

    public init(raw: String) {
        self = BuddyMood(rawValue: raw.lowercased()) ?? .ready
    }

    /// The accent color that tints Buddy's halo and the mood chip.
    public var accent: Color {
        switch self {
        case .resting:     return Palette.sky
        case .ready:       return Palette.brand
        case .jogging:     return Palette.go
        case .cheering:    return Palette.go
        case .concerned:   return Palette.amber
        case .celebrating: return Palette.gold
        case .recovery:    return Palette.lilac
        }
    }

    /// One-word caption shown under Buddy.
    public var caption: String {
        switch self {
        case .resting:     return "Resting"
        case .ready:       return "Ready"
        case .jogging:     return "On a roll"
        case .cheering:    return "Cheering"
        case .concerned:   return "Take it easy"
        case .celebrating: return "Celebrating"
        case .recovery:    return "Recovery"
        }
    }
}
