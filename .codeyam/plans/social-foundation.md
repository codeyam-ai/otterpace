---
title: "Social Foundation — Identity, Friendships, and the Redaction Guarantee"
mode: ui
createdAt: "2026-07-30T19:07:00Z"
source: manual
order: 5
dependsOn: ["strava-handler-consolidation"]
---

## Summary

The first half of Otterpace's social layer: everything needed to *have* a friend,
with no feed UI yet. Consent, a social profile with a shareable friend code,
friend requests and acceptance, the backend and its tables, and — the load-bearing
piece — the **redaction guarantee**: one pure, unit-tested function that projects
`TodayState` down to the thin daily card a friend is allowed to see, and a server
that independently re-validates that shape on write.

Splitting the original 16 KB `social-friends-and-cheers` plan here is deliberate.
Redaction is a privacy promise, and it is far easier to get right — and to prove
right — when it lands and gets tested before any UI depends on it. Everything a
user can *see* about a friend ships in the companion plan
`social-friends-feed`. Everything in this plan is reachable from Settings alone.

Nothing changes for a user who never turns social on: no sign-in, no shared data,
**no new tab**, no prompt. That last point is a change from the original plan and
is called out below.

## Key Decisions

- **Reuse the bearer-session stack; invent no new auth.** `AccountSessionService`
  already exchanges an Apple identity token for a long-lived bearer stored in the
  Keychain, and `requireUser()` in `api/_lib/session.ts` resolves the user
  server-side from that bearer — never from a client-supplied id. Every social
  endpoint calls `requireUser` and derives *both* sides of a friendship from
  server state. This is the single most important security property of the
  feature: a client can never assert who it is or who it is friends with.

- **Social is a third opt-in stream, not a change to the two existing ones.** Add
  `socialSharingEnabled` + `socialConsentAcknowledged` to the existing
  `SyncConsentStore` (`Sources/AppCore/Account/SyncConsent.swift`), following the
  health-sync pattern exactly: off by default, a one-time consent explainer must
  be acknowledged before the first publish, and turning it off offers to delete
  what was already shared. Social data goes in its **own tables**, so it can be
  deleted independently of `account_prefs` and `account_health`.

- **A friend sees a redacted `FriendActivity`, not a `TodayState`.** The client
  builds the share payload through one pure function, `SocialShare.redact(_:)`,
  which projects `TodayState` down to `{ date, steps, goalSteps, buddyMood,
  latestWorkoutSummary }` and nothing else. The server re-validates the shape and
  drops unknown keys on write, mirroring the `prefsContainHealthFields` defense-
  in-depth guard in `api/_lib/account.ts`. Redaction being a pure, unit-tested
  function is what makes "we never leak more than we said" verifiable rather than
  a claim.

- **Friend codes, not directory search.** Discovery is by a short, shareable
  code (e.g. `OTTR-4F2K`) plus an exact-match lookup — never a browsable list of
  users, never email or phone matching. A privacy-first running app should not
  ship a people directory. The code is regenerable from Settings, and regenerating
  invalidates the old one so a code shared too widely can be retired.

- **Display names are user-generated content, and are treated as such.** The
  original plan claimed a "moderation surface at zero" because cheers are the only
  interaction. That was wrong: a display name is free text that other people see,
  which is exactly what App Review's UGC guideline covers. Three mitigations, all
  in this plan: names are **length- and charset-bounded** server-side (≤24 chars,
  no control characters, no zero-width/bidi-override codepoints); friendship is
  **mutual-consent only** — you only ever see the name of someone whose request
  you accepted, so there is no way to push a name at a stranger; and **remove-friend
  is immediate and bidirectional**. The reporting path ships with the feed in the
  companion plan, since that's where a name becomes visible.

