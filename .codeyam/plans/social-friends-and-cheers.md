---
title: "Social — Friends, Cheers, and a Friends' Activity Feed"
mode: ui
createdAt: "2026-07-30T18:25:31Z"
source: manual
---

## Summary

Give Otterpace a small, kind social layer: find and add friends, accept or
decline requests, see a friends' activity feed, and send a 🐾 **cheer** on
someone's day. It rides entirely on the existing Sign in with Apple → bearer
token → Supabase stack (`AccountSessionService` / `api/_lib/session.ts`), adds a
third **Friends** tab beside Today and Coach, and is **opt-in behind an explicit
consent moment** that mirrors the existing health-sync consent. Nothing about the
account-free, on-device default changes for a user who never turns social on: no
sign-in, no shared data, no new tab prompt beyond a friendly empty state. What a
friend sees is a deliberately thin, redacted daily card — steps vs. goal, Buddy's
mood, and one latest workout summary — never the full `TodayState`, never the
heatmap series, never journal entries or races.

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
  code (e.g. `OTTR-4F2K`) plus an exact-match handle lookup — never a browsable
  list of users, never email or phone matching. A privacy-first running app
  should not ship a people directory. The code is regenerable from Settings, and
  regenerating invalidates the old one so a code shared too widely can be retired.

- **One serverless function, because the deployment is exactly at the cap.**
  `api/` currently has **exactly 12** handler files and Vercel's Hobby tier caps a
  deployment at 12 serverless functions — so a naive `api/social/friends.ts` +
  `feed.ts` + `cheer.ts` split would fail to deploy. All social routes therefore
  live in **one** catch-all, `api/social/[...route].ts`, dispatching on the path
  segment. Even that is a 13th function: **before shipping, either confirm the
  project is on a plan above Hobby, or fold the four `api/strava/*` handlers into
  a single `api/strava/[...route].ts` first** (freeing 3 slots, landing at 10).
  Flagging this at plan time so it isn't discovered as a red deploy.

- **Cheers are the only interaction, and they're one-way and positive.** No
  comments, no likes-with-a-count-to-chase, no leaderboard. A cheer is one 🐾 per
  friend per day, idempotent server-side. This keeps the moderation surface at
  zero, which is the only responsible shape for a v1 social feature in a
  wellness app — and it matches Buddy's never-shame-based voice.

- **Feed is pull-on-appear, not push.** No new APNs work in this plan; the feed
  refreshes when the Friends tab appears and on pull-to-refresh, reusing the
  `.refreshable` pattern from `TodayDashboard`. Push notifications for cheers are
  a deliberate follow-up (the `PushRegistrationService` seam already exists).

## Implementation

### 1. Social domain models + pure logic

**New file**: `Sources/AppCore/Social/SocialModels.swift`

`Codable, Equatable` types mirroring the `RaceGoal` / `CoachProfile` house style
(tolerant `init(from:)` with defaults on every optional and collection, so older
payloads keep decoding):

- `SocialProfile` — `userID`, `handle`, `displayName`, `friendCode`.
- `Friendship` — `id`, `otherUserID`, `displayName`, `handle`,
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

**New test**: `Tests/AppCoreTests/SocialModelsTests.swift` — redaction drops every
field it should (assert explicitly that `workouts`, `loadHistory`, `dailySteps`,
`races`, and `profile` never appear), sorting/grouping, code normalization, and
tolerant decode of a payload missing the newer fields.

### 2. Social transport (client)

**New file**: `Sources/AppCore/Social/SocialClient.swift`

A bearer-authenticated client in the shape of `AccountSessionService` /
`URLSessionAccountSyncTransport`: injectable `URLSession` and base URL, reads the
token from `AccountSessionStore`, best-effort throughout (any failure leaves the
feature simply unavailable rather than erroring the app). Methods: `profile()`,
`updateProfile(displayName:)`, `regenerateFriendCode()`, `lookup(code:)`,
`requestFriend(userID:)`, `respond(to:accept:)`, `removeFriend(userID:)`,
`friends()`, `feed()`, `publish(_ activity: FriendActivity)`, `cheer(userID:date:)`,
`purgeSocialData()`.

**New test**: `Tests/AppCoreTests/SocialClientTests.swift` — a stub transport
asserts the `Authorization: Bearer …` header is attached, that a missing token
short-circuits without a request, and that non-200s degrade quietly.

### 3. Social store (observable state + scenario seeding)

**New file**: `Sources/AppCore/Social/SocialStore.swift`

