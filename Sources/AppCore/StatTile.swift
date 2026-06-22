import SwiftUI

// A single labeled metric tile used in the dashboard's stats row.
struct StatTile: View {
    let icon: String
    let tint: Color
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(tint)
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(Palette.ink)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Palette.subtle)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .cardStyle()
    }
}
