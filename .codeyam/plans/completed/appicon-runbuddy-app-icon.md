---
title: "appicon: RunBuddy App Icon"
mode: ui
createdAt: "2026-06-23T17:17:20Z"
source: manual
prefix: "appicon"
---

## Summary

RunBuddy currently ships **no app icon**. The Xcode target already declares
`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` (`App.xcodeproj/project.pbxproj`),
but there is no asset catalog anywhere in the repo and no Resources build phase
that would compile one — so device/simulator builds show a blank icon, and any
TestFlight / App Store Connect upload would be **rejected** for a missing
1024×1024 marketing icon. This plan creates an on-brand app icon featuring
**Buddy the otter** on the coral brand background, packages it as a single-size
(1024×1024) `AppIcon` asset, and wires the asset catalog into the Xcode project
so the same icon serves the installed app, the simulator, and TestFlight builds.

## Key Decisions

- **One 1024×1024 icon, single-size asset format** — Xcode 14+/iOS 17 (this
  project targets `IPHONEOS_DEPLOYMENT_TARGET = 17.0`) generates every home
  screen / Spotlight / Settings size from a single 1024 "universal iOS" entry in
  the `.appiconset`. No need to hand-author the legacy 20/29/40/60/76pt matrix.
- **The same asset-catalog icon covers TestFlight** — there is no separate
  "TestFlight icon." App Store Connect / TestFlight reads the 1024 marketing
  icon embedded in the compiled asset catalog. The only hard requirements are:
  exactly 1024×1024 px, sRGB, **opaque (no alpha channel)**, no rounded corners
  (iOS applies the superellipse mask). The artwork is built to satisfy these.
- **Reuse the existing mascot, don't redraw it** — Buddy is already a pure
  SwiftUI vector view (`PuffyBuddy` in `Sources/AppCore/PuffyBuddy.swift`). The
  icon is composed from that view over a full-bleed coral background and exported
  with SwiftUI's `ImageRenderer`, so the icon stays pixel-consistent with the
  in-app mascot and is regenerable if the art changes (instead of a hand-painted
  PNG that drifts out of sync).
- **Icon artwork lives in `AppCore` as a real view** — placing the composition
  in a reusable `AppIconArtwork` view (rather than a throwaway script) lets us
  preview it as a CodeYam scenario and keeps the source of truth in code.
- **Wire the catalog explicitly into `project.pbxproj`** — the build setting
  already names `AppIcon`, but nothing compiles a catalog today. We add the file
  reference, a build file, and a `PBXResourcesBuildPhase` on the App target.

## Implementation

### 1. Icon artwork view (composes Buddy on the brand background)

**New file**: `Sources/AppCore/AppIconArtwork.swift`

A `public struct AppIconArtwork: View` that renders the full-bleed icon square:

- An **opaque** background filling the entire square — a coral radial/linear
  gradient built from `Palette.brand` (`#FF7357`) into `Palette.brandDeep`. No
  transparency anywhere; the square must be fully painted edge to edge.
- **Buddy** centered and scaled to fill comfortably (roughly 62–70% of the
  square), reusing `PuffyBuddy(mood:size:)`. Use a confident, friendly mood —
  default to `.ready` (alert, content) or `.celebrating`; the exact mood is a
  tactical choice during implementation and is easy to compare via the scenarios
  below.
- Render Buddy **without** its translucent `mood.accent` halo ring so it reads
  cleanly against the coral; if `PuffyBuddy` can't suppress the halo via its
  current API, compose only the head/face by overlaying on the solid background
  (a small refactor to expose a "no backdrop" option on `PuffyBuddy` is
  acceptable and preferable to duplicating the drawing).
- A subtle soft drop shadow / inner sheen is fine, but keep the silhouette clear
  at small sizes (test at ~60px). No text in the icon.

The view should be authored at a nominal canvas (e.g. 512pt) and be resolution
independent so `ImageRenderer` can scale it to 1024.

### 2. Generate the 1024×1024 PNG from the view

