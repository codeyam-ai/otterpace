# Otterpace — App Store listing copy (draft)

Drop-in metadata for App Store Connect. Char limits noted; the copy is written to
stay truthful to the (updated) privacy posture — health data stays on-device, but
analytics is on, so nothing here claims "no tracking."

---

## Name & subtitle
- **App Name** (≤30): `Otterpace`
  - Alt if you want the descriptor in the name: `Otterpace: Running Coach` (24).
  - ⚠️ The name must be unique on the App Store — check availability when you
    create the app record.
- **Subtitle** (≤30): `Your friendly AI running coach` (30)
  - Alt: `Injury-aware AI run coach` (25)

## Promotional text (≤170, editable anytime without review)
```
Meet Buddy, your injury-aware otter running coach. Gentle daily nudges toward your step goal, smart run/rest guidance, and a weekly review — never shame, always kind.
```

## Keywords (≤100 chars, comma-separated, no spaces, singular)
Don't repeat words already in the name/subtitle ("running", "coach") — Apple
indexes those automatically. Candidate (95 chars):
```
run,steps,counter,fitness,jog,jogging,training,5k,10k,walk,marathon,health,pace,habit,rest
```

## Description (≤4000)
```
Meet Buddy — your friendly AI running coach. 🐾

Otterpace helps you build a running and movement habit without the guilt. Buddy, your mood-reactive otter coach, reads your activity from Apple Health and gives practical, injury-aware guidance every day — never shame, always encouragement.

WHAT BUDDY DOES
• Daily step goal — a clean dashboard tracks your steps, distance, and active minutes toward a goal you set.
• Injury-aware coaching — clear run/rest advice that eases off when your training load spikes. No diagnoses, just sensible, conservative guidance.
• Ask Buddy anything — "Can I run or should I rest?", "Am I ramping up too fast?", "My knee hurts after my run." Get a kind, practical answer tuned to your week.
• Weekly review — what went well, what changed, your mileage, and one focus for next week.
• Activity history — recent runs and walks, grouped by week.
• Gentle reminders — optional nudges to move, on your schedule.

YOUR HEALTH DATA STAYS ON YOUR DEVICE
Apple Health data is read on your device and is never uploaded. No account is required to start. Otterpace is open source, so you can read exactly what it does.

BRING YOUR OWN AI (OPTIONAL)
Connect your own AI key for real, conversational coaching — or use the built-in coach, which works offline either way.

Otterpace offers general fitness guidance, not medical advice. If you're in pain or have a medical condition, please talk to a clinician.
```

## What's New (version 1.0)
```
First release! Meet Buddy, your injury-aware AI running coach: a daily step-goal dashboard, smart run/rest coaching, the Ask Buddy chat, a weekly review, activity history, and gentle movement reminders.
```

## URLs & metadata
- **Privacy Policy URL**: `https://otterpace.com/privacy`
- **Support URL**: `https://otterpace.com` (add a `/support` page later if you want)
- **Marketing URL**: `https://otterpace.com`
- **Primary category**: Health & Fitness · **Secondary**: Lifestyle
- **Age rating**: 4+ (no objectionable content)
- **Copyright**: `2026 Otterpace`

## Privacy "nutrition label" (App Privacy section)
Must be completed before external testing / release — see
`docs/strava-and-analytics.md` for the full mapping. In short:
- **Usage Data → Product Interaction** — collected, *not linked* to identity,
  for Analytics / App Functionality (PostHog).
- **Identifiers** — anonymous analytics/device id, not linked to the user.
- Apple Health data read on-device is **not** "collected" in App Store terms
  (it never leaves the device) — but declare any data your backend receives.
- (Strava import is hidden in v1, so there's no Strava activity data to declare
  this release — see the StravaClientID note in `App/Info.plist`.)

## Screenshots (raw 6.5" set — captured, ready to upload)
A 6-shot raw set is committed at `appstore/screenshots/6.5-inch/` (1284×2778,
the size App Store Connect's 6.5" slot accepts; ASC reuses one set for all
display sizes). Captured from the seeded CodeYam scenarios on an iPhone 13 Pro
Max simulator with a clean 9:41 status bar. Upload order (first 3 show on the
install sheet):
1. `01-today-goal-crushed.png` — Today dashboard, goal crushed
2. `02-ask-coach-knee-pain.png` — injury-aware "Safety First" coaching
3. `03-weekly-review-solid-week.png` — Weekly Review
4. `04-welcome-meet-buddy.png` — Meet Buddy onboarding
5. `05-today-fresh-start.png` — day-one dashboard
6. `06-settings.png` — Settings (privacy / BYO key)

Regenerate with `scratchpad/appstore-capture.mjs` (or re-capture at 6.9"
1320×2868 on an iPhone 16 Pro Max sim if you later want the larger size too).
```
