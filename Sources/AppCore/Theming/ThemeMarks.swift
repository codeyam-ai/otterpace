import SwiftUI

// MARK: - Theme marks
//
// Each non-Default theme replaces PuffyBuddy with its own abstract brand mark,
// drawn as SwiftUI shapes from the approved mockups: Bolt (lightning glyph),
// Orbit (icy water-world planet), Fieldnote (field-seal with a river route),
// Garden (water-lily monogram). All scale to a `size` and read theme colors.
// `BuddyView` picks PuffyBuddy for Default or the mark for the others.

private func pt(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

/// Bolt — a sharp lightning glyph.
public struct BoltMark: View {
    let size: CGFloat; let color: Color
    public init(size: CGFloat, color: Color) { self.size = size; self.color = color }
    public var body: some View {
        Path { p in
            let s = size
            p.move(to: pt(0.585, 0.07, s))
            p.addLine(to: pt(0.205, 0.545, s))
            p.addLine(to: pt(0.455, 0.545, s))
            p.addLine(to: pt(0.375, 0.93, s))
            p.addLine(to: pt(0.80, 0.42, s))
            p.addLine(to: pt(0.545, 0.42, s))
            p.closeSubpath()
        }
        .fill(color)
        .frame(width: size, height: size)
    }
}

/// Orbit — an icy water-world planet with a thin ring and glow.
public struct OrbitMark: View {
    let size: CGFloat; let ice: Color
    public init(size: CGFloat, ice: Color) { self.size = size; self.ice = ice }
    public var body: some View {
        let s = size
        ZStack {
            // orbit path (behind)
            Ellipse().stroke(ice.opacity(0.4), lineWidth: max(1, s * 0.014))
                .frame(width: s * 0.92, height: s * 0.34)
                .rotationEffect(.degrees(-22))
            // planet body
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xF0FAFF), Color(hex: 0x8FD2F2), Color(hex: 0x37749F)],
                                     center: .init(x: 0.38, y: 0.32), startRadius: 0, endRadius: s * 0.34))
                .frame(width: s * 0.54, height: s * 0.54)
            // ice bands
            Path { p in
                p.move(to: pt(0.28, 0.40, s)); p.addQuadCurve(to: pt(0.72, 0.40, s), control: pt(0.50, 0.46, s))
            }.stroke(Color(hex: 0xF0FAFF).opacity(0.5), lineWidth: s * 0.014)
            Path { p in
                p.move(to: pt(0.26, 0.60, s)); p.addQuadCurve(to: pt(0.74, 0.60, s), control: pt(0.50, 0.66, s))
            }.stroke(Color(hex: 0xF0FAFF).opacity(0.4), lineWidth: s * 0.012)
            // front of the ring
            Ellipse().stroke(Color(hex: 0xC6EEFF).opacity(0.85), lineWidth: s * 0.02)
                .frame(width: s * 0.78, height: s * 0.22)
                .rotationEffect(.degrees(-22))
                .mask(Rectangle().frame(width: s, height: s * 0.5).offset(y: s * 0.14))
        }
        .frame(width: size, height: size)
        .shadow(color: ice.opacity(0.5), radius: s * 0.12)
    }
}

/// Fieldnote — a letterpress field-seal: double ring, tick marks, a river route.
public struct FieldnoteMark: View {
    let size: CGFloat; let ink: Color; let teal: Color
    public init(size: CGFloat, ink: Color, teal: Color) { self.size = size; self.ink = ink; self.teal = teal }
    public var body: some View {
        let s = size
        ZStack {
            Circle().stroke(teal.opacity(0.5), lineWidth: s * 0.024).frame(width: s * 0.8, height: s * 0.8).offset(x: s * 0.012, y: s * 0.012)
            Circle().stroke(ink, lineWidth: s * 0.024).frame(width: s * 0.8, height: s * 0.8)
            Circle().stroke(ink.opacity(0.45), lineWidth: s * 0.01).frame(width: s * 0.67, height: s * 0.67)
            // tick marks
            ForEach(0..<4, id: \.self) { i in
                Rectangle().fill(ink).frame(width: s * 0.018, height: s * 0.05)
                    .offset(y: -s * 0.4)
                    .rotationEffect(.degrees(Double(i) * 90))
            }
            // river route
            Path { p in
                p.move(to: pt(0.28, 0.58, s))
                p.addQuadCurve(to: pt(0.50, 0.52, s), control: pt(0.40, 0.38, s))
                p.addQuadCurve(to: pt(0.72, 0.42, s), control: pt(0.60, 0.66, s))
            }.stroke(teal, style: .init(lineWidth: s * 0.028, lineCap: .round))
            Circle().fill(teal).frame(width: s * 0.06, height: s * 0.06).offset(x: -s * 0.22, y: s * 0.08)
            Circle().fill(ink).frame(width: s * 0.07, height: s * 0.07).offset(x: s * 0.22, y: -s * 0.08)
        }
        .frame(width: size, height: size)
    }
}

