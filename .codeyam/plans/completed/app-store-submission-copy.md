---
title: "App Store Submission Copy (post-plans v1, analytics-off)"
mode: ui
createdAt: "2026-07-08T21:00:00Z"
source: manual
---

## Summary

Refresh the App Store listing copy so it matches the **post-plans, analytics-off
v1** app, and give paste-ready values for every field on the App Store Connect
**1.0 Prepare for Submission** screen. The current source of truth
(`docs/app-store-listing.md`) is stale on two fronts: (1) it was written for the
"analytics is on" posture and explicitly avoids any no-tracking claim, but v1 ships
with `PostHogProjectKey` empty (analytics off), `StravaClientID` empty (Strava
hidden), and HealthKit read on-device only — confirmed in `App/Info.plist`; and (2)
its Description predates several shipped features — **races & race-goal coaching**
(build/taper/race-day + import-race-by-URL / search-by-name), **custom step goal**,
**optional Apple sign-in + cross-device sync**, and the retuned human coach voice.
This plan rewrites `docs/app-store-listing.md` to the accurate v1 state and embeds
the exact field-by-field ASC copy so submission is copy-paste. Per the user's
decisions: **privacy is mentioned, not the headline** (coaching features lead), and
**Support/Marketing = `https://otterpace.com`** with **Privacy Policy =
`https://otterpace.com/privacy`**. This is a **doc-only** change — no Swift/API
source touched. It is the copy source that the queued `app-store-submission` runbook
plan pastes from, so refreshing it here keeps that runbook accurate.

## Key Decisions

- **Copy reflects the real v1 shipping state (analytics off, Strava hidden).**
  Because `PostHogProjectKey` and `StravaClientID` are both empty in
  `App/Info.plist`, a privacy note is now truthful: no tracking/analytics, no
  account required, Health stays on-device. The stale header in the listing doc
  ("analytics is on, so nothing here claims 'no tracking'") is removed. This aligns
  with the `app-store-submission` plan's **Data Not Collected** privacy-label
  decision, so the two docs stop contradicting each other.
- **Privacy is mentioned, not led (per user).** The subtitle and the top of the
  Description lead with Buddy and the coaching features; the privacy story is one
  clear paragraph/bullet near the end rather than the headline.
