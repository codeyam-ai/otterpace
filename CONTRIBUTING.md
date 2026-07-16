# Contributing to Otterpace

Thanks for your interest in Otterpace — an open-source, AI running coach for iOS,
built in the open. Contributions of all sizes are welcome.

## Getting started

You'll need **Xcode** with an iOS simulator runtime installed (the project
targets iOS 17).

```bash
# Build the shared library + run the tests
swift build
swift test --parallel --disable-swift-testing --xunit-output .codeyam/swift-tests.xml

# Open the app in Xcode to run it on a simulator/device
open App.xcodeproj
```

- `App/` — the iOS app entry point (`@main`) and `Info.plist`.
- `Sources/AppCore/` — the SwiftUI views + model, as a shared SwiftPM library
  (one file per component).
- `Tests/AppCoreTests/` — XCTest coverage of the model, formatters, and engines.
- `Scripts/GenerateAppIcon` — regenerates the app icon from `AppIconArtwork`
  (`swift run GenerateAppIcon`).
- `.codeyam/` — CodeYam scenarios, screenshots, glossary, and journal. Otterpace
  is built as a CodeYam showcase; scenarios seed the app's state at launch so
  each UI state is reviewable. (Runtime/machine state under `.codeyam/` is
  git-ignored — only the curated showcase content is tracked.)

## Code style

- **SwiftUI, one component per file.** Pages/screens compose components; keep
  views small and focused.
- **Design tokens, not magic numbers.** Use `Palette` for color and `Typography`
  for fonts (`Sources/AppCore/Theme.swift`) so contrast and Dynamic Type stay
  consistent and accessible.
- **Pure, testable logic.** Keep deterministic logic (engines, formatters,
  grouping) free of SwiftUI so it can be unit-tested — see `CoachEngine`,
  `WeeklyReviewEngine`, `ActivityHistory`.
- **Coaching is conservative and never shame-based.** Any coaching copy must stay
  cautious: no diagnoses, encourage clinical care for real pain, and prefer
  rest/easy effort when the data suggests fatigue.

## Tests

Write tests with **XCTest** (not swift-testing — see the README "Testing"
section for why). Put a `//` comment directly above each `func testX()`
describing what it verifies. Every behavior change should come with a test.

## Pull requests

1. Fork and branch from `main`.
2. Keep PRs focused; include tests for logic changes.
3. Make sure `swift build` and the test command above pass.
4. Describe the user-facing change and, where relevant, the scenario(s) it affects.

## Good first issues

Friendly places to start:

- Add a new Buddy mood or refine an existing one (`PuffyBuddy`).
- Improve an empty state (Activity History, Ask Coach, Weekly Review).
- Add a coaching scenario or a new `CoachEngine` intent + tests.
- Add accessibility labels or improve Dynamic Type handling on a component.
- Add mock activity fixtures / a new seeded scenario.
- Improve README screenshots or docs.

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By
participating, you agree to uphold it.
