import SwiftUI

/// One labelled fact in the Coach Data Preview: what the field is, and what would
/// be sent for it.
///
/// `value == nil` renders "Not shared" in the subdued ink rather than hiding the
/// row. That is the whole point of the row: on a screen whose job is to show what
/// leaves the device, a field that silently disappears when empty teaches the
/// reader nothing — they cannot tell "we don't send this" from "we forgot to
/// list it". So absence is rendered, not omitted.
///
/// Purely props-driven — no store, no UserDefaults — so both states capture in
/// isolation.
struct CoachDataRow: View {
    let label: String
    let value: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(Typography.callout)
                .foregroundColor(Palette.ink)
            Spacer(minLength: 12)
            Text(value ?? "Not shared")
                .font(Typography.callout)
                .foregroundColor(value == nil ? Palette.subtle : Palette.ink)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 32)
    }
}