/// Garden — a water-lily monogram: an O ring with a sprig growing through it.
public struct GardenMark: View {
    let size: CGFloat; let color: Color; let bud: Color
    public init(size: CGFloat, color: Color, bud: Color) { self.size = size; self.color = color; self.bud = bud }
    public var body: some View {
        let s = size
        let lw = s * 0.02
        ZStack {
            Circle().stroke(color, lineWidth: lw).frame(width: s * 0.6, height: s * 0.6)
            Path { p in p.move(to: pt(0.50, 0.78, s)); p.addLine(to: pt(0.50, 0.26, s)) }
                .stroke(color, style: .init(lineWidth: lw, lineCap: .round))
            leaf(0.50, 0.64, 0.37, 0.49, true, s)
            leaf(0.50, 0.58, 0.63, 0.43, false, s)
            leaf(0.50, 0.49, 0.39, 0.35, true, s)
            leaf(0.50, 0.43, 0.61, 0.29, false, s)
            Path { p in
                p.move(to: pt(0.50, 0.26, s))
                p.addCurve(to: pt(0.50, 0.15, s), control1: pt(0.47, 0.22, s), control2: pt(0.47, 0.18, s))
                p.addCurve(to: pt(0.50, 0.26, s), control1: pt(0.53, 0.18, s), control2: pt(0.53, 0.22, s))
            }.stroke(color, style: .init(lineWidth: lw, lineCap: .round, lineJoin: .round))
            Circle().fill(bud).frame(width: s * 0.04, height: s * 0.04).offset(y: s * 0.03)
        }
        .frame(width: size, height: size)
    }
    private func leaf(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ left: Bool, _ s: CGFloat) -> some View {
        Path { p in
            p.move(to: pt(x0, y0, s))
            p.addCurve(to: pt(x1, y1, s),
                       control1: pt(left ? x0 - 0.08 : x0 + 0.08, y0 - 0.02, s),
                       control2: pt(x1, y1 + 0.06, s))
        }.stroke(GardenMark.stroke(color), style: .init(lineWidth: s * 0.02, lineCap: .round))
    }
    private static func stroke(_ c: Color) -> Color { c }
}

// MARK: - Dispatcher + Buddy swap

/// The theme's mark at a given size (empty for Default, which uses PuffyBuddy).
public struct ThemeMark: View {
    public let theme: Theme
    public let size: CGFloat
    public init(theme: Theme, size: CGFloat) { self.theme = theme; self.size = size }
    @ViewBuilder public var body: some View {
        switch theme.id {
        case .bolt:      BoltMark(size: size, color: theme.brand)
        case .orbit:     OrbitMark(size: size, ice: theme.brand)
        case .fieldnote: FieldnoteMark(size: size, ink: theme.ink, teal: theme.go)
        case .garden:    GardenMark(size: size, color: theme.brand, bud: theme.lilac)
        case .default:   EmptyView()
        }
    }
}

/// The app's mascot slot: PuffyBuddy for Default, the theme mark otherwise. On
/// mood surfaces the non-Default mark sits inside a mood-accent halo, so mood
/// still reads through color when there's no face.
public struct BuddyView: View {
    public let mood: BuddyMood
    public var size: CGFloat
    public var showHalo: Bool
    @Environment(\.theme) private var theme

    public init(mood: BuddyMood, size: CGFloat = 120, showHalo: Bool = true) {
        self.mood = mood; self.size = size; self.showHalo = showHalo
    }

    public var body: some View {
        if theme.id == .default {
            PuffyBuddy(mood: mood, size: size, showHalo: showHalo)
        } else {
            ZStack {
                if showHalo {
                    Circle().fill(mood.accent.opacity(theme.isDark ? 0.22 : 0.16))
                        .frame(width: size * 1.34, height: size * 1.34)
                }
                ThemeMark(theme: theme, size: size)
            }
            .frame(width: size * 1.36, height: size * 1.36)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Otterpace \(theme.id.displayName) mark")
        }
    }
}
