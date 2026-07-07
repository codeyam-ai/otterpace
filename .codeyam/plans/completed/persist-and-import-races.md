---
title: "Persist Added Races & Import Races from the Web"
mode: ui
createdAt: "2026-07-06T18:38:32Z"
source: manual
---

## Summary

Fix a data-loss bug where races the user adds disappear across app sessions, and
add two new ways to create a race without hand-typing every field: **import from a
URL** (paste a race's web page; the AI coach extracts the details) and **search
online by name** (type a race name; pick from candidate results). Both new paths
end in the existing `RaceEditorView` pre-filled, so the user always confirms and
edits before saving. Both reuse the app's established BYO-key coach-proxy
architecture (Swift client → Vercel endpoint → Anthropic), so no Anthropic key
ever leaves the device path already trusted by the coach.

## Bug: added races don't persist across sessions

**Current broken behavior.** A user adds a race in Settings → it's written to
UserDefaults under `otterpaceRaces` and immediately shown. On the next launch (or
any HealthKit `connect()` / Today pull-to-refresh), the race is gone from the UI,
even though the JSON is still on disk.

**Root cause.** `RaceStore` persistence is correct and round-trips
(`RaceGoals.swift:161–194`, proven by `testStoreRoundTripsAndMutates`). The launch
load is also correct (`Model.swift:144`, `RaceStore.load`). The defect is that the
**live `today` snapshot is replaced wholesale** and the on-device fields are
dropped:

- `OtterpaceModel.connect()` (`Model.swift:273`) and `refresh()`
  (`Model.swift:286`, wired to Today's `.refreshable` at `TodayView.swift:83`)
  both do `today = await source.loadToday()`.
- `HealthKitDataSource.loadToday()` (`HealthKitDataSource.swift:79–91`) builds a
  fresh `TodayState` that **omits `races:` and `profile:`**, so they reset to `[]`
  / `nil`.

Result: races (and, by the same clobber, the coach `profile`) survive in
UserDefaults but are never re-merged into `today` after a HealthKit load — "added
in one session, gone in a later session." The seeded/scenario path
(`SeededHealthDataSource.loadToday`) does not have this bug because it goes through
`OtterpaceModel.readState`, which repopulates from the seed key — which is why the
bug is invisible in scenarios but hits real HealthKit users.

**Expected correct behavior.** After any `loadToday()`, the on-device race list and
coach profile are preserved. Add a race, force-quit, relaunch (or pull-to-refresh),
and the race is still there.

## Key Decisions

- **Re-merge on-device state after every `loadToday()`, in one place** — rather
  than teaching each data source to fold in `races`/`profile`. A single
  `applyOnDeviceState()` helper on `OtterpaceModel` called right after both
  `today = loadToday()` sites keeps the fix DRY and covers `connect()`, `refresh()`,
  and any future load path. This also fixes the identical latent `profile` clobber
  in the same stroke (per chosen scope).
- **Both import and search, funneling into the existing editor** — the user picked
  "Both URL + search." Both produce a partially-filled `RaceGoal` (or a struct the
  editor can seed from) and open `RaceEditorView` for confirm/edit/save. We never
  auto-save a machine-extracted race; the human confirms. This reuses all existing
  validation, unit handling, and the `onSave → model.addRace` path.
- **Server-side fetching & extraction via the coach-proxy pattern** — the app must
  not fetch arbitrary HTML on-device (privacy, reliability, CSP, and to keep the
  Anthropic prompt server-side). Two new Vercel endpoints mirror `api/coach.ts`
  (same `x-anthropic-key` header, rate-limit, size guards, JSON-schema-constrained
  output). Two new thin Swift clients mirror `RemoteCoach`.
- **Graceful degradation** — like `AskCoachView`, if there's no coach key or the
  request fails, the import/search UI shows a clear message and the user can still
  add a race manually. No hard dependency on connectivity.
- **Structured extraction output** — the extraction endpoint returns a strict JSON
  shape (`name`, `date` as `yyyy-MM-dd`, `distanceMiles` or `distance`+`unit`,
  `location`, optional `notes`, plus a `confidence`/`missingFields` hint) so the
  editor can highlight low-confidence fields the user should double-check.

## Implementation

### 1. Fix the persistence clobber (the bug)

**File**: `Sources/AppCore/Model.swift`

Add an internal helper that re-applies on-device state onto the current `today`
snapshot, and call it immediately after both `today = await source.loadToday()`
sites:

- In `connect()` (line ~273) and `refresh()` (line ~286), after assigning
  `today = await source.loadToday()`, call `applyOnDeviceState()`.
- `applyOnDeviceState()` sets `today.races = RaceStore.load(defaults)` and
  `today.profile = CoachProfileStore.load(defaults)` (use whichever defaults
  instance the model already uses at launch — see `Model.swift:134–149`), so the
  freshly loaded HealthKit snapshot regains the persisted race list and profile.
- Verify no double-encoding/round-trip mismatch with the seeded path: the seeded
  source already repopulates via `readState`; guard so `applyOnDeviceState()` is
  correct in both real and seeded environments (either always re-merge, or skip
  when the source already carries races — prefer always re-merge from the same
  store the mutators write to).

**File**: `Sources/AppCore/HealthKitDataSource.swift`

Optional belt-and-suspenders: leave `loadToday()` as-is (it legitimately doesn't
know about UserDefaults), since the re-merge now lives in the model. Do **not**
duplicate the load in two places — the model helper is the single source of truth.

### 2. Backend: race-import endpoint (URL → structured race)

**New file**: `api/race-import.ts`

Mirror `api/coach.ts` structure (`handler`, method/content-type/size checks,
`x-anthropic-key` header, `api/_lib/ratelimit.ts` `allow`/`clientIp`). Body:
`{ url: string }`. Steps:

- Validate/normalize the URL (http/https only; reject private/loopback hosts to
  avoid SSRF; cap redirects and response size; short timeout).
- Server-side `fetch` of the page; strip to text/relevant content (title + main
  text) to keep tokens bounded.
- Call Anthropic (`@anthropic-ai/sdk`, `MODEL = process.env.COACH_MODEL ||
  "claude-opus-4-8"`) with a focused extraction system prompt + a
  JSON-schema-constrained `FORMAT` returning the structured race shape above.
- Respond `{ race: {...}, confidence, missingFields }`; map upstream 401→invalid
  key, 429→rate limited, other→server, consistent with `coach.ts`.

### 3. Backend: race-search endpoint (name → candidates)

**New file**: `api/race-search.ts`

Same proxy scaffolding. Body: `{ query: string }`. Returns
`{ results: [{ name, date, location, distance, unit, sourceUrl }] }` (a small,
capped list). Use the model's web/tool capability (or a lightweight search step) to
produce candidates; each candidate carries a `sourceUrl` so the user can fall back
to the URL-import path for full detail. Keep result count small and rate-limited.

*(If a server-side web-search dependency isn't yet configured, note it here for the
editor workflow: this endpoint may need a search API key env var; the URL-import
endpoint has no such dependency and can ship first.)*

### 4. Swift clients for the two endpoints

**New file**: `Sources/AppCore/Coach/RaceImportClient.swift`

Model closely on `RemoteCoach` (`Sources/AppCore/Coach/RemoteCoach.swift`):
- Reuse `CoachConfig.keyAccount` / `CoachKeyStore` for the Anthropic key, and
  `CoachError` for error mapping.
- `func importRace(from url: String, apiKey: String) async throws ->
  RaceImportResult` — POST `{ url }` to `https://otterpace.com/api/race-import`
  with `x-anthropic-key`, decode into a `RaceImportResult` (a partial race +
  confidence/missingFields).
- `func searchRaces(query: String, apiKey: String) async throws ->
  [RaceSearchResult]` — POST `{ query }` to `.../api/race-search`. (Can live in the
  same file or a sibling `RaceSearchClient.swift`.)
- Add small `Codable` DTOs and a mapping to `RaceGoal` (respecting
  `RaceDistance.miles(from:unit:)` and the `date` `yyyy-MM-dd` format).

### 5. UI: import & search entry points feeding the editor

**File**: `Sources/AppCore/RaceEditorView.swift`

- Add an initializer / seed path so the editor can be opened pre-filled from a
  `RaceGoal` draft (reuse the existing edit-mode plumbing where possible; the view
  already builds a `RaceGoal` and calls `onSave`).
- Optionally surface low-confidence / missing fields (from `missingFields`) with a
  subtle hint so the user knows what to verify.

**File**: `Sources/AppCore/SettingsView.swift`

- In the Races card (`racesCard`, lines ~398–408) / add-race flow, add two new
  affordances beside "Add manually": **"Import from URL"** and **"Search online"**.
- "Import from URL": a small sheet with a URL text field → calls
  `RaceImportClient.importRace` → on success opens `RaceEditorView` pre-filled → on
  save routes through the existing `onSave → model.addRace` path (which now
  persists correctly thanks to fix #1).
- "Search online": a search field → `searchRaces` → a results list → tapping a
  result opens the editor pre-filled (using the candidate, or fetching full detail
  from its `sourceUrl` via import).
- Mirror `AskCoachView`'s no-key / error handling: if `keyStore.key == nil` or the
  call fails, show a message and offer manual entry. Reuse the coach key store so
  the user doesn't configure a second key.

## Reused existing code

- `RaceStore.load` / `save` / `add` / `update` / `remove` from
  `Sources/AppCore/RaceGoals.swift` (glossary entry: `RaceStore`) — the on-device
  race persistence the fix re-merges from.
- `RaceGoal`, `RaceDistance`, `DistanceUnit` from `Sources/AppCore/RaceGoals.swift`
  (glossary entries: `RaceGoal`, `RaceDistance`) — model + unit conversion
  (`RaceDistance.miles(from:unit:)`) for mapping extracted/searched data.
- `RaceEditorView` from `Sources/AppCore/RaceEditorView.swift` (glossary entry:
  `RaceEditorView`) — the confirm/edit/save surface both new paths funnel into.
- `RemoteCoach`, `CoachConfig`, `CoachKeyStore`, `CoachError` from
  `Sources/AppCore/Coach/RemoteCoach.swift` — client template + shared Anthropic
  key store + error taxonomy for the two new clients.
- `AskCoachView.submit(_:)` no-key/fallback pattern from
  `Sources/AppCore/AskCoachView.swift:121–150` — the graceful-degradation UX to
  copy.
- `api/coach.ts` handler + `api/_lib/ratelimit.ts` (`allow`, `clientIp`) — backend
  scaffolding (auth header, method/size guards, rate limiting, Anthropic call,
  JSON-schema-constrained output) for the two new endpoints.
- `OtterpaceModel.addRace/updateRace` (`Model.swift:297–299`) and
  `CoachProfileStore` — the mutation + profile store the re-merge helper reads.

## Scenarios to Demonstrate

- **Persistence fixed (happy path):** User adds a race, app does a
  `refresh()`/relaunch, the race is still present in Settings and the Today banner
  reflects the upcoming race.
- **Persistence — profile too:** Coach profile set on device survives a
  HealthKit `loadToday()` (regression guard for the same clobber).
- **Import from URL (rich):** Paste a real race URL → editor opens pre-filled with
  name, date, distance (km race round-tripping to display), location.
- **Import from URL (partial/low-confidence):** A sparse page → editor opens with
  the fields that were found and clearly flags the missing ones for the user.
- **Search online:** Type a race name → a short list of candidates → pick one →
  editor pre-filled → save persists.
- **No coach key / offline:** Import and search both show a clear message and fall
  back to manual entry; no crash, no lost input.
- **Invalid / unreachable URL:** Graceful error, user stays in the flow.