- **One serverless function, and the capacity for it now exists.** All social
  routes live in a single catch-all `api/social/[...route].ts` dispatching on the
  path segment. The prerequisite `strava-handler-consolidation` plan takes the
  deployment from 12 functions to 9, so this lands at 10 — inside the Hobby-tier
  cap of 12. **This plan must not be started before that one lands**, which is why
  it is declared in `dependsOn` rather than mentioned in prose.

## Implementation

### 1. Social domain models + pure logic

**New file**: `Sources/AppCore/Social/SocialModels.swift`

`Codable, Equatable` types mirroring the `RaceGoal` / `CoachProfile` house style
(tolerant `init(from:)` with defaults on every optional and collection, so older
payloads keep decoding):

- `SocialProfile` — `userID`, `displayName`, `friendCode`.
- `Friendship` — `id`, `otherUserID`, `displayName`,
  `status` (`pending` | `accepted`), `direction` (`incoming` | `outgoing`).
- `FriendActivity` — `userID`, `displayName`, `date` (ISO `yyyy-MM-dd`),
  `steps`, `goalSteps`, `buddyMood`, `latestWorkoutSummary: String?`,
  `cheeredByMe: Bool`, `cheerCount: Int`.

Plus pure helpers, all XCTest-covered:

- `SocialShare.redact(_ today: TodayState) -> FriendActivity` — the single
  projection point described above.
- `SocialFeed.sort(_:)` — newest date first, then display name, so the feed is
  deterministic for captures.
- `SocialFeed.groupByDay(_:asOf:)` — "Today" / "Yesterday" / ISO date sections,
  reusing the POSIX/UTC date convention from `RaceGoal.daysUntil`.
- `FriendCode.normalize(_:)` / `FriendCode.isValid(_:)` — uppercase, strip
  spaces/hyphens, validate the `OTTR-XXXX` shape so paste-with-formatting works.
- `DisplayName.sanitize(_:)` — trim, collapse whitespace, cap at 24 characters,
  strip control/zero-width/bidi-override codepoints. Client-side courtesy; the
  server enforces independently.

**New test**: `Tests/AppCoreTests/SocialModelsTests.swift` — redaction drops every
field it should (assert explicitly that `workouts`, `loadHistory`, `dailySteps`,
`races`, `profile`, **and `journal`** never appear — see the cross-plan note
below), sorting/grouping, code normalization, display-name sanitization including
a bidi-override case, and tolerant decode of a payload missing the newer fields.

> **Cross-plan note:** `journal` is added to `TodayState` by the
> `post-run-journal-and-check-ins` plan. If that plan has landed, the redaction
> test **must** assert `journal` never appears in a share payload — journal text
> is the most personal data in the app and must never reach a friend. If journal
> has not landed yet, add the assertion when it does. Whichever of the two ships
> second owns this.

### 2. Social transport (client)

**New file**: `Sources/AppCore/Social/SocialClient.swift`

A bearer-authenticated client in the shape of `AccountSessionService` /
`URLSessionAccountSyncTransport`: injectable `URLSession` and base URL, reads the
token from `AccountSessionStore`, best-effort throughout (any failure leaves the
feature simply unavailable rather than erroring the app). Methods: `profile()`,
`updateProfile(displayName:)`, `regenerateFriendCode()`, `lookup(code:)`,
`requestFriend(userID:)`, `respond(to:accept:)`, `removeFriend(userID:)`,
`friends()`, `publish(_ activity: FriendActivity)`, `purgeSocialData()`.

`feed()` and `cheer(userID:date:)` are declared here but consumed by the companion
plan.

**New test**: `Tests/AppCoreTests/SocialClientTests.swift` — a stub transport
asserts the `Authorization: Bearer …` header is attached, that a missing token
short-circuits without a request, and that non-200s degrade quietly.

### 3. Social store

**New file**: `Sources/AppCore/Social/SocialStore.swift`