**New file**: `Scripts/generate-app-icon.swift` (or an equivalent SwiftPM
executable target — implementer's choice)

A small `@MainActor` entry point that uses `ImageRenderer` to rasterize
`AppIconArtwork` and write `App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`:

- Set `renderer.scale` so the output is exactly **1024×1024** px.
- Write a **PNG with no alpha** (flatten onto the opaque coral background).
  Verify the emitted file has no alpha channel — App Store validation fails
  otherwise.
- Make the script idempotent/re-runnable so the icon can be regenerated whenever
  the mascot art changes.

Document the regeneration command in `README.md` (see step 6).

**New file (binary)**: `App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
— the generated 1024×1024 opaque PNG committed into the asset set.

### 3. Asset catalog + appiconset metadata

**New file**: `App/Assets.xcassets/Contents.json`

Standard empty catalog metadata:

```json
{ "info": { "author": "xcode", "version": 1 } }
```

**New file**: `App/Assets.xcassets/AppIcon.appiconset/Contents.json`

Single-size iOS app icon pointing at the generated PNG:

```json
{
  "images": [
    { "filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

### 4. Wire the asset catalog into the Xcode project

**File**: `App.xcodeproj/project.pbxproj`

The target builds Sources and Frameworks phases only — there is no resources
phase, so the catalog would never compile even once it exists. Add:

- A `PBXFileReference` for `App/Assets.xcassets`
  (`lastKnownFileType = folder.assetcatalog`, `path = Assets.xcassets`,
  `sourceTree = "<group>"`), placed in the **App** group
  (`666666666666666666666666`) alongside `App.swift` / `Info.plist`.
- A `PBXBuildFile` referencing that file.
- A new `PBXResourcesBuildPhase` containing the build file.
- That resources phase added to the App native target's `buildPhases`
  (target `888888888888888888888888`), after Sources/Frameworks.

`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` is already set in the Debug
config, so no build-setting change is needed. Confirm the project still opens
and builds after editing the pbxproj (it uses placeholder hex IDs like
`AAAA…`/`6666…`; add new objects with similarly unique IDs).

### 5. Verify Info.plist needs nothing extra

**File**: `App/Info.plist` (verify only — likely no change)

With the modern asset-catalog flow, Xcode injects `CFBundleIcons` /
`CFBundleIconName` at build time from `ASSETCATALOG_COMPILER_APPICON_NAME`. Do
**not** hand-add icon keys to `Info.plist`. Confirm after a build that the icon
appears on the simulator home screen and that the built `App.app` contains the
catalog-compiled icon.

### 6. Document regeneration

**File**: `README.md`

Add a short "App icon" note under Running/Architecture: where the artwork lives
(`AppIconArtwork`), the regeneration command from step 2, and the App Store
constraints (1024×1024, sRGB, opaque, no rounded corners).

## Reused existing code

- `PuffyBuddy` from `Sources/AppCore/PuffyBuddy.swift` — the otter mascot view,
  composed into the icon (the visual centerpiece).
- `Palette.brand` / `Palette.brandDeep` from `Sources/AppCore/Theme.swift` — the
  coral brand colors for the opaque icon background, keeping the icon consistent
  with the app's `Palette`-driven UI.
- `BuddyMood` (from `Sources/AppCore/Model.swift` / mascot files) — selects
  Buddy's expression for the icon.
- Existing pbxproj structure in `App.xcodeproj/project.pbxproj` — the App group
  and native target the new file reference / resources phase attach to.

## Scenarios to Demonstrate

- **App icon — full square**: `AppIconArtwork` rendered as the raw 1024 square
  (opaque coral + Buddy), the artwork as TestFlight/App Store sees it.
- **App icon — on the home screen**: the same artwork clipped to iOS's rounded
  superellipse mask, showing how it reads as an installed app icon.
- **Mood comparison**: the icon artwork across 2–3 candidate Buddy moods
  (e.g. `.ready`, `.celebrating`, `.cheering`) to pick the most recognizable
  expression.
- **Small-size legibility**: the icon rendered at ~60px to confirm Buddy's
  silhouette stays clear when shrunk to home screen / Settings sizes.
