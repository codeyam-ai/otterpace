---
title: "Provider Copy Says All Three, Not Just Anthropic"
mode: ui
createdAt: "2026-08-03T14:59:05Z"
source: manual
---

## Summary

Otterpace's BYO-key coaching became multi-provider in `567a4d6` ("Get an API
Key — Reach All Three Providers"): `CoachProvider` carries `.anthropic`,
`.openai`, and `.gemini`, each with its own Keychain account and console link,
and every backend path (`api/coach.ts`, `api/race-import.ts`,
`api/race-search.ts`) routes through `api/_lib/llm.ts`, which has a real branch
per provider. The feature is complete; what did not follow it is the copy.

Every user-facing and developer-facing surface outside the app's own Settings
and onboarding screens still says "Anthropic" as if it were the only option. The
material one is the privacy policy: `site/privacy.html` tells users their
question, activity summary, personalization profile, and journal slice "are sent
to our backend and on to Anthropic" — which is simply false for a user who
connected an OpenAI or Gemini key. A privacy policy that names the wrong data
recipient is an accuracy problem, not a polish problem. Inside the app,
`RaceImportView` still tells the user that importing a race "uses your Anthropic
API key" even though it passes whatever provider is active.

This plan corrects every surface that names a provider, makes the in-app race
copy derive from the connected provider the same way `CoachPreviewDestinationCard`
already does, and adds guards so the copy cannot silently drift out of sync
again.

## Key Decisions

- **The privacy policy leads.** It is the only surface with a correctness stake
  beyond tidiness, so it gets the most careful rewrite: name all three providers,
  and make it unambiguous that the destination is whichever provider the user
  connected, not a fixed vendor.
- **In-app copy is derived, not restated.** `RaceImportView`'s prompt becomes a
  pure, testable function of the active provider rather than a hardcoded vendor
  name. This is exactly the pattern `CoachPreviewDestinationCard.swift:15-20`
  already uses ("…is sent to \(provider.displayName) using your own API key"),
  and it is why that card did not go stale when the other two providers landed.
- **No new API handlers.** `api/` sits at exactly 12 functions, the Vercel Hobby
  ceiling, so this plan touches only comments and tests in existing handlers.
- **Add provider coverage to the race endpoint tests.** `test/api/race-import.test.ts`
  and `test/api/race-search.test.ts` mock only `@anthropic-ai/sdk` and assert
  against the legacy `x-anthropic-key` header. They pass, but they prove nothing
  about the OpenAI or Gemini paths those endpoints now support. A single
  `x-ai-provider: openai` case per endpoint closes that gap cheaply.
- **Guard the copy with a test, not a convention.** A vitest over
  `site/privacy.html` asserting that if it names any provider it names all three
  is what stops the next provider addition from leaving the policy wrong again.
- **`docs/ai-coach.md` is rewritten, not patched.** Its architecture diagram,
  header names, and file list all predate `_lib/llm.ts`; line-editing it would
  leave a document that reads as Anthropic-shaped with substitutions.
- **Out of scope, flagged:** `docs/app-store-listing.md` also has stale *version*
  state (it describes 1.0.1 build 6 as the pending update; 1.0.2 is live and
  1.0.3 build 12 is in external review). That is unrelated version drift, not
  provider copy. Left alone deliberately so this plan stays reviewable, but worth
  its own pass.

## Implementation

### 1. Privacy policy — the material fix

**File**: `site/privacy.html`

Rewrite the AI-coach paragraph (line 35). It currently reads "If you connect an
AI coach by adding your own Anthropic API key… sent to our backend and on to
Anthropic to generate a reply."

The replacement must say:

- The user connects their own API key from **Anthropic, OpenAI, or Google
  (Gemini)**.
- What is sent is unchanged (question, activity summary, onboarding
  personalization profile, recent journal slice) — do not weaken these existing
  disclosures.
- The request goes to Otterpace's backend and on to **the provider whose key you
  connected**, and to no other provider.
- Everything already true stays true and stays stated: key lives only in the
  device Keychain, never on the server; questions are not retained; profile and
  journal never go to analytics; roughly two weeks of journal entries, long notes
  shortened; Settings → Privacy erases them.

