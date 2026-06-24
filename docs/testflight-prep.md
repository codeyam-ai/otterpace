# RunBuddy — TestFlight Prep Plan

A step-by-step checklist to get RunBuddy onto TestFlight. Most of this happens in
**Xcode** + **App Store Connect** (the archive/upload can't be done from the
codeyam CLI / simulator). Work top to bottom.

## Status at a glance

**Already done ✅**
- App icon: `AppIconArtwork` + generated 1024×1024 opaque PNG, asset catalog
  wired into `App.xcodeproj`, all home-screen sizes compile into the bundle.
  (Regenerate anytime with `swift run GenerateAppIcon`.)
- Version `1.0` / build `1` (Info.plist).
- Launch screen present (blank `UILaunchScreen`).
- No privacy usage strings required yet — the shipping app is mock/local (no
  HealthKit / network / location in source).
- Repo is clean (no stray tracked files).

**Decisions you made**
- **App name: Otterpace** (renaming from "RunBuddy" — see "App name" section below). The otter mascot stays named **Buddy**.
- Bundle ID: **set to `com.otterpace.app`** in the project (was `com.example.App`). A bundle ID is just an identifier — **no DNS / domain setup is required** to use it or to ship. You still need to register it as an App ID under your Apple Developer account (Xcode does this automatically when you enable signing).
- Code signing: handle in Xcode with your team.

## App name: Otterpace

Chosen after vetting otter-themed candidates. "RunBuddy" is descriptive but
crowded; "Otterpace" leads with the unique mascot, reads instantly as a running
coach, and came back clean:

| Check | Result |
|---|---|
| App Store (fitness) | ✅ no "Otterpace" app found |
| Trademark | ✅ none in fitness; Otter.ai / OtterBox / Otter POS are unrelated categories |
| `otterpace.com` | ✅ secured — registered on Namecheap |

Rejected: OtterRun (collides with the *Otter African Trail Run* event + `otterrun.com` is parked), Lutra (existing "LUTRA" AI-SaaS trademark + water-treatment lutra.com), PaceOtter (crowded "Pace___" App Store field), OtterBuddyRun (long + redundant "Buddy").

### Rename checklist (RunBuddy → Otterpace)

Mascot **Buddy** is unchanged — only the product/app name changes.

**In-repo edits — DONE ✅** (committed):
- [x] `Info.plist` → `CFBundleDisplayName = Otterpace` (home screen now reads "Otterpace").
- [x] `Sources/AppCore/TodayHeader.swift` → wordmark "Otterpace".
- [x] `Sources/AppCore/AppIconArtwork.swift` → "Otterpace app icon" label + showcase title.
- [x] `RunBuddyModel` → `OtterpaceModel` (model class + all call sites + tests + glossary).
- [x] `README.md`, code comments → Otterpace.
- [x] `.codeyam/editor.json` → `projectTitle` + spec references → Otterpace.
- [x] `otterpace.com` registered (Namecheap).

**Still yours, in Xcode / App Store Connect:**
- [x] `App.xcodeproj` → bundle ID set to `com.otterpace.app` (replaced `com.example.App`). Verified the app still builds, launches, and captures.
- [ ] Register `com.otterpace.app` as an App ID under your Apple Developer account (Xcode "Automatically manage signing" does this for you when you pick your team). No DNS needed.
- [ ] App Store Connect → create the app record with name **Otterpace**.

---

## 1. Apple Developer prerequisites (do first)

- [ ] Confirm you have a paid **Apple Developer Program** membership ($99/yr) —
      required for TestFlight.
- [ ] Decide the **bundle identifier** (reverse-DNS, globally unique), e.g.
      `com.codeyam.runbuddy`. You'll register it as an **App ID** and create the
      app record in App Store Connect (step 5).

## 2. Project metadata in Xcode (`App.xcodeproj`)

Open `App.xcodeproj` in Xcode → select the **App** target → **General** /
**Signing & Capabilities** / **Build Settings**:

- [ ] **Display name**: set to `Otterpace` (see the rename checklist above).
      - Quickest: add `CFBundleDisplayName = Otterpace` to `App/Info.plist`
        (one key — does not touch the bundle ID), or set the target's
        "Display Name" field. Today the home screen shows "App".
- [ ] **Bundle Identifier**: change `PRODUCT_BUNDLE_IDENTIFIER` from
      `com.example.App` to your chosen ID (step 1).
- [ ] **Version / Build**: `1.0` / `1` is fine for the first upload. Bump
      **Build** for every subsequent TestFlight upload (1 → 2 → 3…).
- [ ] (Optional) **Device family**: currently iPhone + iPad (`1,2`). Keep, or
      restrict to iPhone-only if that's the intended target.

## 3. Signing & Capabilities

- [ ] In **Signing & Capabilities**, check **Automatically manage signing** and
      select your **Team**. Xcode creates/uses the provisioning profile.
- [ ] No capabilities to add yet (no HealthKit/Strava in the shipping build). If
      you add them later, this is where the entitlement + matching
      `NS…UsageDescription` Info.plist strings go (see step 7).

## 4. Build & test on a real device

- [ ] Plug in an iPhone, select it as the run destination, and **Run** — confirm
      it installs, launches, the **RunBuddy icon** shows on the home screen, and
      the dashboard/coach/history/weekly-review screens work.
- [ ] Sanity-check Dynamic Type + light/dark by changing the device text size.

## 5. App Store Connect — create the app record

- [ ] At appstoreconnect.apple.com → **Apps → +** → **New App**: platform iOS,
      pick the **bundle ID** from step 2, set the name **RunBuddy**, primary
      language, SKU.
- [ ] Fill the minimum TestFlight metadata (what TestFlight prompts for): test
      info / "what to test", and a contact email. Full App Store listing
      (screenshots, description) is only needed for public release, not TestFlight.

## 6. Archive & upload

- [ ] In Xcode: set the run destination to **Any iOS Device (arm64)**.
- [ ] **Product → Archive**. When the Organizer opens, **Distribute App →
      App Store Connect → Upload**.
- [ ] Wait for processing in App Store Connect → **TestFlight** tab (a few
      minutes). Resolve any "missing compliance" / export-compliance prompt
      (this app uses no non-exempt encryption → answer accordingly).
- [ ] Add yourself / testers to an **Internal Testing** group and install via the
      TestFlight app.

## 7. Not needed now — but required when real integrations land

These are out of scope for the current mock build; add them in the same release
that introduces the real feature, or App Store review will reject:

- [ ] **HealthKit**: HealthKit capability + `NSHealthShareUsageDescription`
      (and `NSHealthUpdateUsageDescription` if writing).
- [ ] **Strava OAuth**: `ASWebAuthenticationSession` redirect handling; no extra
      Info.plist string, but document the privacy flow.
- [ ] **Location** (route data): `NSLocationWhenInUseUsageDescription`.
- [ ] **Privacy manifest** (`PrivacyInfo.xcprivacy`) once you collect/transmit
      any user data (e.g. sending context to an AI coach backend).

## 8. Optional polish before first invite

- [x] Branded launch screen — coral background + centered Buddy via the
      `UILaunchScreen` keys (`LaunchBackground` color + `LaunchBuddy` image,
      generated by `swift run GenerateAppIcon`). First launch is no longer blank.
- [ ] `CFBundleName` is still `App` (via `PRODUCT_NAME`); `CFBundleDisplayName`
      from step 2 covers the user-visible name, so this is cosmetic.

---

### What I can do for you in this repo (just say the word)

- Apply the **RunBuddy display name** (`CFBundleDisplayName` in `Info.plist`).
- Set the **bundle identifier** in `project.pbxproj` once you've chosen it.
- Add a **branded launch screen**.
- Wire **HealthKit/Strava capabilities + usage strings** when you start those.

The team selection, archive, and upload stay in Xcode — those need your Apple
Developer account and can't run from here.