`ObservableObject` holding `@Published` `profile`, `friends`, `requests`, `feed`,
and a `loadState` (`idle` / `loading` / `loaded` / `unavailable`). Mirrors
`SeededHealthDataSource`: when a scenario has seeded `rb*` keys
(`HealthSource.isScenarioSeeded()`), it hydrates from `rbSocialFeedJSON`,
`rbSocialFriendsJSON`, `rbSocialRequestsJSON`, `rbSocialProfileJSON`, and
`rbSocialState` and **never touches the network**, so captures stay offline and
deterministic. Otherwise it drives `SocialClient`.

Explicitly seed the "off" value for every social key in scenarios that don't use
them — the bleed-proofing rule this repo already follows for `rb*` seeds.

### 4. Consent flags

**File**: `Sources/AppCore/Account/SyncConsent.swift`

Add `socialSharingEnabled` (key `otterpaceSocialSharingEnabled`) and
`socialConsentAcknowledged` (key `otterpaceSocialConsentAcknowledged`), plus
`acknowledgeSocialConsent()` and a `setSocialSharingEnabled(_:)` that no-ops
unless consent was acknowledged — the same `@discardableResult` guard the health
flag uses. Extend `Tests/AppCoreTests/AccountSyncTests.swift`.

### 5. Settings — Friends & sharing

**File**: `Sources/AppCore/SettingsView.swift`

A new card between Account and AI Coach, built from the existing `card(...)` /
`actionRow(...)` helpers. **This is the feature's only entry point until the feed
ships**, and remains its discovery point afterward:

- Master **"Share my activity with friends"** toggle, gated by the consent sheet
  (reuse the health-consent sheet pattern at lines ~259–346, including the
  "what's shared / what isn't" copy).
- Your display name (editable, sanitized on commit) and friend code, with **Copy**
  and **Regenerate**.
- **Add a friend** — the code-entry sheet.
- **Manage friends** — the friends list, incoming requests with Accept / Decline,
  and remove.
- **"Turn off & delete shared data"** destructive action calling
  `SocialClient.purgeSocialData()`, matching the health-sync disable dialog.
- Account deletion (line ~151) must also purge social rows — extend the existing
  `purgeOnAccountDeletion` path so the App Store deletion requirement still holds.

**New files** under `Sources/AppCore/Social/`:

- `AddFriendSheet.swift` — enter/paste a friend code, live-validated via
  `FriendCode.isValid`, showing the matched profile before you send. Also shows
  **your** code with a share action.
- `FriendListView.swift` — accepted friends and pending requests, with Accept /
  Decline / Remove.
- `FriendRequestRow.swift` — one incoming request.
- `SocialConsentSheet.swift` — the one-time "here's exactly what friends see"
  explainer.

All read `Palette` / `Typography` / `Layout` tokens so they retint across the five
themes, and scale with Dynamic Type.

### 6. Backend — one catch-all function

**New file**: `api/social/[...route].ts`

Single Vercel handler, `requireUser` first on every path, dispatching on the
route segment — the same dispatch idiom as the consolidated
`api/strava/[...route].ts`:

| Route | Methods | Behavior |
|---|---|---|
| `profile` | GET, PUT | own profile; PUT sets display name / regenerates code |
| `lookup` | GET `?code=` | exact friend-code match → minimal public profile |
| `requests` | GET, POST, PATCH | list incoming/outgoing; send; accept/decline |
| `friends` | GET, DELETE | accepted list; remove (both directions) |
| `share` | PUT | publish own redacted daily card |
| `purge` | DELETE | delete this user's profile, friendships, shares, cheers |

`feed` and `cheer` routes are added by the companion plan.

Rate-limit writes with the existing `api/_lib/ratelimit.ts`; friend-code lookup
especially, so codes can't be brute-forced.

**New file**: `api/_lib/social.ts`

Supabase PostgREST helpers via `env()` / `supabaseHeaders()` from
`api/_lib/strava.ts` (the established no-SDK pattern), plus the pure logic that
carries the tests:

- `normalizePair(a, b)` — canonical ordering so a friendship is one row, not two,
  and `(a,b)` can't duplicate `(b,a)`.
