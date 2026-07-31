import SwiftUI

/// The honest counterpart to everything above: what never leaves the device.
///
/// Every claim here is one the code actually keeps, verified rather than
/// asserted — the key travels as the `x-ai-key` request header (`CoachHeaders`)
/// and never inside the JSON body; `api/coach.ts` and `api/_lib/llm.ts` contain
/// no logging and no persistence, so it is not stored server-side; and the body
/// (`RemoteCoach.RequestBody`) carries only question, context, and history, with
/// no identity fields at all.
///
/// If any of those change, this copy is wrong and must change with them. That is
/// why the claims are enumerated here instead of being a vague reassurance.
struct CoachPreviewNeverSentCard: View {
    var body: some View {
        CardSection(title: "Never sent") {
            VStack(alignment: .leading, spacing: 8) {
                bullet("Your API key is sent as a request header so the provider can bill you — never inside this summary, and never saved by Otterpace.")
                bullet("Your name, email, and Apple ID.")
                bullet("Your raw Apple Health records. Only the totals above are summarised.")
                bullet("Your location, routes, and any map data.")
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").font(Typography.callout).foregroundColor(Palette.subtle)
            Text(text).font(Typography.callout).foregroundColor(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
