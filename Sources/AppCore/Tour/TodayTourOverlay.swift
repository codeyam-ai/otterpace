import SwiftUI

// MARK: - Today spotlight tour
//
// A scrim plus a themed callout card naming the highlighted element, with a
// step-dot indicator, a primary "Next" / "Got it", and a secondary "Skip tour".
//
// Positioning uses `anchorPreference` / `overlayPreferenceValue`, which are
// available on the macOS 12 test build. When no anchor resolves (a launch-seeded
// capture can render the overlay before the anchored section has reported its
// bounds) the callout falls back to a centered card, so a seeded capture is never
// blank.

/// Collects the bounds of each tour-anchored section, keyed by `TourStep.anchorID`.
struct TourAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Tag a Today section as the target of a tour step.
    func tourAnchor(_ step: TourStep) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { [step.anchorID: $0] }
    }
}

struct TodayTourOverlay: View {
    let step: TourStep
    let index: Int
    /// Resolved bounds of the highlighted section, when the anchor has reported.
    var highlight: CGRect? = nil
    var onNext: () -> Void
    var onSkip: () -> Void

    private var isLast: Bool { index == TourStep.allCases.count - 1 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    // Tapping the scrim advances, matching the callout's primary
                    // action, so a stray tap never feels like a dead end.
                    .onTapGesture(perform: onNext)
                    .accessibilityHidden(true)

                if let highlight {
                    RoundedRectangle(cornerRadius: Layout.cardCorner, style: .continuous)
                        .stroke(Palette.onAccent.opacity(0.9), lineWidth: 2)
                        .background(
                            RoundedRectangle(cornerRadius: Layout.cardCorner, style: .continuous)
                                .fill(Palette.onAccent.opacity(0.12))
                        )
                        .frame(width: highlight.width + 8, height: highlight.height + 8)
                        .position(x: highlight.midX, y: highlight.midY)
                        .allowsHitTesting(false)
                }

                callout
                    .frame(maxWidth: 380)
                    .position(calloutCenter(in: geo.size))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Today tour, step \(index + 1) of \(TourStep.allCases.count)")
    }

    // MARK: Callout

    private var callout: some View {
        VStack(alignment: .leading, spacing: Layout.sm) {
            Text(step.title)
                .font(Typography.title3)
                .foregroundColor(Palette.ink)
            Text(step.body)
                .font(Typography.body)
                .foregroundColor(Palette.subtle)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                ForEach(0..<TourStep.allCases.count, id: \.self) { i in
                    Circle()
                        .fill(i == index ? Palette.brand : Palette.subtle.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, 2)
            .accessibilityHidden(true)

            HStack {
                if !isLast {
                    Button(action: onSkip) {
                        Text("Skip tour")
                            .font(Typography.caption)
                            .foregroundColor(Palette.subtle)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skip the tour")
                }
                Spacer()
                Button(action: onNext) {
                    Text(step.advanceTitle)
                        .font(Typography.headline)
                        .foregroundColor(Palette.onAccent)
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(
                            Capsule().fill(
                                LinearGradient(colors: [Palette.brand, Palette.brandDeep],
                                               startPoint: .leading, endPoint: .trailing)
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isLast ? "Finish the tour" : "Next tour step")
            }
            .padding(.top, 2)
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCorner, style: .continuous)
                .fill(Palette.card)
        )
        .padding(.horizontal, Layout.screenGutter)
    }

    /// Place the callout under the highlighted section when there's room, above it
    /// otherwise, and dead center when no anchor has resolved.
    private func calloutCenter(in size: CGSize) -> CGPoint {
        guard let highlight else {
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }
        let estimatedHeight: CGFloat = 220
        let below = highlight.maxY + estimatedHeight / 2 + Layout.md
        let above = highlight.minY - estimatedHeight / 2 - Layout.md
        let y = below < size.height - Layout.md
            ? below
            : max(estimatedHeight / 2 + Layout.md, above)
        return CGPoint(x: size.width / 2, y: y)
    }
}
