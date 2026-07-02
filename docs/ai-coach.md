# AI Coach (M3) — real LLM replies, BYO key, backed by Vercel

The Ask Coach chat has two coaches behind one `CoachReply` shape:

- **`CoachEngine`** (on-device, deterministic) — the always-on default. Used
  offline, when no key is connected, on any backend failure, and in every
  CodeYam scenario/seed so captures stay deterministic and network-free.
- **`RemoteCoach`** (real Claude) — used for interactive sends when the user has
  connected their own Anthropic key in **Settings → AI Coach**.

## How it connects (BYO key, proxied through a backend)

```
iOS app ──{question, TodayState}──▶  otterpace.com/api/coach   ──▶  Anthropic
          x-anthropic-key: <user key>     (Vercel function:            (user's key)
                                            curated coach prompt
                                            + safety rules +
                                            structured output)
```

- The user's key is sent **per request** in the `x-anthropic-key` header and is
  **never stored, logged, or persisted** by the function (`api/coach.ts` holds no
  state). On-device it lives only in the Keychain (`CoachConfig.keyAccount`).
- The **coaching prompt, safety rules, and model choice live server-side**, so
  they can be tuned without an App Store release, and the client can't see or
  tamper with them.
- The backend constrains Claude to a structured `{ text, mood, safetyFlag }`
  reply (mood ∈ the app's `BuddyMood` raw values) so the app decodes it directly.
- **You pay nothing for coach usage** — each user's calls run on their own key.
- The `TodayState` context now also carries an **optional onboarding
  personalization profile** (`profile`: usual walking volume + time of day, and
  any other training) alongside the day's activity summary. It rides inside the
  same request — no new transport — and the system prompt uses it to tailor tone
  and suggestions. Every field is optional; a missing/`null` field means the user
  didn't share it, and the profile never overrides the hard safety rules.

## Files

- `api/coach.ts` — the Vercel serverless function (Anthropic SDK).
- `vercel.json` / `package.json` — Vercel config + deps (`@anthropic-ai/sdk`).
- `Sources/AppCore/Coach/RemoteCoach.swift` — iOS client + `CoachKeyStore`.
- `Sources/AppCore/AskCoachView.swift` — routes interactive sends to the coach,
  falls back to the mock; seeding stays on the mock.
- `Sources/AppCore/SettingsView.swift` — the AI Coach connect/disconnect UI.

## Going live (one-time, you)

1. **Import this repo into Vercel** (your personal account → New Project →
   pick `nseldeib/otterpace`). Framework preset: **Other**. It auto-detects
   `vercel.json` (static site from `site/`) and the `api/` function.
2. **Add the domain** `otterpace.com` in the Vercel project's **Domains** tab
   and follow its DNS instructions on Namecheap. Using Vercel for the domain
   means you do **not** also point DNS at GitHub Pages — pick one host for
   `otterpace.com` (Vercel serves both the site and `/api/coach`). The GitHub
   Pages workflow can stay as a fallback for the static site only.
3. *(optional)* Set env var **`COACH_MODEL`** in Vercel to override the model
   (default `claude-opus-4-8`). No server-side API key is needed — keys are BYO.
4. In the app: **Settings → AI Coach → paste an Anthropic key → Connect**, then
   ask the coach a question. Without a key, the built-in coach answers.

## Verify

- `https://otterpace.com/api/coach` returns `405` to a GET (POST-only) once
  deployed — a quick liveness check.
- A connected key in the app yields a "Buddy is thinking…" bubble that resolves
  to a real reply; a bad key falls back to the on-device coach with a note.

## Notes / limits

- The real LLM path can't be verified in the CodeYam preview loop (needs the
  deployed backend + a key + network). Scenarios always use the deterministic
  mock by design.
- `@anthropic-ai/sdk` / `@vercel/node` are pinned to `latest` in `package.json`
  so the first Vercel install resolves a version with the `output_config`
  structured-output API; pin to exact versions after the first successful deploy.