`ObservableObject` holding `@Published` `profile`, `friends`, `requests`, `feed`,
and a `loadState` (`idle` / `loading` / `loaded` / `unavailable`). Mirrors
`SeededHealthDataSource`: when a scenario has seeded `rb*` keys
(`HealthSource.isScenarioSeeded()`), it hydrates from
`rbSocialFeedJSON`, `rbSocialFriendsJSON`, `rbSocialRequestsJSON`,
`rbSocialProfileJSON`, and `rbSocialState` and **never touches the network**, so
captures stay offline and deterministic. Otherwise it drives `SocialClient`.

Explicitly seed the "off" value for every social key in scenarios that don't use
them — the bleed-proofing rule this repo already follows for `rb*` seeds.

### 4. Friends tab + screens

**File**: `Sources/AppCore/ContentView.swift`

Add `case friends` to `MainTab` (line 216) and a third tab item. `rbStartTab="friends"`
already routes through `MainTab(raw:)`, so scenarios can land on it with no new
plumbing. Update `Tests/AppCoreTests/MainTabTests.swift` for the new case.

**New files** under `Sources/AppCore/Social/`:

- `FriendsView.swift` — screen root: requests section (when any), then the
  day-grouped feed; `.refreshable`; "Add friend" button in the header. Follows
  the `ActivityHistoryView` composition style — arrange components, no logic.
- `FriendsHeader.swift` — title + add-friend affordance, styled like
  `ActivityHistoryHeader`.
