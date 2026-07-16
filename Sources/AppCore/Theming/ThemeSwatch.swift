import SwiftUI

// MARK: - Theme choice building blocks
//
// The Settings "Appearance" list and the onboarding "Choose your look" step both
// render the same thing: a row of selectable theme options, each previewing its
// own colors + brand mark. These two components are that shared shape, so the two
// surfaces compose instead of duplicating the swatch/row markup.

/// A small rounded preview tile for one theme: the theme's `bgTop` fill, a hairline
/// `subtle` border, and the theme's identity mark (PuffyBuddy for Default, the
/// `ThemeMark` otherwise). Used at 46pt in Settings and 56pt in onboarding.
public struct ThemeSwatch: View {
    public let id: ThemeID
    public let tileSize: CGFloat
    public let corner: CGFloat
    public let markSize: CGFloat
    public let puffySize: CGFloat

    public init(id: ThemeID, tileSize: CGFloat, corner: CGFloat, markSize: CGFloat, puffySize: CGFloat) {
        self.id = id
        self.tileSize = tileSize
        self.corner = corner
        self.markSize = markSize
        self.puffySize = puffySize
    }

    public var body: some View {
        let t = id.theme
        ZStack {
            RoundedRectangle(cornerRadius: corner).fill(t.bgTop)
            RoundedRectangle(cornerRadius: corner).strokeBorder(t.subtle.opacity(0.25), lineWidth: 1)
            if id == .default {
                PuffyBuddy(mood: .ready, size: puffySize, showHalo: false)
            } else {
                ThemeMark(theme: t, size: markSize)
            }
        }
        .frame(width: tileSize, height: tileSize)
    }
}

/// A full selectable theme row: swatch + name + one-line blurb + selection check.
/// The two host surfaces differ only cosmetically, captured by `Style`; selecting
/// invokes `onSelect` (the caller sets the theme and fires its own analytics).
public struct ThemeChoiceRow: View {
    public enum Style {
        case settings
        case onboarding
    }

    public let id: ThemeID
    public let selected: Bool
    public let style: Style
    public let onSelect: () -> Void

    public init(id: ThemeID, selected: Bool, style: Style, onSelect: @escaping () -> Void) {
        self.id = id
        self.selected = selected
        self.style = style
        self.onSelect = onSelect
    }

    public var body: some View {
        Button(action: onSelect) { label }
            .buttonStyle(.plain)
            .accessibilityLabel("\(id.displayName) theme. \(id.blurb)")
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder private var label: some View {
        switch style {
        case .settings:
            HStack(spacing: 12) {
                ThemeSwatch(id: id, tileSize: 46, corner: 10, markSize: 26, puffySize: 28)
                textBlock(name: Typography.body)
                Spacer()
                checkmark(unselectedOpacity: 0.4)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        case .onboarding:
            HStack(spacing: 14) {
                ThemeSwatch(id: id, tileSize: 56, corner: 12, markSize: 30, puffySize: 34)
                textBlock(name: Typography.headline)
                Spacer()
                checkmark(unselectedOpacity: 0.45)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(selected ? Palette.brand : Color.clear, lineWidth: 2))
        }
    }

    private func textBlock(name: Font) -> some View {
        VStack(alignment: .leading, spacing: style == .settings ? 2 : 3) {
            Text(id.displayName).font(name).foregroundColor(Palette.ink)
            Text(id.blurb).font(Typography.caption).foregroundColor(Palette.subtle)
        }
    }

    private func checkmark(unselectedOpacity: Double) -> some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .foregroundColor(selected ? Palette.brand : Palette.subtle.opacity(unselectedOpacity))
    }
}
