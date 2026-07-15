import XCTest
@testable import AppCore

// XCTest (not swift-testing) so results land in the editor's --xunit-output file.
final class ThemeStoreTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "theme-test-\(UUID().uuidString)")!
    }

    // With nothing saved and no scenario seed, the app opens on the Default look.
    func testDefaultsToDefaultTheme() {
        let store = ThemeStore(defaults: freshDefaults())
        XCTAssertEqual(store.themeID, .default)
    }

    // A returning user lands on the theme they last chose (their personal default).
    func testLoadsSavedTheme() {
        let d = freshDefaults()
        d.set("orbit", forKey: "otterpaceTheme")
        XCTAssertEqual(ThemeStore(defaults: d).themeID, .orbit)
    }

    // A scenario capture pins a theme via rbTheme, which wins over the saved value
    // so each theme is capturable regardless of the developer's own preference.
    func testRbThemeSeedOverridesSaved() {
        let d = freshDefaults()
        d.set("garden", forKey: "otterpaceTheme")
        d.set("bolt", forKey: "rbTheme")
        XCTAssertEqual(ThemeStore(defaults: d).themeID, .bolt)
    }

    // Picking a theme persists it as the personal default until changed again.
    func testChangingThemePersists() {
        let d = freshDefaults()
        let store = ThemeStore(defaults: d)
        store.themeID = .fieldnote
        XCTAssertEqual(d.string(forKey: "otterpaceTheme"), "fieldnote")
        XCTAssertEqual(ThemeStore(defaults: d).themeID, .fieldnote)
    }

    // An unrecognized saved value degrades to Default rather than crashing.
    func testUnknownSavedValueFallsBackToDefault() {
        let d = freshDefaults()
        d.set("neon-disco", forKey: "otterpaceTheme")
        XCTAssertEqual(ThemeStore(defaults: d).themeID, .default)
    }

    // Every theme resolves to a token set with a matching id, and the dark themes
    // (Bolt, Orbit) declare isDark so the app can pin the matching color scheme.
    func testEveryThemeResolves() {
        for id in ThemeID.allCases {
            XCTAssertEqual(id.theme.id, id)
            XCTAssertFalse(id.displayName.isEmpty)
            XCTAssertFalse(id.blurb.isEmpty)
        }
        XCTAssertFalse(ThemeID.default.theme.isDark)
        XCTAssertFalse(ThemeID.garden.theme.isDark)
        XCTAssertTrue(ThemeID.bolt.theme.isDark)
        XCTAssertTrue(ThemeID.orbit.theme.isDark)
    }
}
