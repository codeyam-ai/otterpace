import SwiftUI

// MARK: - Puffy Buddy loader
//
// A bouncy loading state that suits the puffy mascot: a squash-and-stretch hop
// over a soft, scaling shadow, with a caption and pulsing dots. Animates via a
// single `repeatForever` driver started in `onAppear`.

public struct PuffyBuddyLoader: View {
    public var size: CGFloat
    public var caption: String
    public var showCaption: Bool

    public init(size: CGFloat = 120, caption: String = "Fetching your day…", showCaption: Bool = true) {
        self.size = size
        self.caption = caption
        self.showCaption = showCaption
    }

    @State private var hop = false

    public var body: some View {
        VStack(spacing: size * 0.26) {
            ZStack {
                Ellipse().fill(Color.black.opacity(0.14))
                    .frame(width: size * (hop ? 0.5 : 0.74), height: size * 0.12)
                    .offset(y: size * 0.6)
                    .blur(radius: 2)
                PuffyBuddy(mood: .jogging, size: size)
                    .scaleEffect(x: hop ? 0.95 : 1.05, y: hop ? 1.06 : 0.92, anchor: .bottom)
                    .offset(y: hop ? -size * 0.14 : size * 0.02)
            }
            .frame(width: size * 1.5, height: size * 1.6)
            if showCaption {
                VStack(spacing: 6) {
                    Text(caption)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(Palette.ink.opacity(0.85))
                    BouncingDots(color: Palette.brand, dot: 6)
                }
            } else {
                BouncingDots(color: Palette.brand, dot: 5)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { hop = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

// Three dots that pulse in sequence — a shared loading affordance.
struct BouncingDots: View {
    let color: Color
    var dot: CGFloat
    @State private var on = false

    var body: some View {
        HStack(spacing: dot * 0.7) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: dot, height: dot)
                    .scaleEffect(on ? 1.0 : 0.5)
                    .opacity(on ? 1.0 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: on
                    )
            }
        }
        .onAppear { on = true }
    }
}
