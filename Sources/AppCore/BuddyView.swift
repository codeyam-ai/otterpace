import SwiftUI

// MARK: - Buddy the dog
//
// A friendly pup mascot drawn entirely with SwiftUI shapes so it scales
// crisply and reflects mood: eyes, tongue, and a small accessory change with
// the coach's read of how the day is going.

public struct BuddyView: View {
    public let mood: BuddyMood
    public var size: CGFloat

    public init(mood: BuddyMood, size: CGFloat = 120) {
        self.mood = mood
        self.size = size
    }

    private let fur = Color(red: 0.85, green: 0.66, blue: 0.45)
    private let furDark = Color(red: 0.64, green: 0.46, blue: 0.30)
    private let snout = Color(red: 0.96, green: 0.89, blue: 0.79)

    public var body: some View {
        ZStack {
            Circle()
                .fill(mood.accent.opacity(0.16))
                .frame(width: size * 1.28, height: size * 1.28)

            ears
            Circle().fill(fur).frame(width: size, height: size)
            patch
            snoutGroup
            eyes
            accessory
        }
        .frame(width: size * 1.3, height: size * 1.3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Buddy looking \(mood.caption.lowercased())")
    }

    private var ears: some View {
        ZStack {
            Ellipse().fill(furDark)
                .frame(width: size * 0.30, height: size * 0.52)
                .rotationEffect(.degrees(-22))
                .offset(x: -size * 0.36, y: -size * 0.10)
            Ellipse().fill(furDark)
                .frame(width: size * 0.30, height: size * 0.52)
                .rotationEffect(.degrees(22))
                .offset(x: size * 0.36, y: -size * 0.10)
        }
    }

    // A soft darker patch over one eye for character.
    private var patch: some View {
        Circle().fill(furDark.opacity(0.55))
            .frame(width: size * 0.34, height: size * 0.34)
            .offset(x: size * 0.17, y: -size * 0.10)
    }

    private var snoutGroup: some View {
        ZStack {
            Ellipse().fill(snout)
                .frame(width: size * 0.52, height: size * 0.40)
                .offset(y: size * 0.20)
            // nose
            Ellipse().fill(Color.black.opacity(0.82))
                .frame(width: size * 0.17, height: size * 0.13)
                .offset(y: size * 0.10)
            tongue
        }
    }

    @ViewBuilder private var tongue: some View {
        if mood == .cheering || mood == .celebrating || mood == .jogging {
            Capsule().fill(Color(red: 0.95, green: 0.45, blue: 0.50))
                .frame(width: size * 0.14, height: size * 0.18)
                .offset(y: size * 0.30)
        }
    }

    private var eyes: some View {
        HStack(spacing: size * 0.24) {
            eye
            eye
        }
        .offset(y: -size * 0.06)
    }

    @ViewBuilder private var eye: some View {
        switch mood {
        case .resting, .recovery:
            // closed, content
            Capsule().fill(Color.black.opacity(0.8))
                .frame(width: size * 0.13, height: size * 0.03)
        case .cheering, .celebrating:
            // happy upward arcs
            ArcEye().stroke(Color.black.opacity(0.82), lineWidth: size * 0.035)
                .frame(width: size * 0.15, height: size * 0.09)
        case .concerned:
            Circle().fill(Color.black.opacity(0.82))
                .frame(width: size * 0.10, height: size * 0.10)
        default:
            Circle().fill(Color.black.opacity(0.82))
                .frame(width: size * 0.12, height: size * 0.12)
        }
    }

    @ViewBuilder private var accessory: some View {
        switch mood {
        case .celebrating, .cheering:
            Text("✨")
                .font(.system(size: size * 0.26))
                .offset(x: size * 0.52, y: -size * 0.46)
        case .resting, .recovery:
            Text("💤")
                .font(.system(size: size * 0.24))
                .offset(x: size * 0.46, y: -size * 0.48)
        case .concerned:
            Circle().fill(Palette.sky.opacity(0.85))
                .frame(width: size * 0.12, height: size * 0.16)
                .offset(x: size * 0.40, y: -size * 0.30)
        case .jogging:
            Text("💨")
                .font(.system(size: size * 0.22))
                .offset(x: -size * 0.55, y: size * 0.10)
        case .ready:
            Text("🦴")
                .font(.system(size: size * 0.22))
                .offset(x: size * 0.50, y: size * 0.30)
        }
    }
}

// Upward-curving "happy" eye.
private struct ArcEye: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.minY - rect.height)
        )
        return p
    }
}
