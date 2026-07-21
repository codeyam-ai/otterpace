---
title: "Progress Heatmap — On-Brand Activity Calendar"
mode: ui
createdAt: "2026-07-16T01:43:30Z"
source: manual
---

## Summary

Add a GitHub-contributions-style activity heatmap to the top of the **Activity
History** screen, restyled to be aesthetic and on-brand: a grid of day cells
(Monday-start weeks, matching the rest of the app) where each day's color
intensity reflects how active that day was, plus a **range selector** (Week /
Month / 3-Month) and a **metric filter** (Distance / Active minutes / Steps vs.
goal). The metric filter defaults to a single metric so the view never feels
overwhelming; the other two are one tap away. The heatmap reads the theme tokens
so it retints with the five app looks, and shows a friendly Buddy-fronted empty
state on day one. All the binning logic is pure and testable, mirroring the
existing `ActivityHistory` module.

## Key Decisions

- **Lives at the top of Activity History, not a new screen** — the Activity
  History overlay (`ActivityHistoryView`) already owns the workout data
  (`model.today.workouts`) and per-week rollups; adding the heatmap as a section
  above the existing per-week list reuses that entry point and data with the
  smallest new navigation surface. It scrolls with the weeks below it.
- **Three metrics behind a filter, default Distance** — the segmented metric
  filter offers **Distance (miles)**, **Active minutes**, and **Steps vs. goal**.
  Default to **Distance** because it derives directly from existing
  `LatestWorkout.distanceMiles` with no new data plumbing and is always present.
  Active minutes derives from `LatestWorkout.durationMinutes`. **Steps vs. goal**
  needs a per-day steps series that does not exist in the model yet (see next
  decision), so it renders as "no step data yet" until that series is seeded —
  never a broken/empty grid.
- **New per-day steps series, additively** — add an optional `dailySteps`
  ([date → steps]) series to `TodayState`, seeded from a new scenario key
  (e.g. `rbDailySteps`) the same launch-seed way `workouts`/`loadHistory` are
  seeded today. It's optional and defaults empty, so nothing regresses when a
  scenario doesn't provide it. The Steps-vs-goal metric bins each day's steps
  against `today.goalSteps`.
- **Pure, testable binning in the `ActivityHistory` style** — all grid math
  (bucketing workouts/steps into per-day intensity, mapping to 0–4 levels,
  laying out the Monday-start week columns over the selected range) goes in a new
  pure function set, XCTest-covered, so the view stays a thin renderer. Reuse the
  existing Monday-start POSIX-calendar convention and unparseable-date dropping
  from `ActivityHistory.groupByWeek`.
- **On-brand, theme-reactive color ramp** — intensity levels 0–4 map to a ramp
  built from the theme's `brand`/`go` tokens via `Palette` (empty = a subtle
  card tint, hottest = full brand), so the heatmap retints across Default / Bolt
  / Orbit / Fieldnote / Garden. Rounded cells, soft spacing from `Layout`,
  `Typography` labels — never a clinical grid. WCAG AA contrast preserved.
- **Range = visible span, not aggregation** — Week / Month / 3-Month change how
  much history the grid shows (default Month), keeping day-granularity cells like
  GitHub. This satisfies the "over a day / week / month" ask without a second
  aggregation mode that would complicate the read.

## Implementation

### 1. Per-day intensity + grid logic (pure)

**New file**: `Sources/AppCore/ActivityHeatmap.swift`

A pure module (no SwiftUI) alongside `ActivityHistory.swift`:

- `enum HeatmapMetric { case distance, activeMinutes, stepsGoal }` — the three
  filterable metrics, each with a display label.
- `enum HeatmapRange { case week, month, threeMonth }` — the visible span, each
  knowing how many trailing days/weeks to render (default `.month`).
- `struct HeatmapDay { let dateISO: String; let value: Double; let level: Int }`
  — one cell; `level` is 0–4.
