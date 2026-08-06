import SwiftUI

// Says out loud what the app does when it can't see your activity.
//
// The suppression rule behind the movement nudges is invisible by design: a
// nudge that doesn't fire looks exactly like a feature that's broken. Naming it
// turns "why did it go quiet?" into a deliberate promise — Buddy would rather
// say nothing than guess wrong about you.
//
// Deliberately props-driven (a single `isStale`) rather than reading the model,
// so both states can be rendered side by side in isolation. The staleness
// decision itself belongs to `ActivityFreshness`, which the schedulers also
// consult — so what this row claims and what the nudges actually do cannot
// drift apart.
struct MovementFreshnessNote: View {
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: isStale ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(isStale ? Palette.amber : Palette.go)
                Text(isStale ? "Activity data is out of date" : "Activity data is up to date")
                    .font(Typography.captionStrong)
                    .foregroundColor(Palette.ink)
            }
            Text(isStale
                 ? "Buddy won't nudge you while it can't tell what you've been up to — better quiet than wrong."
                 : "Buddy only nudges from activity it can actually see, never from a guess.")
                .font(Typography.caption)
                .foregroundColor(Palette.subtle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
