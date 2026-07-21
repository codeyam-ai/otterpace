import SwiftUI

// MARK: - Heatmap intensity ramp

/// Maps a 0–4 intensity to an on-brand fill.
///
/// Deliberately a SINGLE hue — the theme's `brand` at rising strength, topping
/// out at `brandDeep`. An earlier version ramped `go` (green) up to `brand`
/// (coral), but interpolating between two hues passes through a muddy olive at
/// the midpoint, which looked drab in the Default theme and off-brand in all of
/// them. One hue at four strengths stays unmistakably on-theme everywhere and
/// still reads as "more" at a glance.
///
/// Level 0 is a faint `ink` wash — a rest day should read as quiet, never as a
/// hole punched in the card.
///
/// The ramp is pure opacity on ONE token rather than stepping to `brandDeep` at
/// the top: on the dark themes `brandDeep` is *darker* than `brand`, so using it
/// made the busiest day recede instead of stand out. Straight opacity is
/// strictly monotonic on every ground — on light themes each step reads deeper,
/// on dark themes each step reads brighter.
enum HeatmapRamp {
    static func fill(level: Int) -> Color {
        switch level {
        case ...0: return Palette.ink.opacity(0.07)
        case 1:    return Palette.brand.opacity(0.30)
        case 2:    return Palette.brand.opacity(0.55)
        case 3:    return Palette.brand.opacity(0.80)
        default:   return Palette.brand
        }
    }

    /// Cell border. Level 0 stays borderless so empty days recede; active cells
    /// get a hairline so adjacent same-level days remain distinguishable.
    static func stroke(level: Int) -> Color {
        level <= 0 ? .clear : Palette.ink.opacity(0.06)
    }
}
