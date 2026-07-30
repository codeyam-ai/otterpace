---
title: "Social — The Friends Feed and Cheers"
mode: ui
createdAt: "2026-07-30T19:08:00Z"
source: manual
order: 6
dependsOn: ["social-foundation"]
---

## Summary

The visible half of the social layer: a **Friends** tab showing a day-grouped feed
of what your friends did, and a 🐾 **cheer** you can send on someone's day. It
builds entirely on `social-foundation` — the models, redaction guarantee, client,
consent flags, and backend catch-all all exist before this plan starts; this adds
two endpoints (`feed`, `cheer`), the tab, and the screens.

The design bar here is higher than anywhere else in the app. A friends feed has
strong default gravity toward looking like a generic social product, which is the
opposite of what Otterpace is. The feed card is the surface most worth a design
exploration pass before implementation — see the note below.

## Key Decisions

- **The Friends tab is hidden until social is on.** This reverses the original
  plan, which added a permanent third tab showing a locked state to everyone. That
  taxes every solo user — the large majority — with a dead destination in order to
  advertise a feature they've declined, and it makes the app feel like it wants
  something from you. Instead `MainTab.friends` exists in the enum but the tab is
  **conditionally rendered** on `socialSharingEnabled`. Discovery lives in the
  Settings card that `social-foundation` already built. Turning social on adds the
  tab; turning it off removes it and returns you to Today.

- **Cheers are the only interaction, and they're one-way and positive.** No
  comments, no likes-with-a-count-to-chase, no leaderboard, no ranking of friends
  against each other. A cheer is one 🐾 per friend per day, idempotent server-side.
  This keeps the moderation surface minimal, which is the only responsible shape
  for a v1 social feature in a wellness app — and it matches Buddy's
  never-shame-based voice. A feed that can make you feel behind is a failed feed.

- **The feed never ranks or compares.** Sorted by date then name, never by step
  count, never with a "you're 3rd this week" framing. `SocialFeed.sort` from the
  foundation plan already encodes this; the UI must not re-sort. Worth stating
  explicitly because a step-count feed is one careless `sorted(by:)` away from
  becoming a leaderboard.

- **Reporting ships here, because this is where a name becomes visible.** The
  foundation plan bounds display names and makes friendship mutual-consent; this
  plan adds the user-facing **Report** action on a friend, alongside Remove. That
  completes the App Review UGC requirements (bounded content, block/remove, report
  path) at the moment the content first appears on screen.

- **Feed is pull-on-appear, not push.** No new APNs work in this plan; the feed
  refreshes when the Friends tab appears and on pull-to-refresh, reusing the
  `.refreshable` pattern from `TodayDashboard`. Push notifications for cheers are
  a deliberate follow-up (the `PushRegistrationService` seam already exists), and
  should be weighed against the nudge-volume concerns in
  `nudges-correctness-then-customization` before being added.

- **Run a design pass on the feed card before building it.** `FriendActivityCard`
  is the one new surface where "reads the theme tokens" is not a sufficient
  specification — token compliance guarantees consistency, not quality. Generate
  mockups (`/codeyam-design`) for the card and the day-grouped feed, pick a
  direction, then implement. This is the highest-visibility new screen in the app
  and the one most likely to drift toward generic.

## Implementation

### 1. The tab

**File**: `Sources/AppCore/ContentView.swift`

Add `case friends` to `MainTab` (line 216, currently `case today, coach`) and
render the third tab item **only** when `SyncConsentStore.socialSharingEnabled` is
true. `rbStartTab="friends"` already routes through `MainTab(raw:)`, so scenarios
can land on it with no new plumbing — but a scenario targeting the Friends tab
must **also** seed the social-enabled flag, or the tab won't exist and the capture
silently lands on Today. Call this out in the scenario seeds; it is exactly the
index-drift failure mode this repo has hit before.

Update `Tests/AppCoreTests/MainTabTests.swift` for the new case, including that
`MainTab(raw: "friends")` still resolves when the tab is hidden (the enum and the
visibility are separate concerns).

### 2. Feed screens

**New files** under `Sources/AppCore/Social/`:

- `FriendsView.swift` — screen root: requests section (when any), then the
  day-grouped feed; `.refreshable`; "Add friend" in the header. Follows the
  `ActivityHistoryView` composition style — arrange components, no logic.
- `FriendsHeader.swift` — title + add-friend affordance, styled like
  `ActivityHistoryHeader`.
