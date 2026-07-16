import SwiftUI

// MARK: - Theme system
//
// Otterpace ships five whole-app looks. Default keeps the warm coral / PuffyBuddy
// identity; the four alternates (Bolt, Orbit, Fieldnote, Garden) each retint every
// screen and swap Buddy for their own mark. A `Theme` is a flat token set; the
// existing `Palette` (see Theme.swift) resolves its members from the currently
// selected theme, so all ~39 `Palette.X` call sites theme with no edit. Views that
// must *branch* on theme (the mascot/mark, per-theme background) read
// `@Environment(\.theme)` or `ThemeStore`.

/// The design tokens every surface needs. One value per theme.
public struct Theme: Equatable {
    public let id: ThemeID
    public let isDark: Bool

    // Brand + semantic accents (BuddyMood.accent maps onto these).
    public let brand: Color
    public let brandDeep: Color
    public let go: Color
    public let sky: Color
    public let amber: Color
    public let gold: Color
    public let lilac: Color

    // Surfaces + text.
    public let ink: Color
    public let subtle: Color
    public let card: Color
    public let bgTop: Color
    public let bgBottom: Color

    // The readable text/icon color to place *on* a brand/go/amber accent fill
    // (buttons, pills, chat bubbles). Light themes use white; the dark themes
    // carry deliberately *light* accents (bright teal/blue), so white would blend
    // — they use a near-black instead so on-accent text always contrasts.
    public let onAccent: Color
}

/// The five selectable looks. `.default` is the shipping identity and the default.
public enum ThemeID: String, CaseIterable, Identifiable {
    case `default`, bolt, orbit, fieldnote, garden
    public var id: String { rawValue }

    /// Human name shown in the onboarding step and Settings picker.
    public var displayName: String {
        switch self {
        case .default:   return "Otter"
        case .bolt:      return "Bolt"
        case .orbit:     return "Orbit"
        case .fieldnote: return "Fieldnote"
        case .garden:    return "Garden"
        }
    }

    /// One-line education blurb (shared by onboarding + Settings).
    public var blurb: String {
        switch self {
        case .default:   return "Warm and friendly — meet Buddy."
        case .bolt:      return "Dark and focused, built for training."
        case .orbit:     return "Cool, calm, cosmic."
        case .fieldnote: return "Warm, analog, field-guide."
        case .garden:    return "Quiet and natural."
        }
    }

