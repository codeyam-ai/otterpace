---
title: "Settings connect & race-import flow: tappable rows and working prefill"
mode: ui
createdAt: "2026-07-15T22:40:00Z"
source: manual
---

## Summary

Two concrete problems in Settings and its connect/import flows. First, the
action rows that drive nearly every "connect" and "add" affordance (Import from
URL, Search online, Add manually, Connect Strava / Apple Health / AI Coach, Sign
out, Delete account, etc.) are hard to tap: the shared `actionRowLabel` builder
has no `contentShape` and no vertical padding, so only the icon/text glyphs are
hit-testable — the gaps and the trailing chevron area are dead. Second, the
"Import from URL" and "Search online" flows successfully find a race but never
open the editor to save it: the handoff flips a single `.sheet(item:)` directly
from `.importURL`/`.search` to `.editor` (non-nil → non-nil in one update),
which SwiftUI does not reliably re-present, so the prefilled editor never
appears. This plan makes every settings row a comfortable full-width tap target
and fixes the sheet handoff so a found/searched race actually opens the editor
pre-filled and ready to confirm-and-save.

## Key Decisions

- **Fix tappability at the shared builder, not per call site** — enlarging
  `actionRowLabel`/`actionRow` in `SettingsView` fixes every connect/add/account
  action at once (Strava, Health, Coach, Races, Account) and keeps the change in
  one place. Match the existing `phaseRow`/`themeRow` pattern already in the file
  (`.contentShape(Rectangle())` + vertical padding) so rows read consistently and
  clear the ~44pt HIG tap-target minimum.
- **Fix the import→editor handoff by dismissing then re-presenting** — the
  root cause is a known SwiftUI limitation: mutating a presented `.sheet(item:)`
  from one non-nil identity to another non-nil identity in the same runloop tick
  does not swap the sheet. Set `activeRaceSheet = nil` first, then schedule
  `activeRaceSheet = .editor` on the next main-runloop tick so the editor
  presents cleanly with the seed. Chosen over restructuring into nested/separate
  sheets because it's the smallest change that preserves the existing single-enum
  design and all the scenario hooks (`rbShowRaceEditor`, `rbRaceEditorSeedJSON`).
- **The seed mapping is already correct and tested** — `RaceDraft.asRaceGoalSeed`
  and `RaceSearchResult.asDraft` are covered by `RaceImportPersistenceTests` and
  work; do NOT touch them. The bug is purely the presentation handoff, not the
  data. This is why `settings-import-race-review` (which seeds the editor state
  directly) looks fine while the live URL/search path is broken.
- **Also enlarge the small per-race edit/delete controls** — the pencil/trash
  buttons in `raceRow` are ~17pt glyphs with only 6pt padding (~29pt targets),
  below the comfortable minimum; give them a larger hit area so races are easy to
  edit/remove ("easy to select or unselect").

## Implementation

### 1. Make every settings action row a full, comfortable tap target

**File**: `Sources/AppCore/SettingsView.swift`

In `actionRowLabel(...)` (the shared HStack of icon + title + spacer + chevron),
add vertical padding and a rectangular hit shape so the whole row — including the
empty spacer region and the trailing chevron — is tappable, not just the glyphs.
Concretely: give the label `.padding(.vertical, 8)` (or enough to reach ≥44pt
total height) and apply `.contentShape(Rectangle())`. Since `actionRow` wraps
`actionRowLabel` in a `Button(...).buttonStyle(.plain)`, the enlarged content
shape becomes the button's hit region. Ensure the `Link`-wrapped uses
(`actionRowLabel(... external: true)` for "Get an API key" and "Privacy policy")
also benefit — they route through the same builder, so the tappable Link area
grows too. Verify the destructive rows (Delete account, Disconnect) keep their
red tint and still read correctly with the added padding.

Confirm spacing inside each `card(...)` still looks right after rows get taller
(the card uses `VStack(spacing: 12)`); reduce per-row vertical padding slightly
if rows feel too loose, but never below the ~44pt effective target.

### 2. Enlarge the per-race edit/delete controls

**File**: `Sources/AppCore/SettingsView.swift`

In `raceRow(_:)`, the edit (pencil) and delete (trash) `Button`s currently use a
bare `Image(...).padding(6)`. Increase their tap area (e.g. a fixed
`.frame(width: 44, height: 44)` with `.contentShape(Rectangle())`, keeping the
glyph centered and the existing tints/`accessibilityLabel`s) so each race is easy
to edit or delete. Keep the row layout visually balanced — adjust the row's
trailing spacing if the larger targets crowd the name/detail text.

### 3. Fix the import/search → editor handoff so the found race opens prefilled

**File**: `Sources/AppCore/SettingsView.swift`

The handoff functions `openEditorPrefilled(seed:flagged:)` and
`openEditorForAdd()` (the import/search "add manually" fallback) both set
`activeRaceSheet = .editor` while an import/search sheet is already presented.
Change these so they first dismiss the current sheet, then present the editor on
the next runloop tick, e.g.:

```swift
private func openEditorPrefilled(seed: RaceGoal, flagged: [String]) {
    editingRace = nil
    raceEditorSeed = seed
    raceEditorFlagged = flagged
    presentEditorAfterDismiss()
}

private func openEditorForAdd() {
    editingRace = nil
    raceEditorSeed = nil
    raceEditorFlagged = []
    presentEditorAfterDismiss()
}

/// Dismiss any presented race sheet, then present the editor on the next
/// runloop tick. Mutating a live `.sheet(item:)` straight from one non-nil
/// case to another does not reliably re-present in SwiftUI, so the editor
/// (and its seed) would silently never appear.
private func presentEditorAfterDismiss() {
    if activeRaceSheet == nil {
        activeRaceSheet = .editor            // opened cold (e.g. "Add manually" with no sheet up)
    } else {
        activeRaceSheet = nil
        DispatchQueue.main.async { activeRaceSheet = .editor }
    }
}
```

Notes:
- The `nil`-check preserves the direct path for the "Add manually" button on the
  Races card, which opens the editor when no sheet is showing (avoids a needless
  dismiss/re-present flicker there).
- `raceEditorSeed`/`raceEditorFlagged`/`editingRace` are plain `@State` read at
  sheet-build time, so setting them before scheduling the editor is safe — the
  `.editor` case reads the current values when it presents on the next tick.
- Leave the `raceRow` edit button's direct `activeRaceSheet = .editor` as-is: it
  fires with no sheet presented (nil → `.editor`), which presents fine.

### 4. (If verification shows a flicker) reset seed state on editor dismiss

**File**: `Sources/AppCore/SettingsView.swift`

Only if the deconstruct/verify step surfaces stale-seed carryover between
successive opens (e.g. open import → editor, cancel, then "Add manually" shows an
old seed): clear `raceEditorSeed`/`raceEditorFlagged`/`editingRace` when the
editor's `onSave`/`onCancel` set `activeRaceSheet = nil`. The current
`openEditorForAdd` already resets them on each open, so this is a belt-and-suspenders
guard, not expected to be required — implement only if observed.

## Reused existing code

- `actionRow` / `actionRowLabel` builders in `Sources/AppCore/SettingsView.swift`
  (glossary entry: `SettingsView`) — the single place all connect/add/account
  action rows are built; enlarging here fixes tappability app-wide.
- `phaseRow` / `themeRow` in `Sources/AppCore/SettingsView.swift` — existing
  in-file precedent for `.contentShape(Rectangle())` + vertical padding on a
  full-width tappable row; match their pattern.
- `RaceEditorView` from `Sources/AppCore/RaceEditorView.swift` (glossary entry:
  `RaceEditorView`) — already accepts `seed:` + `flaggedFields:` and prefills
  correctly; no change needed, it just needs to actually be presented.
- `RaceImportSheet` / `RaceSearchSheet` from
  `Sources/AppCore/RaceImportView.swift` (glossary entries: `RaceImportSheet`,
  `RaceSearchSheet`) — already call `onPrefill`/`onManual` with the right data;
  the fix is on the SettingsView side that handles those callbacks.
- `RaceDraft.asRaceGoalSeed`, `RaceSearchResult.asDraft` from
  `Sources/AppCore/RaceGoals.swift` / `Coach/RaceImportClient.swift` — verified
  correct by `Tests/AppCoreTests/RaceImportPersistenceTests.swift`; reused
  unchanged.
- The `RaceSheet` enum + `.sheet(item: $activeRaceSheet)` and scenario hooks
  (`rbShowRaceEditor`, `rbRaceEditorSeedJSON`, `rbRaceEditorFlagged`) —
  preserved; the fix works within this design.

## Scenarios to Demonstrate

- **Import-from-URL → editor opens prefilled** — with a coach key connected (or
  `rbCoachConnected`), paste a race URL, import succeeds, and the editor appears
  pre-filled with name/date/distance/location and the "Double-check …" review
  hint. This is the flow that's currently broken.
- **Search online → pick a candidate → editor opens prefilled** — search returns
  candidates; tapping one opens the editor seeded from that candidate with the
  missing fields flagged.
- **Add manually (cold)** — tapping "Add manually" on the Races card with no
  sheet up opens a blank editor immediately (no flicker), Save disabled until a
  name is typed.
- **Manual fallback from the import sheet** — inside the import sheet (e.g. no
  key, or after an error), "Add manually instead" dismisses the import sheet and
  opens the blank editor.
- **Tappable connect rows** — the Races, Strava, Apple Health, AI Coach, and
  Account action rows register a tap anywhere across the full row width
  (including the chevron/empty area), not only on the icon/label.
- **Easy edit/unselect a race** — a Races list with one or more races where the
  enlarged pencil/trash controls are comfortably tappable to edit or remove.
- **Edge: sparse import** — a URL import that only yields a name opens the editor
  with the Half distance preset selected and every unknown field flagged for
  review, Save enabled once the name is present.