Keep the existing document voice and sentence rhythm; this is a correction, not a
rewrite of the policy's tone.

### 2. In-app race import copy

**File**: `Sources/AppCore/Coach/CoachProvider.swift`

Add a pure copy helper beside the existing `article` / `displayName` /
`consoleURL` accessors:

```
static func keyRequirementCopy(action: String, provider: CoachProvider?) -> String
```

- With a provider: "Importing races from the web uses your \(provider.displayName)
  API key…" (grammatical for all three via the existing `article` accessor).
- With none: the connect-a-key phrasing, naming all three options rather than one.

Pure and SwiftUI-free, so it is unit-testable exactly like `CoachProvider.detect`.

**File**: `Sources/AppCore/RaceImportView.swift`

- Replace the hardcoded string at line 289 ("\(action) races from the web uses
  your **Anthropic** API key…") with `CoachProvider.keyRequirementCopy`.
- The sheet already resolves `keyStore.activeProvider` for the request path
  (lines 84 and 214); read the same value for the copy so the sentence and the
  request can never disagree.
- Update the file's header comment (line 13), which still says "Both reuse the
  BYO Anthropic key".

**File**: `Sources/AppCore/CodeyamIsolated/SettingsActionRowIsolated.swift`

The isolated preview's sample label is "Get an Anthropic API key" (line 22),
frozen from before `CoachConsoleLinkRow` became provider-aware. Update it to
match what the real row renders today so the `settingsactionrow-variants`
scenario stops advertising a row shape the app no longer has.

### 3. README

**File**: `README.md`

Lines 56 and 83 both say "your own Anthropic key". Update both to name Anthropic,
OpenAI, or Gemini, and mention that the key is detected from its shape so the
user does not have to pick a provider manually.

### 4. Developer doc — rewrite for the multi-provider architecture

**File**: `docs/ai-coach.md`

Rewrite rather than patch. It must describe what exists now:

- **Flow**: iOS app → `otterpace.com/api/coach` → `api/_lib/llm.ts` → the branch
  for the connected provider (Anthropic SDK / OpenAI chat-completions /
  Gemini generateContent).
- **Headers**: `x-ai-key` + `x-ai-provider` are current (`api/_lib/llm.ts:89-90`);
  `x-anthropic-key` is retained only as the legacy fallback for already-installed
  clients, and a request with no `x-ai-provider` is inferred as Anthropic
  (`api/_lib/llm.ts:119-120`). The doc currently presents the legacy header as
  the live one.
- **Models and env overrides**: `COACH_MODEL`, `COACH_MODEL_OPENAI`,
  `COACH_MODEL_GEMINI` (`api/_lib/llm.ts:29-33`).
- **The invariant worth stating explicitly**: the system prompt and safety rules
  do not vary by provider; the provider only changes which model generates the
  words. This is the reason the abstraction exists and it belongs in the doc.
- **File list**: add `api/_lib/llm.ts` as the provider layer, and note that
  `api/race-import.ts` and `api/race-search.ts` share it.
- **Setup step** (line 58): paste a key from any of the three.
- **Adding a provider**: a short section pointing at the two places that
  enumerate providers — the `CoachProvider` enum and the `llm.ts` switch — which
  `CoachProvider.swift:11-12` already promises is the whole list.

### 5. Runbook

**File**: `docs/go-live-runbook.md`

- Line 24: "end users paste their own **Anthropic** key" → any of the three; and
  the reassurance that you need no key of your own to ship stays.
- Line 105: the on-device smoke test should exercise a provider key generally,
  with a note that testing more than one provider is worthwhile since they are
  separate code paths.
- Lines 157 and 160: the dependency note claims `@anthropic-ai/sdk` is "the only
  runtime dependency". Verify against `package.json` before rewording — the
  OpenAI and Gemini branches use `fetch` rather than vendor SDKs
  (`api/_lib/llm.ts:198`), so the claim may still be accurate and only its
  framing ("the Anthropic SDK is the only one we ship") needs adjusting.

### 6. Store listing note

**File**: `docs/app-store-listing.md`

Line 54's parenthetical, "BYO-key requests still go straight to Anthropic, never
stored", is used to justify the **Data Not Collected** privacy label. Reword to
"straight to the user's chosen AI provider, never stored". The label answer does
not change — nothing new is collected either way — but the sentence supporting it
must be true.

### 7. Backend header comments

**Files**: `api/race-import.ts` (lines 7-8), `api/race-search.ts` (line 7)

Both describe the request as carrying "the user's own Anthropic key in the
`x-anthropic-key` header". Both actually call `credentialsFromHeaders` + `complete`
and support all three providers. Correct the comments; no behavior change.

### 8. Tests

**New**: `test/site/privacy-copy.test.ts` — read `site/privacy.html` and assert
that if it names any supported provider it names all three. The durable guard
that keeps the policy honest the next time a provider is added.

**Extend**: `test/api/race-import.test.ts` — add a case sending
`x-ai-provider: openai` with `x-ai-key`, asserting the request goes out on the
OpenAI path (the file currently mocks only `@anthropic-ai/sdk` and asserts on
`x-anthropic-key`; follow the provider-mocking approach already used in
`test/api/coach.test.ts`). Also confirm the existing "never logs the API key"
assertion covers the new header.

**Extend**: `test/api/race-search.test.ts` — the same single OpenAI-provider case.

**New**: `Tests/AppCoreTests/CoachProviderCopyTests.swift` — `keyRequirementCopy`
names the connected provider for each of the three, names all three when no
provider is connected, reads grammatically (`article` applied correctly), and
contains no em dashes (the copy convention applied across the app).

### 9. Scenario recapture

Two scenarios capture the race-import copy being changed and will need
recapturing: `raceimportsheet-no-key` and `racesearchsheet-no-key`. The
`settingsactionrow-variants` scenario covers the isolated-preview label change.

Recapture per-scenario with `rbTheme` pinned and diff each result against its
committed original before accepting — do not run a bulk recapture-stale pass over
this stack.

## Reused existing code

- `CoachProvider` from `Sources/AppCore/Coach/CoachProvider.swift` (glossary
  entry: `CoachProvider`) — `displayName`, `article`, and `consoleURL` already
  exist for exactly this kind of copy; the new helper joins them rather than
  duplicating vendor names elsewhere.
- `CoachPreviewDestinationCard` from
  `Sources/AppCore/CoachPreviewDestinationCard.swift` (glossary entry:
  `CoachPreviewDestinationCard`) — the reference implementation of
  provider-derived copy, including the no-provider branch. Its scenarios
  (`coachpreviewdestinationcard-connected` / `-no-provider`) are the model for
  how the race sheet's two states should read.
- `credentialsFromHeaders` / `complete` / `isLlmProvider` from `api/_lib/llm.ts`
  — already the single place that knows the provider set; the doc rewrite
  describes it rather than re-explaining providers per endpoint.
- `test/api/coach.test.ts` — already exercises the multi-provider header path;
  the race-endpoint test additions should mirror its mocking approach rather than
  invent a second one.
- `Tests/AppCoreTests/CoachProviderConsoleTests.swift` — existing home for
  `CoachProvider` accessor tests; the new copy test sits beside it and follows
  its structure.

## Scenarios to Demonstrate

- `raceimportsheet-no-key` (recapture) — the import sheet with no key connected,
  now naming all three providers instead of Anthropic.
- `racesearchsheet-no-key` (recapture) — same for the search sheet.
- `raceimportsheet-openai-connected` (new) — the import prompt with an OpenAI key
  active, proving the copy follows the connected provider.
- `raceimportsheet-gemini-connected` (new) — the same with Gemini, where the
  indefinite article differs ("a Gemini key" vs "an OpenAI key").
- `settingsactionrow-variants` (recapture) — the isolated row label matching the
  provider-aware row the app actually ships.
- `coachpreviewdestinationcard-connected` (existing, re-verify) — confirms the
  card that was already correct still reads consistently with the newly corrected
  race copy.