- **Description updated to the post-plans feature set.** Add races/race-goal
  coaching (import-by-URL / search-by-name), custom step goal, and optional
  sign-in-with-Apple sync; keep it truthful about the BYO-key coach ("built-in
  coach works with no key"). Reflects `race-goals-coaching`,
  `persist-and-import-races`, `custom-step-goal`, `dogfood-account-data-sync`,
  and `human-coach-voice`.
- **URLs (per user):** Marketing URL `https://otterpace.com`, Support URL
  `https://otterpace.com`, Privacy Policy URL `https://otterpace.com/privacy`
  (matches `site/privacy.html`). Support URL must resolve when a reviewer clicks it.
- **Release + review-safety carried over.** Auto-release on approval; App Review
  Notes pre-empt the three Otterpace-specific rejection triggers (BYO-key coach,
  optional sign-in / no demo account, sparse HealthKit on a fresh device) —
  consistent with the `app-store-submission` runbook.
- **Doc-only, no source changes.** Constrained-file pre-check on
  `docs/app-store-listing.md` returned none. Analytics stays off for v1
  (`Info.plist` untouched).

## Implementation

### 1. Rewrite the listing copy for the post-plans, analytics-off v1

**File**: `docs/app-store-listing.md`

- Remove the stale intro line about analytics being on / avoiding no-tracking
  claims. Replace with a one-line note that v1 ships analytics-off + Strava-hidden,
  so a truthful privacy mention is included (kept as a bullet, not the lead).
- Update the **Privacy "nutrition label"** section to the v1 answer: **Data Not
  Collected** (analytics off, Strava hidden, Health on-device), pointing to the
  `app-store-submission` runbook for the full label flow; keep the Usage-Data
  mapping as the "if analytics is enabled later" branch so nothing is lost.
- Update **URLs & metadata**: Support `https://otterpace.com`, Marketing
  `https://otterpace.com`, Privacy `https://otterpace.com/privacy`, Copyright
  `2026 Otterpace`, Primary category Health & Fitness, Age rating 4+.
- Replace the **Promotional text**, **Keywords**, and **Description** with the
  post-plans copy below.
- Add an **App Review Notes** block (currently only referenced by the runbook) so
  the exact reviewer-notes text lives with the rest of the copy.

### 2. Ready-to-paste App Store Connect field values

These are the exact values for the fields visible on the **1.0 Prepare for
Submission** screen. Embed them verbatim in `docs/app-store-listing.md` and paste
into ASC.

**Subtitle** (≤30):
```
Your friendly running coach
```

**Promotional Text** (≤170):
```
Meet Buddy, your friendly running coach. Daily nudges to your step goal, smart run/rest tips, race-day guidance, and a kind weekly review. No account needed.
```

**Keywords** (≤100, comma-separated, no spaces; "running"/"coach" omitted — Apple
indexes name/subtitle words automatically):
```
run,steps,fitness,jog,training,5k,10k,walk,marathon,race,pace,habit,rest,goal,tracker,health
```

**Description** (≤4000):
```
Meet Buddy, your friendly running coach. 🐾

Otterpace turns daily movement into steady, guilt-free progress. Buddy reads your activity from Apple Health and gives simple, encouraging guidance every day. No pressure, no guilt, just a coach in your corner.

• Daily step goal: a clean dashboard for steps, distance, and active minutes. Pick a preset or set any custom target.
• Ask Buddy: quick, practical answers like "Run or rest today?" in a real coach's voice.
• Smart run/rest tips: Buddy eases off when your training load spikes, and nudges you when you've been still too long.
• Training for a race? Add it and Buddy makes coaching goal-aware: build early, taper near race day, and check in after. Import a race from a link or search by name.
• Weekly review: what went well, and one focus for next week.
• Activity history: your recent runs and walks, week by week.
• Gentle reminders: optional nudges to move, on your schedule.

Private by design: your Apple Health data stays on your device and is never uploaded. No account is required to use Otterpace. Sign in with Apple only if you want your goal and preferences to sync across devices. Otterpace is open source.

Optional: connect your own AI key for richer, conversational coaching, or use the built-in coach offline. No key required.

Otterpace offers general fitness guidance, not medical advice.
```

**Support URL**: `https://otterpace.com`
**Marketing URL**: `https://otterpace.com`
**Privacy Policy URL**: `https://otterpace.com/privacy`
**Version**: `1.0`
**Copyright** (≤200):
```
2026 Otterpace
```

**App Review Information → Notes** (≤4000):
```
Otterpace is a personal running and step coach. Notes to make review smooth:

• No demo account needed. Sign in with Apple is optional; the app is fully usable signed out, so you can exercise every feature without signing in. (Signing in only syncs the step goal and preferences across devices.)

• The AI coach works with no key. "Ask Buddy" answers using a built-in, on-device coach that needs no setup and no API key. The "connect your own AI key" field in Settings is optional and only enhances replies. Leave it empty to review.

• Health data may be empty on a fresh device. Otterpace reads steps, distance, and active minutes from Apple Health on-device (nothing is uploaded). On a new review device Health may have little or no data, so the dashboard can look sparse. Please grant the Health permission when prompted; values populate from the device's own Health data. The screenshots show the populated states.

• No tracking or analytics in this version, and Strava import is intentionally hidden this release.

Contact: Nadia Eldeib, nseldeib@gmail.com.
```

**Sign-In Information**: leave **"Sign-in required" unchecked** — the app is fully
usable signed out, so no username/password is provided.

**App Store Version Release**: select **Automatically release this version** (auto
on approval). Manual release is the one-line alternative.

### 3. Screenshots (already 6 of 10 uploaded on the 6.5" slot)

Upload the committed 6-shot set (`appstore/screenshots/6.5-inch/`, 1284×2778) in
this order — the first 3 show on the install sheet:

1. `01-today-goal-crushed.png` — Today dashboard, goal crushed
2. `02-ask-coach-knee-pain.png` — injury-aware "Safety First" coaching
3. `03-weekly-review-solid-week.png` — Weekly Review
4. `04-welcome-meet-buddy.png` — Meet Buddy onboarding
5. `05-today-fresh-start.png` — day-one dashboard
6. `06-settings.png` — Settings (privacy / BYO key)

**Verify** ASC still accepts the 6.5" set alone before submitting; if it now
requires 6.9", recapture at 1320×2868 (iPhone 16 Pro Max sim) per the note in the
listing doc.

## Reused existing code

- `docs/app-store-listing.md` — the metadata source of truth being refreshed (its
  "analytics on" framing is superseded for the analytics-off v1).
- `.codeyam/plans/app-store-submission.md` (queued runbook) — pastes from the
  listing doc; this plan keeps that copy accurate. No overlap: that plan owns the
  ASC **portal flow**, this plan owns the **copy**.
- `App/Info.plist` — read-only confirmation of the v1 shipping state
  (`PostHogProjectKey` empty, `StravaClientID` empty,
  `ITSAppUsesNonExemptEncryption = NO`); not modified.
- `site/privacy.html` — the live Privacy Policy the `https://otterpace.com/privacy`
  URL points at.
- `appstore/screenshots/6.5-inch/*.png` — the committed six-shot 1284×2778 set,
  uploaded in the documented order.
- Completed feature plans reflected in the new Description: `race-goals-coaching`,
  `persist-and-import-races`, `custom-step-goal`, `dogfood-account-data-sync`,
  `human-coach-voice`.

## Scenarios to Demonstrate

Doc-only change (no app UI surface), so no codeyam UI scenarios. Verifiable
outcomes:

- `docs/app-store-listing.md` no longer claims analytics is on; the privacy label
  section reads **Data Not Collected** for v1.
- The Description names races/race-goal coaching, custom step goal, and optional
  sign-in sync, and stays under 4000 chars.
- Promotional Text ≤170, Keywords ≤100, Copyright ≤200 — all within limits.
- Every field on the ASC 1.0 screen (Promotional Text, Description, Keywords,
  Support/Marketing URLs, Version, Copyright, App Review Notes, Sign-In, Release)
  has a ready-to-paste value in the doc.
