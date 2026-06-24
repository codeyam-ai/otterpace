import SwiftUI

// MARK: - Puffy Buddy — the chosen direction
//
// The winning mascot: Buddy the otter, rendered in the "Puffy" 3D style
// (inflated, bouncy, glossy, soft-shadowed) — small round ears, a broad soft
// muzzle. Production-bound Buddy, drawn across the full mood range with a matching
// bouncy loader. All SwiftUI shapes.

public struct PuffyBuddy: View {
    public let mood: BuddyMood
    public var size: CGFloat
    // Whether to draw the translucent mood-accent halo behind Buddy. The app icon
    // composes Buddy on a solid coral background and suppresses the halo so the
    // silhouette reads cleanly.
    public var showHalo: Bool

    public init(mood: BuddyMood, size: CGFloat = 120, showHalo: Bool = true) {
        self.mood = mood
        self.size = size
        self.showHalo = showHalo
    }

    private var furTop: Color { Color(red: 0.95, green: 0.78, blue: 0.58) }
    private var furBottom: Color { Color(red: 0.80, green: 0.58, blue: 0.40) }
    private var earColor: Color { Color(red: 0.78, green: 0.56, blue: 0.38) }
    private var snout: Color { Color(red: 0.99, green: 0.95, blue: 0.90) }
    private let ink = Color(red: 0.16, green: 0.14, blue: 0.12)

    public var body: some View {
        ZStack {
            if showHalo {
                Circle().fill(mood.accent.opacity(0.16))
                    .frame(width: size * 1.34, height: size * 1.34)
            }

            // small round otter ears, set high & wide
            otterEar.offset(x: -size * 0.33, y: -size * 0.34)
            otterEar.offset(x: size * 0.33, y: -size * 0.34)

            // inflated head
            Circle()
                .fill(RadialGradient(colors: [furTop, furBottom],
                                     center: .init(x: 0.40, y: 0.30),
                                     startRadius: size * 0.04, endRadius: size * 0.78))
                .frame(width: size, height: size)
                .shadow(color: furBottom.opacity(0.45), radius: size * 0.07, x: 0, y: size * 0.06)

            // big soft highlight (the "puffy" sheen)
            Ellipse().fill(Color.white.opacity(0.42))
                .frame(width: size * 0.40, height: size * 0.24)
                .offset(x: -size * 0.17, y: -size * 0.27)
                .blur(radius: size * 0.015)

            // cheeks
            cheek.offset(x: -size * 0.30, y: size * 0.11)
            cheek.offset(x: size * 0.30, y: size * 0.11)

            snoutGroup
            eyes
        }
        .frame(width: size * 1.36, height: size * 1.36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Buddy the otter looking \(mood.caption.lowercased())")
    }

    private var otterEar: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [earColor, furBottom], startPoint: .top, endPoint: .bottom))
            Circle().fill(furBottom.opacity(0.55)).scaleEffect(0.5)
        }
        .frame(width: size * 0.26, height: size * 0.26)
        .shadow(color: furBottom.opacity(0.25), radius: size * 0.015, y: size * 0.01)
    }

    private var cheek: some View {
        Circle().fill(Color(red: 0.97, green: 0.55, blue: 0.50).opacity(0.28))
            .frame(width: size * 0.18, height: size * 0.14)
    }

    private var snoutGroup: some View {
        ZStack {
            // broad otter muzzle — two soft lobes
            Ellipse().fill(snout)
                .frame(width: size * 0.66, height: size * 0.46)
                .offset(y: size * 0.19)
                .shadow(color: furBottom.opacity(0.18), radius: size * 0.015, y: size * 0.01)

            // wide button nose
            Ellipse().fill(ink).frame(width: size * 0.21, height: size * 0.15).offset(y: size * 0.09)
            Ellipse().fill(Color.white.opacity(0.55))
                .frame(width: size * 0.07, height: size * 0.045)
                .offset(x: -size * 0.04, y: size * 0.065)
            if mood == .cheering || mood == .celebrating || mood == .jogging {
                Capsule().fill(Color(red: 0.96, green: 0.46, blue: 0.52))
                    .frame(width: size * 0.16, height: size * 0.20)
                    .offset(y: size * 0.32)
            }
        }
    }


    private var eyes: some View {
        HStack(spacing: size * 0.26) { eye; eye }.offset(y: -size * 0.05)
    }

    @ViewBuilder private var eye: some View {
        switch mood {
        case .resting, .recovery:
            Capsule().fill(ink).frame(width: size * 0.15, height: size * 0.035)
        case .cheering, .celebrating:
            HappyArc().stroke(ink, style: .init(lineWidth: size * 0.04, lineCap: .round))
                .frame(width: size * 0.17, height: size * 0.10)
        case .concerned:
            ZStack {
                Circle().fill(ink).frame(width: size * 0.12, height: size * 0.12)
                Circle().fill(.white).frame(width: size * 0.04, height: size * 0.04).offset(x: size * 0.02, y: -size * 0.025)
            }
        default:
            ZStack {
                Circle().fill(ink).frame(width: size * 0.15, height: size * 0.15)
                Circle().fill(.white).frame(width: size * 0.05, height: size * 0.05).offset(x: size * 0.03, y: -size * 0.035)
            }
        }
    }

}

// One-screen showcase of the chosen Puffy Buddy across all moods.
public struct PuffyBuddyGallery: View {
    public init() {}
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    public var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text("Buddy — Puffy")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundColor(Palette.ink)
                    Text("The chosen direction, across every mood")
                        .font(.system(size: 14)).foregroundColor(Palette.subtle)
                }
                .padding(.top, 16)

                PuffyBuddy(mood: .ready, size: 140)

                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(BuddyMood.allCases, id: \.self) { mood in
                        VStack(spacing: 8) {
                            PuffyBuddy(mood: mood, size: 78).frame(height: 116)
                            MoodChip(mood: mood)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.6)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
        }
    }
}

// Upward-curving "happy" arc — used for Buddy's smiling eyes.
struct HappyArc: Shape {
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
