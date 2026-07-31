import SwiftUI

/// The Coach Data Preview's title bar: Buddy, the screen name, and Done.
///
/// Mirrors `SettingsView`'s header so arriving here from Settings feels like the
/// same surface rather than a different app.
struct CoachPreviewHeader: View {
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            BuddyView(mood: .ready, size: 34)
            Text("What Buddy sees")
                .font(Typography.title3)
                .foregroundColor(Palette.ink)
            Spacer()
            Button(action: onClose) {
                Text("Done").font(Typography.headline).foregroundColor(Palette.brandDeep)
            }
            .accessibilityLabel("Close data preview")
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }
}