- `FriendActivityCard.swift` — one friend's day: name, a compact step-vs-goal
  ring or bar, Buddy mood chip (reuse `MoodChip`), latest workout line (reuse
  `WorkoutCard`'s formatting idiom), and the cheer button. **Design-pass output
  lands here.**
- `CheerButton.swift` — 🐾 toggle; optimistic local state, reverts on failure.
- `FriendsEmptyState.swift` — the day-one state: Buddy plus "Running's better
  with company" and the add-friend CTA.

All read `Palette` / `Typography` / `Layout` tokens so they retint across the five
themes, and scale with Dynamic Type. No `FriendsLockedState` is needed — the tab
is absent rather than locked.

### 3. Report + remove

**File**: `Sources/AppCore/Social/FriendActivityCard.swift` (context menu) and
`FriendListView.swift` (from the foundation plan)

A **Report** action alongside Remove. Reporting removes the friendship
immediately (the user should never have to keep seeing someone to report them)
and posts to a `report` route. Keep the confirmation copy plain and
non-dramatic.

### 4. Backend — two more routes

**File**: `api/social/[...route].ts` (created by the foundation plan)

Add to the dispatch:

| Route | Methods | Behavior |
|---|---|---|
| `feed` | GET | accepted friends' latest cards + my cheer state |
| `cheer` | POST | idempotent 🐾 for (friend, date) |
| `report` | POST | record a report, sever the friendship |

`feed` runs every row through `canSee` from `api/_lib/social.ts`. `cheer` relies
on the `social_cheers` unique constraint the foundation plan created for
idempotency — a duplicate is a 200, not a 409, so a double-tap is harmless.

**File**: `api/_lib/social.ts` — add `buildFeed(viewerId, shares, friendships, cheers)`
as a pure function so feed assembly and cheer-state resolution are unit-testable
without Supabase.

**File**: `test/api/social.test.ts` — extend: feed excludes non-friends and
pending requests, cheer is idempotent, cheer on a non-friend is rejected, report
severs the friendship, and 401 without a bearer on all three new routes.

### 5. Publish on change

**File**: `Sources/AppCore/Model.swift` / wherever `TodayState` is republished

When social is enabled, publish the redacted card via
`SocialClient.publish(SocialShare.redact(today))` on meaningful change (debounced
— not on every step-count tick). When social is off, never call it. Add a test
asserting the no-publish-when-off path, since that is the privacy-relevant
branch.

## Reused existing code

- Everything from `social-foundation`: `SocialModels`, `SocialShare.redact`,
  `SocialFeed.sort` / `groupByDay`, `SocialClient`, `SocialStore`,
  `api/social/[...route].ts`, `api/_lib/social.ts`, the consent flags, and the
  Settings card.
- `MainTab` (`Sources/AppCore/ContentView.swift:216`) + `MainTabTests` — the tab
  enum and its `rbStartTab` seed path.
- `MoodChip` (`Sources/AppCore/MoodChip.swift`) and the `WorkoutCard`
  (`Sources/AppCore/WorkoutCard.swift`) formatting idiom — reused in the feed card.
- `ActivityHistoryView` / `ActivityHistoryHeader` — the screen composition style
  the Friends screens follow.
- The `.refreshable` pattern from `TodayDashboard`.
- `Analytics.shared.capture` — add `cheer_sent`, `friend_reported`. Counts only.

## Scenarios to Demonstrate

*(Every Friends-tab scenario must seed both `rbStartTab="friends"` **and** the
social-enabled flag — see the tab note above.)*

- **Friends feed — an active day**: three friends, one over goal with a 6-mile
  run, one mid-day, one rested; mixed Buddy moods; one already cheered.
- **Friends feed — day one empty**: social on, zero friends → Buddy empty state
  and CTA.
- **Cheer sent**: the same feed card before and after the 🐾, count 0 → 1.
- **Feed with a long name + large text**: `rbContentSize="accessibility3"` over a
  24-character display name and a 13.1-mile workout line — the truncation case.
- **Feed with one friend who did nothing today**: the rest-day card, which must
  read as neutral and fine, never as a gap or a failure. This is the scenario
  that proves the no-shame decision held.
- **Report confirmation**: the plain, non-dramatic confirm copy.
- **Today tab with social off**: no Friends tab present — the solo-mode
  regression guard, and the visible proof of the hidden-tab decision.
- **Today tab with social on**: three tabs, Friends reachable.
- **Friends feed — Bolt theme** (and one more, e.g. Garden): the new screens
  retint across the five-theme system.
