# AI Coach (M3) — real LLM replies, BYO key, backed by Vercel

The Ask Coach chat has two coaches behind one `CoachReply` shape:

- **`CoachEngine`** (on-device, deterministic) — the always-on default. Used
  offline, when no key is connected, on any backend failure, and in every
  CodeYam scenario/seed so captures stay deterministic and network-free.
- **`RemoteCoach`** (a real LLM) — used for interactive sends when the user has
  connected their own API key from Anthropic, OpenAI, or Gemini in
  **Settings → AI Coach**. The provider is recognized from the key's shape and
  routed by the shared backend router; the prompt and safety rules never vary by
  provider.

Why BYO key at all, and why "just log in with my ChatGPT subscription" is not
currently buildable, is recorded in
[`codeyam/ai-connection-options.md`](codeyam/ai-connection-options.md). Note that
an API key bills against a **separate** balance from a ChatGPT Plus or Claude Pro
subscription — a connected key with no credits is the single most common reason
the chat fails.

## How it connects (BYO key, proxied through a backend)

```
iOS app ──{question, TodayState}──▶  otterpace.com/api/coach ──▶ api/_lib/llm.ts ──▶ Anthropic
          x-ai-provider: <provider>      (Vercel function:        (provider router)     OpenAI
          x-ai-key:      <user key>       curated coach prompt                          Gemini
                                          + safety rules +                          (user's key)
                                          structured output)
```

- **The prompt does not vary by provider.** Otterpace's coaching quality and
  safety rules are the product; the provider only changes which model generates
  the words. That invariant is why the router exists, and a provider that cannot
  honor the schema is a bug to fix in `llm.ts`, not a reason to soften the prompt.
- The user's key is sent **per request** in the `x-ai-key` header, alongside
  `x-ai-provider` naming which service to call, and is **never stored, logged, or
  persisted** by the function. On-device it lives only in the Keychain, one
  account per provider.
- `x-anthropic-key` is retained **only** as a legacy fallback for already-installed
  clients, and a request with no `x-ai-provider` is inferred as Anthropic
  (`api/_lib/llm.ts`). App and backend cannot deploy atomically, so compatibility
  runs both ways.
- **Models are env-overridable** without an app release: `COACH_MODEL`,
  `COACH_MODEL_OPENAI`, `COACH_MODEL_GEMINI`.
- The **coaching prompt, safety rules, and model choice live server-side**, so
  they can be tuned without an App Store release, and the client can't see or
  tamper with them.
- The backend constrains the model to a structured `{ text, mood, safetyFlag }`
  reply (mood ∈ the app's `BuddyMood` raw values) so the app decodes it directly.
- **You pay nothing for coach usage** — each user's calls run on their own key.
- The `TodayState` context now also carries an **optional onboarding
  personalization profile** (`profile`: usual walking volume + time of day, and
  any other training) alongside the day's activity summary. It rides inside the
  same request — no new transport — and the system prompt uses it to tailor tone
  and suggestions. Every field is optional; a missing/`null` field means the user
  didn't share it, and the profile never overrides the hard safety rules.

## Files

- `api/coach.ts` — the Vercel serverless function: validates, builds the prompt.
- `api/_lib/llm.ts` — the **provider layer**: reads the key + provider off the
  headers and routes to Anthropic (SDK), OpenAI or Gemini (plain `fetch`).
  `api/race-import.ts` and `api/race-search.ts` share it, so all three
  coach-backed endpoints support all three providers identically.
- `vercel.json` / `package.json` — Vercel config + deps. `@anthropic-ai/sdk` is the
  only vendor SDK shipped; the other two providers are reached over `fetch`.
- `Sources/AppCore/Coach/CoachProvider.swift` — the provider enum: key-shape
  detection, display names, console URLs, and user-facing copy.
- `Sources/AppCore/Coach/RemoteCoach.swift` — iOS client + `CoachKeyStore`.
- `Sources/AppCore/AskCoachView.swift` — routes interactive sends to the coach,
  falls back to the mock; seeding stays on the mock.
- `Sources/AppCore/SettingsView.swift` — the AI Coach connect/disconnect UI.

## Going live (one-time, you)

1. **Import this repo into Vercel** (your personal account → New Project →
   pick `codeyam-ai/otterpace`). Framework preset: **Other**. It auto-detects
   `vercel.json` (static site from `site/`) and the `api/` function.
2. **Add the domain** `otterpace.com` in the Vercel project's **Domains** tab
   and follow its DNS instructions on Namecheap. Using Vercel for the domain
   means you do **not** also point DNS at GitHub Pages — pick one host for
   `otterpace.com` (Vercel serves both the site and `/api/coach`). The GitHub
   Pages workflow can stay as a fallback for the static site only.
3. *(optional)* Set env var **`COACH_MODEL`** in Vercel to override the model
   (default `claude-opus-4-8`). No server-side API key is needed — keys are BYO.
4. In the app: **Settings → AI Coach → paste a key from Anthropic, OpenAI or
   Gemini → Connect**, then
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

## Adding a fourth provider

Two places enumerate providers, and `CoachProvider.swift` promises that is the
whole list:

1. **`Sources/AppCore/Coach/CoachProvider.swift`** — add the case. Key-shape
   detection, display name, console URL and the user-facing copy all hang off the
   enum, and `allNamesSentence` derives prose from `displayOrder`, so the app's
   copy updates itself.
2. **`api/_lib/llm.ts`** — add the case to `LlmProvider`, `MODELS`, and the
   `complete` switch, with a `complete<Provider>` function that returns the shared
   `LlmResult` shape.

Nothing else should need touching: the prompt, safety rules and structured-output
contract are provider-independent by design. If a change is needed anywhere else,
that is a sign the abstraction leaked.
