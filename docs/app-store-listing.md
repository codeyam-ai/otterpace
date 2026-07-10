# Otterpace App Store listing copy (v1 — post-plans, analytics-off)

Drop-in metadata for App Store Connect, refreshed to match the **v1 shipping
state**. This build ships **analytics off** (`PostHogProjectKey` empty) and
**Strava import hidden** (`StravaClientID` empty) — confirmed in `App/Info.plist`
— and reads Apple Health on-device only. Because nothing is tracked or uploaded,
a truthful privacy note is included below; per the product call it is **mentioned,
not the headline** (coaching features lead).

The exact, paste-ready values for every field on the App Store Connect **1.0
Prepare for Submission** screen are collected in the
[Ready-to-paste ASC fields](#ready-to-paste-asc-fields-10-prepare-for-submission)
section. This doc is the copy source that the `app-store-submission` runbook plan
pastes from.

---

## Name & subtitle
- **App Name** (≤30): `Otterpace`
  - Alt if you want the descriptor in the name: `Otterpace: Running Coach` (24).
  - ⚠️ The name must be unique on the App Store; check availability when you
    create the app record.
- **Subtitle** (≤30): `Your friendly running coach` (27)
  - Alt: `Your daily running coach` (24)

## URLs & metadata
- **Privacy Policy URL**: `https://otterpace.com/privacy` (matches `site/privacy.html`)
- **Support URL**: `https://otterpace.com` (must resolve when a reviewer clicks it)
- **Marketing URL**: `https://otterpace.com`
- **Primary category**: Health & Fitness · **Secondary**: Lifestyle
- **Age rating**: no objectionable content. On Apple's 2025+ questionnaire answer
  **Health or Wellness Topics = Yes** (self-care/lifestyle recs), **Medical or
  Treatment-Focused = No** ("not medical advice"); resulting rating may be 4+ to
  12+ — take whatever ASC computes. **For the v1 submission ASC returned 9+.**
- **Version**: `1.0`
- **Copyright**: `2026 Nadia Eldeib`

## Privacy "nutrition label" (App Privacy section)
For **v1**, the answer is **Data Not Collected**: analytics is off, Strava import
is hidden, and Apple Health data is read on-device only (it never leaves the
device, so it is not "collected" in App Store terms). See the
`app-store-submission` runbook plan for the full label-completion flow; the two
docs agree on **Data Not Collected** for this release.

> If analytics is enabled in a later release, the mapping becomes (kept here so
> nothing is lost — see `docs/strava-and-analytics.md` for the full version):
> - **Usage Data → Product Interaction**: collected, *not linked* to identity,
>   for Analytics / App Functionality (PostHog).
> - **Identifiers**: anonymous analytics/device id, not linked to the user.
> - Apple Health data read on-device is still **not** "collected"; declare only
>   data your backend actually receives.
> - Strava import stays hidden in v1 (`StravaClientID` empty in `App/Info.plist`),
>   so there is no Strava activity data to declare this release.

---

## Ready-to-paste ASC fields (1.0 Prepare for Submission)

Paste each value verbatim into the matching field on the App Store Connect 1.0
screen.

**Subtitle** (≤30):
```
Your friendly running coach
```

**Promotional Text** (≤170, editable anytime without review):
```
Meet Buddy, your friendly running coach. Daily nudges to your step goal, smart run/rest tips, race-day guidance, and a kind weekly review. No account needed.
```

**Keywords** (≤100, comma-separated, no spaces; "running"/"coach" omitted — Apple
indexes name/subtitle words automatically):
```
run,steps,fitness,jog,training,5k,10k,walk,marathon,race,pace,habit,rest,goal,tracker,health
```

**Description** (≤4000):

> ⚠️ **No emoji in this field.** App Store Connect rejects emoji in the Description
> with "This field contains one or more invalid characters." Bullets (`•`, U+2022)
> are fine and intentional. (Emoji are OK in Promotional Text and What's New.)

```
Meet Buddy, your friendly running coach.

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
2026 Nadia Eldeib
```
> No incorporated "Otterpace" entity exists yet, so the exclusive rights are held
> by the individual. Rights may later be assigned to CodeYam; update this field if
> that happens.

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

## What's New (version 1.0)
```
First release: meet Buddy, your friendly running coach. Daily step goal, Ask Buddy chat, smart run/rest tips, race-goal coaching, weekly review, activity history, and gentle reminders.
```

## Screenshots (raw 6.5" set, captured and ready to upload)
A 6-shot raw set is committed at `appstore/screenshots/6.5-inch/` (1284×2778,
the size App Store Connect's 6.5" slot accepts; ASC reuses one set for all
display sizes). Captured from the seeded CodeYam scenarios on an iPhone 13 Pro
Max simulator with a clean 9:41 status bar. Upload order (first 3 show on the
install sheet):
1. `01-today-goal-crushed.png`: Today dashboard, goal crushed
2. `02-ask-coach-knee-pain.png`: injury-aware "Safety First" coaching
3. `03-weekly-review-solid-week.png`: Weekly Review
4. `04-welcome-meet-buddy.png`: Meet Buddy onboarding
5. `05-today-fresh-start.png`: day-one dashboard
6. `06-settings.png`: Settings (privacy / BYO key)

**Verify** ASC still accepts the 6.5" set alone before submitting; if it now
requires 6.9", recapture at 1320×2868 on an iPhone 16 Pro Max sim. Regenerate
with `scratchpad/appstore-capture.mjs`.
