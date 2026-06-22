import SwiftUI

// Shared card chrome used by the dashboard's section components.
extension View {
    func cardStyle() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Palette.ink.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: Palette.ink.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}
