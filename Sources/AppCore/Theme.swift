import SwiftUI

// MARK: - RunBuddy palette
//
// Warm, friendly, energetic — never clinical. Coral is the brand accent,
// green signals healthy "go" states, amber/blue carry caution and rest.

public enum Palette {
    public static let brand = Color(red: 1.00, green: 0.45, blue: 0.34)   // coral
    public static let brandDeep = Color(red: 0.93, green: 0.32, blue: 0.27)
    public static let go = Color(red: 0.24, green: 0.74, blue: 0.49)      // fresh green
    public static let sky = Color(red: 0.36, green: 0.62, blue: 0.93)     // calm blue
    public static let amber = Color(red: 0.97, green: 0.69, blue: 0.23)   // caution
    public static let gold = Color(red: 0.98, green: 0.80, blue: 0.30)    // celebration
    public static let lilac = Color(red: 0.55, green: 0.51, blue: 0.86)   // recovery

    public static let ink = Color(red: 0.16, green: 0.17, blue: 0.22)
    // Darkened from (0.45,0.47,0.54) ≈ 3.4:1 to clear WCAG AA 4.5:1 on both the
    // white cards and the cream `bgTop` gradient. Used for every caption/label.
    public static let subtle = Color(red: 0.34, green: 0.36, blue: 0.43)
    public static let card = Color.white
    public static let bgTop = Color(red: 0.99, green: 0.96, blue: 0.93)
    public static let bgBottom = Color(red: 0.96, green: 0.94, blue: 0.98)
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
