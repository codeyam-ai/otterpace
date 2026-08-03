import SwiftUI

// A Today callout, in Buddy's voice, inviting the user to add a race.
//
// The old version led with a bare ✕ that killed the banner permanently on the
// first tap, and body copy that never said what adding a race would DO. Both are
// fixed here: the copy names the actual outcome, and dismissal is an explicit
// "Not now" text button (a considered tap, not a reflex) wired to a snooze. The
// ✕-equivalent survives as an accessibility action, so the one-gesture dismissal
// screen-reader users expect is still available.
struct RacePromptBanner: View {
    var onTap: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.sm) {
            HStack(spacing: 12) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Palette.onAccent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Got a race coming up?")
                        .font(Typography.headline)
                        .foregroundColor(Palette.onAccent)
                    Text("Add your race and I will shape your weeks around it: long runs, taper, and race week.")
                        .font(Typography.caption)
                        .foregroundColor(Palette.onAccent.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: Layout.sm) {
                Button(action: onDismiss) {
                    Text("Not now")
                        .font(Typography.caption)
                        .foregroundColor(Palette.onAccent.opacity(0.92))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Not now")
                .accessibilityHint("Hides this for a couple of weeks")

                Spacer(minLength: 0)

                Button(action: onTap) {
                    Text("Add a race")
                        .font(Typography.headline)
                        .foregroundColor(Palette.brandDeep)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Capsule().fill(Palette.onAccent))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a race")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Palette.brand, Palette.brandDeep],
                           startPoint: .leading, endPoint: .trailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityAction(named: Text("Dismiss race prompt"), onDismiss)
    }
}
