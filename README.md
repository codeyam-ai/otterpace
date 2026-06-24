# RunBuddy 🐾

An open-source, AI running coach for iOS — built in the open as a CodeYam showcase.

RunBuddy is a friendly running coach in your pocket: it pulls your activity from
Apple HealthKit (and, soon, Strava), keeps you moving toward your daily 10,000
steps, and gives injury-aware, never-shame-based coaching through **Buddy**, a
mood-reactive otter mascot.

## What's here today

The **Today dashboard**, a native SwiftUI screen that shows:

- A **step-goal ring** toward your daily 10K, plus active minutes, distance, and
  time since you last moved
- **Buddy**, whose mood (resting → ready → jogging → cheering → concerned →
  celebrating → recovery) reflects how the day is going
- An **AI coach card** with one clear, practical recommendation — conservative and
  injury-aware, flipping to an amber caution when your training load spikes
- Your **latest run/walk** and a **weekly training-load** snapshot
- A friendly **day-one "Connect Apple Health"** hero for first launch

The **Ask Coach** chat (this milestone), reached from a Today/Coach tab bar or the
"Ask Buddy" button on the coach card:

- Ask Buddy a fitness question and get a practical, **injury-aware** reply —
  "Can I run or should I rest?", "How do I hit 10K without overdoing it?",
  "Am I increasing mileage too fast?", or "my knee hurts after my run"
- Replies are **classified by intent** and built from your own activity context,
  so they feel personal — a recent hard run or spiking load steers Buddy toward
  recovery, and pain questions return a non-diagnostic, see-a-clinician answer
  behind an amber **"safety first"** shield
- This is **mock-coach mode** (Milestone 2): answers are curated and
  deterministic, served by `CoachEngine` (`Sources/AppCore/CoachEngine.swift`).
  A real model swaps in at Milestone 3

The Today screen is driven by a single `TodayState` (see `Sources/AppCore/Model.swift`),
populated from HealthKit in the real app and from each CodeYam scenario's
`deviceState` preferences in the simulator preview. Production starts empty; each
scenario carries its own seeded state.

## Architecture

- `App/` — the iOS app entry point (`@main`) and `Info.plist`
- `Sources/AppCore/` — the SwiftUI views and model, as a shared SwiftPM library:
  `RunBuddyModel` + `TodayState` (data + derived logic), `PuffyBuddy` (the otter
  mascot) + `PuffyBuddyLoader` (its loading state), one file per dashboard
  component (`StepRing`, `CoachCard`, `WeeklyLoadCard`, …), and the Ask Coach
  surface (`AskCoachView` + `CoachEngine` and its `ChatBubble` / `ChatThread` /
  `AskCoachInputBar` parts)
- `Tests/AppCoreTests/` — XCTest coverage of the model, pure formatters, and the
  coach engine's intent classification and safety branches

## Running

Requires Xcode with an iOS simulator runtime installed.

    # Boot the simulator, build, and launch the app
    codeyam-editor editor start-simulator swift-ios-swiftui

    # Capture the Today dashboard in a given scenario state
    codeyam-editor editor preview '{"dimension":"iPhone 16","path":"/","scenarioSlug":"today-goal-crushed"}'

Scenarios live in `.codeyam/scenarios/` and seed the dashboard's state at launch —
e.g. `today-day-one-connect`, `today-fresh-start`, `today-midday-nudge`,
`today-almost-there`, `today-recovery-caution`, `today-goal-crushed`.

## App icon

The app icon is generated from code, not a hand-painted PNG, so it stays
consistent with the in-app mascot. The artwork is the `AppIconArtwork` SwiftUI
view (`Sources/AppCore/AppIconArtwork.swift`) — Buddy the otter on the opaque
coral brand gradient. Regenerate the 1024×1024 marketing PNG whenever the art
changes:

    swift run GenerateAppIcon

This rasterizes `AppIconArtwork` to
`App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`. App Store constraints
the output satisfies: exactly **1024×1024**, sRGB, **opaque (no alpha)**, and no
rounded corners (iOS applies the superellipse mask). Xcode generates every
home-screen / Spotlight / Settings size from that single source at build time.

## Testing

Write tests with **XCTest** (`import XCTest`, `final class …: XCTestCase`,
`func testName()`). XCTest is the framework the editor's runner captures: the
editor parses the XCTest `--xunit-output` file, and **swift-testing** (`import
Testing`, `@Test func`) results do **not** reliably land there on Xcode 16.x /
Swift 6.x — under `--parallel`, the swift-testing run can overwrite the xunit
with `tests="0"`, so the editor sees no tests. Put your tests in
`Tests/AppCoreTests/` with a `//` comment directly above each `func testX()`
describing what it verifies (the editor parses that comment as the test's
description).

Tests run via:

    swift test --parallel --disable-swift-testing --xunit-output .codeyam/swift-tests.xml

- `--parallel` is required: modern SwiftPM only writes the XCTest xunit to
  `--xunit-output` when run in parallel, so without it the project reports
  zero tests.
- `--disable-swift-testing` makes the xunit deterministic: it stops the
  swift-testing harness from also claiming `--xunit-output` and racing the
  XCTest writer, which otherwise nondeterministically truncates the file to
  `tests="0"`.

To register your tests with the editor after writing them, run:

    codeyam-editor editor reconcile-registry --auto-apply

This diffs the runner output against the registry and auto-adds new tests —
line numbers and descriptions are resolved automatically, so you do not need
to pass `--line` by hand.
