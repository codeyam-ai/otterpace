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
  - ⚠️ **Include the subtitle this time** — it was accidentally omitted at the 1.0
    submission. Fill the Subtitle field on the 1.0.1 version.

## URLs & metadata
- **Privacy Policy URL**: `https://otterpace.com/privacy` (matches `site/privacy.html`)
- **Support URL**: `https://otterpace.com` (must resolve when a reviewer clicks it)
- **Marketing URL**: `https://otterpace.com`
- **Primary category**: Health & Fitness · **Secondary**: Lifestyle
- **Age rating**: no objectionable content. On Apple's 2025+ questionnaire answer
  **Health or Wellness Topics = Yes** (self-care/lifestyle recs), **Medical or
  Treatment-Focused = No** ("not medical advice"); resulting rating may be 4+ to
  12+ — take whatever ASC computes. **For the v1 submission ASC returned 9+.**
- **Version**: `1.0` is **live on the App Store**
  ([id6784287408](https://apps.apple.com/us/app/otterpace/id6784287408)). The
  **`1.0.1`** update (**build 6** — conversational coaching + five themes) is
  uploaded to TestFlight and submitted for external Beta App Review.
- **Copyright**: `2026 Nadia Eldeib`

## Privacy "nutrition label" (App Privacy section)
For **v1**, the answer is **Data Not Collected**: analytics is off, Strava import
is hidden, and Apple Health data is read on-device only (it never leaves the
device, so it is not "collected" in App Store terms). See the
`app-store-submission` runbook plan for the full label-completion flow; the two
docs agree on **Data Not Collected** for this release.

> **1.0.1 keeps Data Not Collected.** The theme feature stores the chosen look in
> on-device UserDefaults only, and its analytics events (`theme_changed`,
> `onboarding_theme_selected`) are no-ops while `PostHogProjectKey` is empty —
> nothing leaves the device. The conversational-coaching change also collects
> nothing new (BYO-key requests still go straight to Anthropic, never stored).

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
• Make it yours: choose from five app themes, from warm and friendly to dark and focused, in onboarding or Settings.

Private by design: your Apple Health data stays on your device and is never uploaded. No account is required to use Otterpace. Sign in with Apple only if you want your goal and preferences to sync across devices. Otterpace is open source.

Ask Buddy holds a real conversation now: it remembers what you already said and builds on it instead of repeating itself. Connect your own AI key for richer replies, or use the built-in coach offline. No key required.

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

## What's New (version 1.0.1 — the pending update, build 5)

> Submit this as a **1.0.1 update** once **1.0 is live** (App Store versions are
> sequential — you can't create 1.0.1 while 1.0 is still Waiting for Review).
> Attach **build 5**, which carries the conversational-coaching upgrade and the
> five-theme system. Metadata below is otherwise unchanged from 1.0 (subtitle now
> included — it was accidentally omitted at the 1.0 submission).

```
Buddy holds a real conversation now: Ask Buddy remembers what you already said and builds on it, gives calmer, more trusting guidance, and no longer over-flags rest. New: choose from five app themes — from warm and friendly to dark and focused — in onboarding or Settings. Plus fixes and polish.
```

## What's New (version 1.0 — first release, build 3)
```
First release: meet Buddy, your friendly running coach. Daily step goal, Ask Buddy chat, smart run/rest tips, race-goal coaching, weekly review, activity history, and gentle reminders.
```

## Screenshots

### For 1.0.1
The committed 6.5" set below (build 3, Default theme) **still represents the app**
— the core screens are unchanged — so 1.0.1 can ship with it unchanged if you want
to submit fast. But the update's two headline features are visual, so a refresh is
worth it when the capture pipeline is healthy:

- **Add a themes showcase** — the Settings › Appearance picker (all five looks), or
  a couple of themed Today screens (e.g. Bolt dark + Orbit) side by side. This is
  the single most valuable new shot.
- **Refresh Ask Coach** to a multi-turn exchange (shows the conversational upgrade).
- Keep the rest (Today, Weekly Review, onboarding, Settings).

**Capture caveat (blocked right now):** the editor's automated capture races the
coral LaunchScreen, so a clean set can't be regenerated reliably this session (see
the `theme-scenarios-need-recapture` note). The manual `simctl` fallback works but
the current sim is **iPhone 16 Pro (1206×2622)** — *not* an App Store size. Capture
the App-Store set on an **iPhone 16 Pro Max** sim at **1320×2868 (6.9")**, or the
legacy 6.5" **1284×2778** on an iPhone 11/13 Pro Max, with a clean 9:41 status bar.
Verify which display sizes ASC requires before uploading (it may now mandate 6.9").

### Existing committed set (6.5", 1284×2778, Default theme)
A 6-shot raw set is committed at `appstore/screenshots/6.5-inch/`. Upload order
(first 3 show on the install sheet):
1. `01-today-goal-crushed.png`: Today dashboard, goal crushed
2. `02-ask-coach-knee-pain.png`: "Safety First" coaching
3. `03-weekly-review-solid-week.png`: Weekly Review
4. `04-welcome-meet-buddy.png`: Meet Buddy onboarding
5. `05-today-fresh-start.png`: day-one dashboard
6. `06-settings.png`: Settings (privacy / BYO key)