- `func heatmap(workouts: [LatestWorkout], dailySteps: [String: Int], goalSteps:
  Int, metric: HeatmapMetric, range: HeatmapRange, todayISO: String) ->
  [[HeatmapDay]]` — returns Monday-start week columns of day cells over the
  range. Sums that day's workout miles / minutes for distance & active-minutes;
  reads `dailySteps` for steps-vs-goal; bins each day's value into levels 0–4
  with per-metric thresholds (relative to the window's max, or goal for steps).
  Drops unparseable dates and reuses the Monday-start POSIX calendar convention
  from `ActivityHistory`.

Factor out the shared Monday-start / date-parsing helpers from
`ActivityHistory.swift` if they aren't already reusable, rather than duplicating.

### 2. Add an optional per-day steps series to the model

**File**: `Sources/AppCore/Model.swift`

- Add `public var dailySteps: [String: Int]` to `TodayState` (default `[:]`),
  with `Codable` `decodeIfPresent` fallback like the other optional fields.
- In the scenario-seeding path (where `workouts` and `loadHistory` are read from
  UserDefaults), read a new `rbDailySteps` key (JSON-encoded `[date: steps]`)
  into `dailySteps`, defaulting to empty when absent.

### 3. Heatmap UI components (theme-reactive)

**New file**: `Sources/AppCore/ActivityHeatmapView.swift`

- `ActivityHeatmapSection` — the composed section: a title row, the metric
  segmented filter, the range selector, the grid, and a small legend
  (less → more). Reads `@ObservedObject ThemeStore.shared` (or `@Environment`
  as the rest of the app does) so it retints live; holds `@State` for the
  selected metric (default `.distance`) and range (default `.month`).
- A `HeatmapGrid` subview rendering `[[HeatmapDay]]` as rounded cells, weekday
  row labels, and month/週 column labels, colored by an intensity ramp derived
  from `Palette.brand`/`Palette.go` per `level`.
- A compact empty state (reuse the Buddy prompt pattern from
  `ActivityHistoryEmptyState`) shown when there are no workouts and no daily
  steps in range; and a per-metric "no step data yet" note for the steps metric
  when `dailySteps` is empty.

Use `Layout`, `Typography`, and `Palette` tokens throughout — no hardcoded
sizes/colors — so it matches the app and scales with Dynamic Type.

### 4. Mount it atop Activity History

**File**: `Sources/AppCore/ActivityHistoryView.swift`

Insert `ActivityHeatmapSection` as the first child of the existing `ScrollView`'s
`VStack`, above the `ForEach(weeks) { ActivityWeekSection... }`. When there are
no weeks (day-one), still show the heatmap section's own empty state rather than
only the full-screen `ActivityHistoryEmptyState` — decide with the user during
build whether the heatmap replaces or sits above the day-one empty prompt.

### 5. Tests

**New file**: `Tests/AppCoreTests/ActivityHeatmapTests.swift`

XCTest coverage (`swift test --parallel --disable-swift-testing`) of the pure
logic, each with a `//`-comment description above the `func testX()`:

- Distance metric bins a rich multi-week workout list into expected levels
- Active-minutes metric bins by duration, independent of distance
- Steps-vs-goal metric bins against `goalSteps`; empty `dailySteps` → all level 0
- Range selection changes the number of week columns (week vs month vs 3-month)
- Monday-start week alignment and unparseable-date dropping match `ActivityHistory`
- Rest days / empty days resolve to level 0

Register with `codeyam-editor editor reconcile-registry --auto-apply`.

## Reused existing code

- `ActivityHistory` (`Sources/AppCore/ActivityHistory.swift`, glossary:
  `ActivityHistory`) — Monday-start POSIX calendar, date parsing, unparseable-date
  dropping; factor shared helpers rather than duplicate.
- `LatestWorkout` (`Sources/AppCore/Model.swift`) — `date`, `distanceMiles`,
  `durationMinutes`, `type` are the heatmap's data atoms.
- `TodayState` / `model.today.workouts` (`Sources/AppCore/Model.swift`) — source
  series; extended with `dailySteps`.
- `ActivityHistoryView` (glossary: `ActivityHistoryView`) — host screen.
- `ActivityHistoryEmptyState` (glossary: `ActivityHistoryEmptyState`) — Buddy
  empty-state pattern to mirror.
- `Palette` (`Sources/AppCore/Theme.swift`), `Typography`, `Layout` — theme
  tokens / type / spacing so the heatmap is on-brand and retints with the five
  themes (glossary: `Theme`, `ThemeStore`).

## Scenarios to Demonstrate

- **Heatmap — Rich Multi-Week (Distance)** — a dense several-week workout history,
  default distance metric, month range: a lively spread of intensities.
- **Heatmap — Active Minutes** — same data, active-minutes metric selected, to
  show the filter changing the read.
- **Heatmap — Steps vs. Goal** — seeded `rbDailySteps` with a mix of goal-hit and
  short days, steps metric selected.
- **Heatmap — Sparse** — a few scattered workouts, mostly rest days (lots of
  level-0 cells).
- **Heatmap — Empty (Day One)** — no workouts, no daily steps: the friendly Buddy
  empty state.
- **Heatmap — Week vs 3-Month range** — the same history at the narrow and wide
  spans, to show the range selector.
- **Heatmap — Themed** — the rich heatmap rendered under a non-default theme
  (e.g. Bolt or Garden) to prove the intensity ramp retints on-brand.
