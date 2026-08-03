---
title: "Journal — Post-Run Notes and Daily Check-Ins"
mode: ui
createdAt: "2026-07-30T18:26:00Z"
source: manual
order: 3
---

## Summary

Let a runner write down how it actually went. Two entry points, one store: a
**post-run note** attached to a workout ("legs heavy the first mile, then it
clicked") and a lightweight **daily check-in** — a feel rating, an energy /
soreness / sleep chip set, and an optional free-text line — reachable from
Today. Entries are **on-device only**, stored as a JSON array in `UserDefaults`
exactly like `RaceStore` and `CoachProfile`, and carried on `TodayState` so they
flow with no new transport into the deterministic `CoachEngine`, the remote AI
coach (`api/coach.ts`), and the `WeeklyReviewEngine`. That last part is the
point: Buddy stops reasoning from mileage alone and starts saying "you logged
three heavy-legs runs this week — take Thursday easy."

## Key Decisions

- **One `JournalEntry` type covering both surfaces, not two features.** A
  post-run note and a daily check-in differ only in whether they're bound to a
  workout. Modeling both as a single dated entry with an optional
  `workoutDate` + `workoutType` link means one store, one persistence path, one
  coach payload, and one set of tests — and it means "how did that run feel" and
  "how do I feel today" appear on the same timeline instead of in two disjoint
  histories.

- **On-device only, following the `RaceStore` pattern.** Journal text is the most
  personal data in the app. It goes in `UserDefaults` as a JSON array under
  `otterpaceJournalEntries` — no new table, no sync stream, no consent sheet
  needed, and it disappears with the app. It rides to the backend **only** on a
  connected-coach request, inside the `TodayState` the app already ships — the
  same posture, and the same privacy sentence, that `CoachProfile` already
  established.

- **Structured chips first, free text second.** The check-in leads with tappable
  chips (feel 1–5, plus energy / soreness / sleep) because they're one-tap on a
  phone, they're what the coach can reason over reliably, and they make an entry
  possible in three seconds. Free text is optional and always available, but
  never required — a journal that demands prose gets abandoned in a week.

- **The coach gets a bounded, recent slice — not the whole diary.** Only the last
  **14 days** of entries, each capped at ~200 characters of free text, ride in
  the coach context. `TodayState` already flows through a 16 KB
  `MAX_CONTEXT_BYTES` cap in `api/coach.ts`; an unbounded journal would silently
  push out `loadHistory` and degrade the coaching quality this feature is meant
  to improve. The bounding is a pure function, so the cap is testable rather than
  hoped for.

- **Deterministic coach first, model second.** `CoachEngine` gains journal-aware
  rules (repeated low feel or high soreness → a gentler nudge and a `recovery`
  Buddy mood; a run logged as great after a rest day → affirm it) so the feature
  works with **no API key at all** and stays reproducible in captures. The
  `api/coach.ts` system prompt then gets a short journal section for connected
  users, written in the same hedged style as the existing `profile` /
  `loadHistory` sections — "the user's own words about how they felt; treat as
  ground truth about subjective experience, never as a substitute for the safety
  rules."

- **The most personal data in the app gets a way out.** Because entries are
  on-device with no sync, there is no server-side delete to lean on — which means
  without an explicit affordance, the only way to clear your journal is to delete
  the app. Settings gets a destructive **"Delete all journal entries"** action with
  a confirm, matching the existing health-sync disable dialog's shape. A feature
  that invites people to write down how they really felt owes them an eraser.

- **Never a streak, never a scold.** No "you haven't journaled in 4 days," no
  completion ring, no unbroken-chain pressure. The empty state invites; it
  doesn't guilt. This is the same never-shame-based rule Buddy already follows,
  and a journaling feature is exactly where a wellness app usually breaks it.

- **Journal history lives inside Activity History, not a new tab.** The Activity
  History overlay already owns the dated workout timeline and the heatmap;
  entries slot into the week sections they belong to. That reuses the existing
  navigation and data instead of adding a fourth top-level destination for what
  is fundamentally an annotation on activity.

## Implementation

### 1. Journal domain model + pure logic

**New file**: `Sources/AppCore/Journal/JournalEntry.swift`

Modeled directly on `Sources/AppCore/RaceGoals.swift` — `Codable, Equatable,
Identifiable`, a tolerant `init(from:)` defaulting every field so older persisted
payloads decode, and enum cases carrying short human `label`s the way
`WalkVolume` / `TrainingKind` do in `CoachProfile.swift`.

```
JournalEntry
  id: UUID
  date: String            // ISO yyyy-MM-dd, matching LatestWorkout.date
  feel: Int?              // 1...5, nil when not rated
  energy: EnergyLevel?    // low | okay | good
  soreness: SorenessLevel?// none | mild | sore | painful
  sleep: SleepQuality?    // poor | okay | good
  note: String?           // free text, optional
  workoutDate: String?    // set => this is a post-run note
  workoutType: String?    // run | walk | ride, for the row's icon
```

Pure helpers, all XCTest-covered:

- `Journal.entry(forWorkoutOn:in:)` — the note attached to a given workout day.
- `Journal.checkIn(on:in:)` — today's non-workout check-in, if any.
- `Journal.recent(_:asOf:days:)` — the trailing-N-day slice, newest-first.
- `Journal.byWeek(_:asOf:)` — Monday-start grouping reusing the exact POSIX/UTC
  convention (and unparseable-date dropping) from `ActivityHistory.groupByWeek`,
  so journal rows land in the same weeks the history screen already renders.
- `Journal.coachSlice(_:asOf:)` — the bounded 14-day / 200-char-per-note
  projection that goes in the coach context.
- `Journal.summary(_:asOf:)` — counts + average feel + a dominant-soreness read
  over a window, consumed by both `CoachEngine` and `WeeklyReviewEngine`.

**New test**: `Tests/AppCoreTests/JournalTests.swift` — grouping, lookups,
tolerant decode of a payload missing the newer fields, and explicit assertions
that `coachSlice` truncates both the day window and the per-note length.

### 2. Persistence

**New file**: `Sources/AppCore/Journal/JournalStore.swift`

`load(_:)` / `save(_:)` / `upsert(_:)` / `delete(id:)` against an injectable
`UserDefaults` under `otterpaceJournalEntries`, the same shape as `RaceStore`.
Scenario seeding reads `rbJournalJSON` so a capture can pin an exact timeline;
`OtterpaceModel` hydrates `today.journal` from the store at launch and after
every edit.

**New test**: `Tests/AppCoreTests/JournalStoreTests.swift` — round-trip, upsert
replaces by id, delete, and an empty/corrupt default decoding to `[]` rather than
throwing (mirroring `RaceImportPersistenceTests`).

### 3. Carry entries on `TodayState`

**File**: `Sources/AppCore/Model.swift`

Add `public var journal: [JournalEntry]` — defaulted to `[]` in the memberwise
init and `decodeIfPresent(...) ?? []` in the tolerant decoder, exactly as
`races` / `loadHistory` were added. `OtterpaceModel` loads it from `JournalStore`
and exposes `saveJournalEntry(_:)` / `deleteJournalEntry(id:)` that write through
and republish. Extend `Tests/AppCoreTests/ModelTests.swift` for the new field's
default-and-decode behavior.

### 4. Capture surfaces

**New files** under `Sources/AppCore/Journal/`:

- `CheckInCard.swift` — on Today, below `WorkoutCard`: either "How'd today feel?"
  with the 1–5 feel row inline (one tap starts an entry), or today's logged
  entry in a compact read state with an edit affordance.
- `JournalEditorSheet.swift` — the full editor: feel selector, energy / soreness
  / sleep chip rows, a free-text field, Save / Delete. Used for both a check-in
  and a post-run note; the workout link is passed in.
- `FeelSelector.swift` — the 1–5 row, using theme tokens and carrying a full
  accessibility label per option (not just a number).
- `JournalChipRow.swift` — the shared labeled chip row for the three enums,
  following the capsule idiom already used by the step-goal presets in Settings.
- `JournalEntryRow.swift` — one entry rendered in history: date, feel, chips, and
  the note, with the workout icon when it's a post-run note.
- `JournalEmptyState.swift` — Buddy plus "A line about today is enough." Invites,
  never scolds.

**File**: `Sources/AppCore/TodayView.swift` — insert `CheckInCard` into the
`VStack` after the `WorkoutCard` branch (line ~72), and add a "How'd that run
feel?" affordance on `WorkoutCard` itself when the latest workout has no note yet.

**File**: `Sources/AppCore/WorkoutCard.swift` — optional `note`/`onAddNote`
parameters, defaulted so every existing call site keeps compiling; renders a note
preview line when present. Update the `accessibilityLabel` to include the note.

**File**: `Sources/AppCore/ActivityHistoryView.swift` — pass entries into
`ActivityWeekSection` so journal rows interleave with the week's workouts by date.

**File**: `Sources/AppCore/ActivityWeekSection.swift` — render `JournalEntryRow`
alongside the week's workouts.

### 5. Coach integration

**File**: `Sources/AppCore/CoachEngine.swift`

Journal-aware rules in `dailyNudge(for:)`, layered **below** the existing safety
rules so nothing about the pain/safety path changes:

- Two or more entries in the last 5 days with `soreness == .sore/.painful` or
  `feel <= 2` → soften the recommendation toward `rest`/`walk`, Buddy mood
  `recovery`, and reference it in plain words.
- A recent `feel >= 4` after a rest day → affirm, keep the plan.
- No entries → behave exactly as today. **This is the regression guard**: every
  existing `CoachEngineTests` case must pass unchanged with an empty journal.

**File**: `Sources/AppCore/WeeklyReviewEngine.swift` — add a journal line to the
"what went well" / "what changed" sections when the week has entries (e.g. "you
felt strong on three of four runs"), omitted entirely when it doesn't.

**File**: `api/coach.ts` — a `journal` section in the system prompt (near the
existing `profile` section at lines ~46–60), same hedged register: entries are
the user's own subjective account, optional, never invented when absent, and
never overriding the safety rules or the ~10% guidance. No transport change —
`journal` arrives inside the `TodayState` context that already ships.

**Tests**: extend `Tests/AppCoreTests/CoachEngineTests.swift` and
`WeeklyReviewEngineTests.swift`; extend `test/api/coach.test.ts` for the prompt
section.

### 6. Settings — delete all entries

**File**: `Sources/AppCore/SettingsView.swift`

A destructive **"Delete all journal entries"** row in the same card as the other
data controls, built from the existing `actionRow(...)` helper and gated by a
confirmation dialog in the shape of the health-sync disable dialog. Clears
`otterpaceJournalEntries` via `JournalStore` and republishes `today.journal` as
`[]`. Also extend the account-deletion path so journal entries go with it.

**Test**: extend `Tests/AppCoreTests/JournalStoreTests.swift` — delete-all empties
the store and a subsequent `load` returns `[]` rather than throwing.

### 7. Privacy copy

**File**: `site/privacy.html` — extend the "AI coach (optional)" paragraph, which
already enumerates what's sent, to name journal entries. They stay on-device and
leave only on a connected-coach request — the same sentence structure the
personalization profile already uses there.

> **Cross-plan note — journal must never reach a friend.** The `social-foundation`
> plan adds `SocialShare.redact(_:)`, which projects `TodayState` down to the five
> fields a friend may see, and a test asserting the excluded fields never appear.
> That test's exclusion list was written before `journal` existed on `TodayState`.
> **Whichever of these two plans lands second owns adding `journal` to that
> assertion** — both the Swift `SocialModelsTests` list and the server-side
> `sanitizeShare` allowlist test in `test/api/social.test.ts`. Journal text is the
> most personal data in the app; it must never be shareable.

## Reused existing code

- `RaceGoal` / `RaceStore` from `Sources/AppCore/RaceGoals.swift` — the
  UserDefaults-JSON persistence pattern, ISO-date convention, and tolerant-decode
  style the journal copies wholesale.
- `CoachProfile` from `Sources/AppCore/Onboarding/CoachProfile.swift` — the
  precedent for an optional on-device blob carried on `TodayState` into both
  coaches, including its privacy posture and enum-with-`label` idiom.
- `ActivityHistory.groupByWeek` / `ActivityHistory.referenceDate`
  (`Sources/AppCore/ActivityHistory.swift`) — Monday-start weeks and the UTC
  date convention, reused rather than reimplemented.
- `TodayState` optional-field pattern (`Sources/AppCore/Model.swift`) — `races`,
  `loadHistory`, `dailySteps` are the exact template for adding `journal`.
- `CoachEngine.dailyNudge` (`Sources/AppCore/CoachEngine.swift`) — extended, so
  the feature works with no API key and stays deterministic in captures.
- `WorkoutCard` (`Sources/AppCore/WorkoutCard.swift`) and `ActivityWeekSection` —
  existing rows extended, not replaced.
- `MoodChip` (`Sources/AppCore/MoodChip.swift`) and the Settings step-goal capsule
  idiom — the visual language for the chip rows.
- `HealthSource.isScenarioSeeded()` and the `rb*` seeding convention
  (`Sources/AppCore/Health/HealthDataSource.swift`) — `rbJournalJSON` follows it.

## Scenarios to Demonstrate

- **Today — check-in prompt**: no entry yet, "How'd today feel?" with the feel row
  live on the card.
- **Today — checked in**: today's entry in its compact read state (feel 4, energy
  good, a one-line note).
- **Post-run note prompt**: a 5.2-mile run on the `WorkoutCard` with no note yet
  and the "How'd that run feel?" affordance.
- **Journal editor — empty**: the sheet opened fresh, nothing selected.
- **Journal editor — rich**: feel 2, sore, poor sleep, and a real multi-line note
  — the "hard day" state, and the layout stress case.
- **Journal editor — long note + large text**: `rbContentSize="accessibility3"`
  over a note near the character cap.
- **History with journal rows**: a rich multi-week history where entries
  interleave with workouts, some post-run notes and some standalone check-ins.
- **History — no entries yet**: the invitation empty state, no streak language
  anywhere.
- **Coach responds to a rough week**: three low-feel/sore entries in five days →
  a gentler card, `recovery` Buddy mood, coach copy referencing how the runner
  said they felt.
- **Coach with an empty journal**: identical to today's behavior — the visible
  proof of no regression.
- **Weekly Review with journal context**: the recap including the "how it felt"
  line.
- **Settings — delete all entries confirm**: the destructive dialog, plain and
  non-alarming.
- **Check-in card — Fieldnote theme** (and one more, e.g. Orbit): the new cards
  retinting across the five-theme system.
