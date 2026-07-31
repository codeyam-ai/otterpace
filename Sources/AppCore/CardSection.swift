import SwiftUI

/// A titled card: an uppercase caption over arbitrary content, on the shared
/// `cardStyle()` surface. The container every Settings-style card is built from.
///
/// This began as a private `card(_:content:)` helper inside `SettingsView`, then
/// got copied into `CoachDataPreview` when that screen needed the same surface.
/// Two private copies of the same container is exactly how two screens start
/// drifting apart visually, so it lives here instead.
///
/// `SettingsView` still has its own private copy: migrating it would touch every
/// card on that screen and re-render all twelve of its committed scenario
/// screenshots, which is a large unrelated diff. That migration is tracked
/// separately rather than smuggled into an unrelated feature.
struct CardSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(Typography.caption2).foregroundColor(Palette.subtle)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardStyle()
    }
}
