import SwiftUI

// Isolation scaffold for ThemeChoiceRow — codeyam renders this View standalone on the
// booted iOS simulator. CODEYAM_ISOLATE_COMPONENT=ThemeChoiceRow selects this struct in
// CodeyamIsolationHost.swift; CODEYAM_ISOLATE_SCENARIO picks the scenario below.
//
// ThemeChoiceRow has two cosmetic styles (Settings plain vs Onboarding carded) and a
// selected state. Each scenario lists all five themes in one style with one selected,
// so the swatch/mark range, the blurbs, and the selection check all read at once.
struct ThemeChoiceRowIsolated: View {
    let scenario: String

    private func list(_ style: ThemeChoiceRow.Style, selected: ThemeID) -> some View {
        VStack(spacing: style == .settings ? 6 : 10) {
            ForEach(ThemeID.allCases) { id in
                ThemeChoiceRow(id: id, selected: id == selected, style: style) {}
            }
        }
    }

    var body: some View {
        Group {
            switch scenario {
            case "Onboarding List":
                list(.onboarding, selected: .garden)
            default:
                list(.settings, selected: .bolt)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.bgTop)
    }
}
