---
title: "Quiet Hours Respect the User's Timezone"
mode: backend
createdAt: "2026-07-30T19:05:00Z"
source: manual
order: 2
---

## Summary

The server-side movement nudge computes its overnight quiet window in **UTC**.
`api/cron/movement-nudge.ts:36` reads `now.getUTCHours()` with the comment
`// per-user timezone is a future refinement; UTC baseline`, and feeds that hour
straight into `shouldNudge`. `DEFAULT_QUIET_HOURS` is `{ startHour: 21, endHour: 8 }`
— intended as 9pm–8am *local*. For a user in `America/New_York` (UTC−4 in summer),
the guard actually protects **5pm–4am local**: it silences the evening nudge that
should fire, and it opens a window from 4am–8am where a push can wake someone up.
For `America/Los_Angeles` (UTC−7) the skew is worse.

This is a live production bug affecting every US user with server push enabled,
and it is small and self-contained: one pure helper, one new nullable column, one
field threaded through the existing health heartbeat. It was previously buried as
one bullet inside the `activity-freshness` draft, behind a page of open questions.
It is extracted here so it can ship on its own.

## Key Decisions

- **IANA zone identifiers, not fixed offsets.** Store `America/New_York`, not
  `-240`. A stored offset is wrong for half the year, and the failure mode is
  exactly the one we're fixing — a quiet window silently sliding by an hour at
  each DST transition. iOS hands us `TimeZone.current.identifier` in IANA form
  already, so this costs nothing at the source.

- **Resolve the local hour with `Intl.DateTimeFormat`, not date math.** Node's
  built-in ICU gives a correct, DST-aware local hour for any IANA zone with no
  dependency and no offset table to maintain. Manual arithmetic on offsets is
  precisely how the second version of this bug gets written.

- **An unknown timezone falls back to UTC — today's behavior — not suppression.**
  The companion freshness work argues "when in doubt, stay quiet," and that's
  right for *stale* data. A missing timezone is different: it's a field absent
  during client rollout, and suppressing on it would silently switch nudges off
  for every user who hasn't updated yet. Falling back to UTC means nobody gets
  worse than today, and everyone on a current build gets correct. Once client
  adoption is high the fallback can tighten — note it in the code so the decision
  is visible rather than inherited.

- **The timezone rides the health heartbeat that already exists.** `api/account/health.ts:75–78`
  already pulls `lastMovementAt` and `inactivityHours` out of the health payload
  and calls `mirrorMovement` to copy them onto the push row. `timeZone` follows
  that identical path. No new endpoint, no new client request, no new consent
  surface — it is one more field on a payload the user already opted into.

- **The decision stays pure.** `shouldNudge` keeps taking a `localHour` number;
  it does not learn about timezones. The new `localHourIn(zone, now)` helper sits
  beside it in `api/_lib/nudge.ts` and is separately testable. This preserves the
  pure-policy split that file's header comment explicitly sets out to protect.

## Implementation

### 1. The pure helper

**File**: `api/_lib/nudge.ts`

Add alongside `isQuietHour`:

```
export function localHourIn(timeZone: string | null, now: Date): number
```

Returns the hour `[0–23]` in `timeZone`, resolved via
`new Intl.DateTimeFormat("en-US", { timeZone, hour: "numeric", hour12: false })`.
Returns `now.getUTCHours()` when `timeZone` is null/empty, and also when
`Intl` throws on an unrecognized identifier — a garbage value from a client must
degrade to today's behavior, never crash the cron scan for every other user.

Note the `hour12: false` detail: it can format midnight as `24`, so normalize
with `% 24` before returning. This is the one real trap in the helper and is
worth an explicit test.

### 2. Persist the zone

**File**: `api/_lib/account.ts`

- Add `time_zone: string | null` to the `PushRow` interface (line ~168).
- Extend `mirrorMovement` (line 246) to accept and write an optional `timeZone`,
  preserving the existing `getPush` → `upsertPush` merge shape so a null never
  clobbers a previously stored good value.
- `listNudgeCandidates` needs no change — it already does `select=*`.
- Add the column to the `account_push` DDL comment in the file header, matching
  how `account_prefs` / `account_health` are documented there:
  `alter table account_push add column time_zone text;`

