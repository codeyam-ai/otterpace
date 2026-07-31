import SwiftUI

/// Where the data goes — the first card on the Coach Data Preview.
///
/// It leads because the answer reframes everything below it: with no provider
/// connected the summary is not sent anywhere at all, and a reader who learns
/// that first reads the rest as "what *would* be shared" rather than "what is
/// being taken from me right now".
struct CoachPreviewDestinationCard: View {
    /// The provider Buddy would use, or nil when no key is connected.
    let activeProvider: CoachProvider?

    var body: some View {
        CardSection(title: "Where this goes") {
            if let provider = activeProvider {
                Text("When you ask Buddy a question, the summary below is sent to \(provider.displayName) using your own API key, over HTTPS. Otterpace does not store it.")
                    .font(Typography.callout).foregroundColor(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No AI provider is connected, so none of this is being sent anywhere. Buddy is coaching you with built-in guidance that runs entirely on this device. Connect a key and the summary below is what would be shared.")
                    .font(Typography.callout).foregroundColor(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