    /// The resolved token set.
    public var theme: Theme {
        switch self {
        case .default:
            return Theme(id: self, isDark: false,
                brand: Color(hex: 0xFF7357), brandDeep: Color(hex: 0xED524A),
                go: Color(hex: 0x3DBC7D), sky: Color(hex: 0x5B9EED), amber: Color(hex: 0xF7B03B),
                gold: Color(hex: 0xFACC4D), lilac: Color(hex: 0x8C82DC),
                ink: Color(hex: 0x292B38), subtle: Color(hex: 0x575C6E),
                card: .white, bgTop: Color(hex: 0xFDF5EE), bgBottom: Color(hex: 0xF5F0FA),
                onAccent: .white)
        case .bolt:
            return Theme(id: self, isDark: true,
                brand: Color(hex: 0x2FE3D0), brandDeep: Color(hex: 0x17B7A6),
                go: Color(hex: 0x3DD68C), sky: Color(hex: 0x5AB0FF), amber: Color(hex: 0xFFB65A),
                gold: Color(hex: 0xFFD65A), lilac: Color(hex: 0xB49CFF),
                ink: Color(hex: 0xF5F5F7), subtle: Color(hex: 0xAEAEB4),
                card: Color(hex: 0x1B1B1D), bgTop: Color(hex: 0x0A0B0D), bgBottom: Color(hex: 0x000000),
                onAccent: Color(hex: 0x08110F))
        case .orbit:
            return Theme(id: self, isDark: true,
                brand: Color(hex: 0x74D6FF), brandDeep: Color(hex: 0x3E9FD6),
                go: Color(hex: 0x5FD6C4), sky: Color(hex: 0x9AB8FF), amber: Color(hex: 0xFFC46F),
                gold: Color(hex: 0xFFDA7A), lilac: Color(hex: 0xA79CFF),
                ink: Color(hex: 0xEAEFFA), subtle: Color(hex: 0x9AA5BE),
                card: Color(hex: 0x111524), bgTop: Color(hex: 0x0A0E1C), bgBottom: Color(hex: 0x05070E),
                onAccent: Color(hex: 0x061019))
        case .fieldnote:
            return Theme(id: self, isDark: false,
                brand: Color(hex: 0xE0562F), brandDeep: Color(hex: 0xC0421F),
                go: Color(hex: 0x1F7E8C), sky: Color(hex: 0x4E8FA0), amber: Color(hex: 0xD99A3C),
                gold: Color(hex: 0xE0B24A), lilac: Color(hex: 0x9C7B9E),
                ink: Color(hex: 0x2A2620), subtle: Color(hex: 0x7C7263),
                card: Color(hex: 0xFBF5E6), bgTop: Color(hex: 0xEFE6D2), bgBottom: Color(hex: 0xE9DFC8),
                onAccent: .white)
        case .garden:
            return Theme(id: self, isDark: false,
                brand: Color(hex: 0x4E6B54), brandDeep: Color(hex: 0x3A5340),
                go: Color(hex: 0x6F9E8B), sky: Color(hex: 0x7FB0AE), amber: Color(hex: 0xC9A24A),
                gold: Color(hex: 0xD6B85C), lilac: Color(hex: 0xC98BA8),
                ink: Color(hex: 0x26312A), subtle: Color(hex: 0x69756A),
                card: .white, bgTop: Color(hex: 0xECEFE8), bgBottom: Color(hex: 0xE4EADD),
                onAccent: .white)
        }
    }
}

// MARK: - Selection + persistence

/// Owns the selected theme, persists it as the user's personal default, and
/// re-seeds from `rbTheme` for scenario previews. Mirrors `CoachProfileStore`:
/// a single UserDefaults key + an injectable `defaults` for tests. A shared
/// instance backs `Palette`'s theme-resolved tokens; the app root observes the
/// same instance so switching re-themes the whole tree.
public final class ThemeStore: ObservableObject {
    public static let shared = ThemeStore()

    private static let key = "otterpaceTheme"
    private let defaults: UserDefaults

    @Published public var themeID: ThemeID {
        didSet { defaults.set(themeID.rawValue, forKey: Self.key) }
    }

    public var current: Theme { themeID.theme }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Scenario capture pins a theme via `rbTheme` (same launch-seed pattern as
        // rbGoalSteps); otherwise the user's saved choice; otherwise Default.
        let seeded = defaults.string(forKey: "rbTheme").flatMap { ThemeID(rawValue: $0.lowercased()) }
        let saved = defaults.string(forKey: Self.key).flatMap { ThemeID(rawValue: $0) }
        self.themeID = seeded ?? saved ?? .default
    }
}

// MARK: - App root

/// Wraps the app content: owns the shared `ThemeStore`, injects the resolved
/// theme + a matching color scheme, and keys the whole tree on the theme id so a
/// switch (from onboarding or Settings) re-themes everything cleanly.
public struct ThemedAppRoot<Content: View>: View {
    @StateObject private var themeStore = ThemeStore.shared
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        content
            .environment(\.theme, themeStore.current)
            .preferredColorScheme(themeStore.current.isDark ? .dark : .light)
    }
}

// Screen roots hold `@ObservedObject private var themeStore = ThemeStore.shared`
// so SwiftUI re-invokes their `body` when the theme changes — live theming with
// no identity reset, so switching never nukes the current screen's navigation.

// MARK: - Environment

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = ThemeID.default.theme
}

public extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Color hex helper

public extension Color {
    /// Build a Color from a 0xRRGGBB literal — keeps the theme token tables terse.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0)
    }
}