### 3. Accept it from the heartbeat

**File**: `api/account/health.ts`

At the `mirrorMovement` call (lines 75–78), also read `health["timeZone"]`, accept
it when `typeof === "string"` and it is ≤64 chars matching a conservative IANA
shape (`/^[A-Za-z0-9+_\-\/]{1,64}$/`), and pass it through. Validating the shape
here keeps an unbounded client string out of the database.

### 4. Use it in the scan

**File**: `api/cron/movement-nudge.ts`

Delete the module-level `const localHour = now.getUTCHours()` at line 36 — the
whole bug is that one hour is computed **once for every user in the scan**. Move
the resolution inside the candidate loop:

```
const localHour = localHourIn(user.time_zone, now);
```

Remove the stale `// per-user timezone is a future refinement` comment.

### 5. Send it from the client

**File**: `Sources/AppCore/Account/AccountSyncService.swift`

Add `public var timeZone: String?` to the health snapshot struct beside
`lastMovementAt` / `inactivityHours` (lines 33–43), defaulted `nil` in the
memberwise init so no existing call site breaks. Populate it from
`TimeZone.current.identifier` at the point the snapshot is built.

### 6. Tests

**File**: `test/api/nudge.test.ts`

- `localHourIn` for a known instant across several zones (`UTC`,
  `America/New_York`, `America/Los_Angeles`, `Asia/Kolkata` — the half-hour offset
  is a good canary, `Pacific/Auckland` for a southern-hemisphere DST).
- **A DST boundary in both directions** — the same UTC instant on either side of
  the US spring-forward and fall-back transitions must yield different local
  hours. This is the case a fixed-offset implementation would fail, so it is the
  test that keeps the decision honest.
- Midnight normalizes to `0`, not `24`.
- `null` and a garbage identifier both fall back to `now.getUTCHours()` without
  throwing.
- End-to-end through `shouldNudge`: a candidate at 22:00 America/New_York is
  quiet, while the same instant in UTC (02:00) is *also* quiet — pick the pairing
  that demonstrates a real behavioral change, e.g. 19:00 New York (should nudge)
  vs. the 23:00 UTC the old code saw (was silenced).

**File**: `test/api/account.test.ts` — `mirrorMovement` writes `time_zone` and
does not null out an existing value when the field is absent.

**File**: `test/api/account-handlers.test.ts` — the health handler accepts a valid
zone and rejects an over-long or malformed one.

## Reused existing code

- `shouldNudge` / `isQuietHour` / `DEFAULT_QUIET_HOURS` (`api/_lib/nudge.ts`) —
  unchanged; the fix feeds them a correct `localHour` rather than altering the
  policy.
- `mirrorMovement` / `getPush` / `upsertPush` / `listNudgeCandidates`
  (`api/_lib/account.ts`) — the existing merge-upsert path, extended by one field.
- The `lastMovementAt` + `inactivityHours` extraction in `api/account/health.ts:75–78`
  — the exact template `timeZone` follows.
- `PushRow` (`api/_lib/account.ts:168`) and the `account_push` DDL header comment.
- The `env` / `supabaseHeaders` PostgREST pattern from `api/_lib/strava.ts` —
  untouched, but it's why no migration tooling is involved.

## Scenarios to Demonstrate

*(Backend-only — no simulator surface. Verification is the vitest suite plus one
staging check.)*

- Unit: 19:00 in `America/New_York` is **not** quiet, where the old UTC path saw
  23:00 and suppressed it — the evening nudge this bug was eating.
- Unit: 05:00 in `America/New_York` **is** quiet, where the old path saw 09:00 and
  would have pushed — the 4am–8am wake-up window this bug opened.
- Unit: spring-forward and fall-back instants resolve to different local hours.
- Unit: `Asia/Kolkata` half-hour offset resolves correctly.
- Unit: `null` and `"Not/AZone"` both fall back to UTC, no throw.
- Unit: two candidates in different zones in one scan get different local hours —
  the regression guard on the hoisted-constant bug specifically.
- Staging: run the cron handler against a seeded push row with `time_zone` set and
  confirm the send/skip decision flips as expected.
