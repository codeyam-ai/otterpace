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
    public static let subtle = Color(red: 0.45, green: 0.47, blue: 0.54)
    public static let card = Color.white
    public static let bgTop = Color(red: 0.99, green: 0.96, blue: 0.93)
    public static let bgBottom = Color(red: 0.96, green: 0.94, blue: 0.98)
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