- `FriendActivityCard.swift` — one friend's day: name, a compact step-vs-goal
  ring or bar, Buddy mood chip (reuse `MoodChip`), latest workout line (reuse
  `WorkoutCard`'s formatting idiom), and the cheer button.
- `CheerButton.swift` — 🐾 toggle; optimistic local state, reverts on failure.
- `FriendRequestRow.swift` — incoming request with Accept / Decline.
- `AddFriendSheet.swift` — enter/paste a friend code, live-validated via
  `FriendCode.isValid`, showing the matched profile before you send. Also shows
  **your** code with a share action.
- `FriendsEmptyState.swift` — the day-one state: Buddy plus "Running's better
  with company" and the add-friend CTA.
- `FriendsLockedState.swift` — shown when social is off or the user isn't signed
  in; explains what gets shared and links to Settings. Modeled on
  `AskCoachLockedState.swift`, which solves the exact same "feature needs a
  thing you haven't turned on" problem.

All screens read `Palette` / `Typography` / `Layout` tokens so they retint across
the five themes, and scale with Dynamic Type.

### 5. Settings — Friends & sharing

**File**: `Sources/AppCore/SettingsView.swift`

A new card between Account and AI Coach, built from the existing `card(...)` /
`actionRow(...)` helpers:

- Master **"Share my activity with friends"** toggle, gated by the consent sheet
  (reuse the health-consent sheet pattern at lines ~259–346, including the
  "what's shared / what isn't" copy).
- Your display name (editable) and friend code, with **Copy** and **Regenerate**.
- **Manage friends** row → the friends list with remove.
- **"Turn off & delete shared data"** destructive action calling
  `SocialClient.purgeSocialData()`, matching the health-sync disable dialog.
- Account deletion (line ~151) must also purge social rows — extend the existing
  `purgeOnAccountDeletion` path so the App Store deletion requirement still holds.

### 6. Consent flags

**File**: `Sources/AppCore/Account/SyncConsent.swift`

Add `socialSharingEnabled` (key `otterpaceSocialSharingEnabled`) and
`socialConsentAcknowledged` (key `otterpaceSocialConsentAcknowledged`), plus
`acknowledgeSocialConsent()` and a `setSocialSharingEnabled(_:)` that no-ops
unless consent was acknowledged — the same `@discardableResult` guard the health
flag uses. Extend `Tests/AppCoreTests/AccountSyncTests.swift`.

### 7. Backend — one catch-all function

**New file**: `api/social/[...route].ts`

Single Vercel handler, `requireUser` first on every path, dispatching on the
route segment:

| Route | Methods | Behavior |
|---|---|---|
| `profile` | GET, PUT | own profile; PUT sets display name / regenerates code |
| `lookup` | GET `?code=` | exact friend-code match → minimal public profile |
| `requests` | GET, POST, PATCH | list incoming/outgoing; send; accept/decline |
| `friends` | GET, DELETE | accepted list; remove (both directions) |
| `share` | PUT | publish own redacted daily card |
| `feed` | GET | accepted friends' latest cards + my cheer state |
| `cheer` | POST | idempotent 🐾 for (friend, date) |
| `purge` | DELETE | delete this user's profile, friendships, shares, cheers |

Rate-limit writes with the existing `api/_lib/ratelimit.ts`; friend-code lookup
especially, so codes can't be brute-forced.

**New file**: `api/_lib/social.ts`

Supabase PostgREST helpers via `env()` / `supabaseHeaders()` from
`api/_lib/strava.js` (the established no-SDK pattern), plus the pure logic that
carries the tests:

- `normalizePair(a, b)` — canonical ordering so a friendship is one row, not two,
  and `(a,b)` can't duplicate `(b,a)`.
- `sanitizeShare(payload)` — allowlist the five permitted keys, drop everything
  else, bound the payload size (mirrors `MAX_PREFS_BYTES`).
- `generateFriendCode()` — `randomBytes`-backed, ambiguity-free alphabet
  (no `0`/`O`/`1`/`I`).
- `canSee(viewerId, ownerId, friendships)` — the authorization predicate every
  feed read goes through.

New Supabase tables, documented in the file header the way `api/_lib/account.ts`
documents its own (create-once DDL in a comment):
`social_profiles`, `social_friendships` (with a `status` check constraint and a
unique index on the normalized pair), `social_shares`, `social_cheers` (unique on
`from_user, to_user, share_date` for idempotency).

**New test**: `test/api/social.test.ts` — pair normalization, share sanitization
(assert a payload carrying `workouts` or `dailySteps` is stripped), code
generation shape, `canSee` rejecting non-friends and pending requests, cheer
idempotency, and 401 on every route without a bearer.

### 8. Analytics + docs

- `Analytics.shared.capture` events: `social_enabled`, `friend_request_sent`,
  `friend_request_accepted`, `cheer_sent`, `social_disabled`. Counts only — no
  friend ids, no payloads (consistent with the existing analytics posture).
- **File**: `site/privacy.html` — a short "Friends (optional)" section stating
  exactly what a friend can see, that it's off by default, and that it's
  deletable. The privacy page currently promises health data is never
  transmitted; that sentence needs the "unless you turn on friends" qualifier or
  it becomes inaccurate the day this ships. **This is a shipping blocker, not a
  nice-to-have.**
- **New file**: `docs/social.md` — table DDL, endpoint contract, and the
  redaction guarantee, matching `docs/account-sync.md`.

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
- `MoodChip` (`Sources/AppCore/MoodChip.swift`) and the `WorkoutCard`
  (`Sources/AppCore/WorkoutCard.swift`) formatting idiom — reused in the feed card.
- `AskCoachLockedState` (`Sources/AppCore/AskCoachLockedState.swift`) — the
  template for `FriendsLockedState`.
- `ActivityHistoryView` / `ActivityHistoryHeader` — the screen composition style
  the Friends screens follow.
- `HealthSource.isScenarioSeeded()` (`Sources/AppCore/Health/HealthDataSource.swift`)
  — the offline/deterministic gate for `SocialStore`.
- `MainTab` (`Sources/AppCore/ContentView.swift:216`) + `MainTabTests` — the tab
  enum and its `rbStartTab` seed path.
- `api/_lib/ratelimit.ts` — write + lookup throttling.
- `prefsContainHealthFields` (`api/_lib/account.ts`) — the defense-in-depth
  precedent `sanitizeShare` follows.

## Scenarios to Demonstrate

- **Friends feed — an active day**: three friends, one over goal with a 6-mile
  run, one mid-day, one rested; mixed Buddy moods; one already cheered.
- **Friends — day one empty**: social on, zero friends → Buddy empty state + CTA.
- **Friends — locked**: not signed in / sharing off → the locked explainer.
- **Incoming friend request**: one pending request above a two-friend feed,
  Accept / Decline visible.
- **Add friend sheet — matched**: a valid pasted code resolving to a profile,
  ready to send.
- **Add friend sheet — invalid code**: inline validation error, send disabled.
- **Cheer sent**: the same feed card before and after the 🐾, cheer count moving
  0 → 1.
- **Settings — Friends & sharing on**: consent acknowledged, friend code visible,
  destructive "turn off & delete" present.
- **Social consent sheet**: the one-time "here's exactly what friends see"
  explainer.
- **Feed with a long name + large text**: `rbContentSize="accessibility3"` over a
  long display name and a 13.1-mile workout line — the truncation/wrap edge case.
- **Friends feed — Bolt theme** (and one more, e.g. Garden): confirms the new
  screens retint with the five-theme system.