- `sanitizeShare(payload)` — allowlist the five permitted keys, drop everything
  else, bound the payload size (mirrors `MAX_PREFS_BYTES`).
- `sanitizeDisplayName(name)` — the server-side enforcement of the ≤24-char,
  no-control-codepoint rule. Independent of the client helper by design.
- `generateFriendCode()` — `randomBytes`-backed, ambiguity-free alphabet
  (no `0`/`O`/`1`/`I`).
- `canSee(viewerId, ownerId, friendships)` — the authorization predicate every
  read goes through.

New Supabase tables, documented in the file header the way `api/_lib/account.ts`
documents its own (create-once DDL in a comment): `social_profiles`,
`social_friendships` (with a `status` check constraint and a unique index on the
normalized pair), `social_shares`, `social_cheers` (unique on
`from_user, to_user, share_date`).

**New test**: `test/api/social.test.ts` — pair normalization, share sanitization
(assert a payload carrying `workouts` or `dailySteps` is stripped), display-name
sanitization, code generation shape, `canSee` rejecting non-friends **and pending
requests**, and 401 on every route without a bearer.

### 7. Privacy copy + docs

- **File**: `site/privacy.html` — a short "Friends (optional)" section stating
  exactly what a friend can see, that it's off by default, and that it's
  deletable. The privacy page currently promises health data is never
  transmitted; that sentence needs the "unless you turn on friends" qualifier or
  it becomes inaccurate the day this ships. **This is a shipping blocker, not a
  nice-to-have.**
- **New file**: `docs/social.md` — table DDL, endpoint contract, and the
  redaction guarantee, matching `docs/account-sync.md`.
- `Analytics.shared.capture` events: `social_enabled`, `friend_request_sent`,
  `friend_request_accepted`, `social_disabled`. Counts only — no friend ids, no
  payloads (consistent with the existing analytics posture).

## Reused existing code

- `AccountSessionService` / `AccountSessionStore` from
  `Sources/AppCore/Account/AccountSession.swift` — bearer token issuance + Keychain
  storage, used unchanged.
- `requireUser` / `bearerToken` from `api/_lib/session.ts` — server-side identity
  on every social route.
- `env` / `supabaseHeaders` from `api/_lib/strava.ts` — the no-SDK Supabase access
  pattern reused verbatim.
- `SyncConsentStore` from `Sources/AppCore/Account/SyncConsent.swift` — extended
  with a third stream rather than duplicated.
- The health-consent sheet in `Sources/AppCore/SettingsView.swift` (~259–346) —
  the template for the social consent moment.
- `HealthSource.isScenarioSeeded()` (`Sources/AppCore/Health/HealthDataSource.swift`)
  — the offline/deterministic gate for `SocialStore`.
- `api/_lib/ratelimit.ts` — write + lookup throttling.
- `prefsContainHealthFields` (`api/_lib/account.ts`) — the defense-in-depth
  precedent `sanitizeShare` follows.
- `api/strava/[...route].ts` (from the prerequisite plan) — the catch-all dispatch
  idiom this file matches.

## Scenarios to Demonstrate

- **Settings — social off (default)**: the Friends card in its untouched state,
  proving the solo-mode default is unchanged.
- **Social consent sheet**: the one-time "here's exactly what friends see"
  explainer.
- **Settings — Friends & sharing on**: consent acknowledged, display name and
  friend code visible, destructive "turn off & delete" present.
- **Add friend sheet — matched**: a valid pasted code resolving to a profile,
  ready to send.
- **Add friend sheet — invalid code**: inline validation error, send disabled.
- **Friend list — with a pending incoming request**: Accept / Decline visible
  above two accepted friends.
- **Friend list — empty**: sharing on, nobody added yet.
- **Friend list under large text**: `rbContentSize="accessibility3"` over a
  24-character display name — the truncation edge case.
- **Settings Friends card — Bolt theme** (and one more, e.g. Garden): confirms
  the new surfaces retint across the five-theme system.
