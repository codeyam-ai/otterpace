# How Otterpace connects to an AI coach — decision record

**Status:** decided for BYO key (shipped). Subscription auth investigated and
rejected for now. Apple Foundation Models recommended as the next step.

**Date:** 2026-07-30

Otterpace's coach needs a model behind it, and someone has to pay for the
tokens. This records the options considered, what was actually shipped, and why
the obvious-sounding one — "just log in with my ChatGPT subscription" — is not
currently buildable.

Companion to [`../ai-coach.md`](../ai-coach.md), which documents the shipped
architecture. This file is about the *choice*, not the implementation.

## What shipped: bring your own API key

The user pastes an API key from Anthropic, OpenAI, or Gemini. It lives in the
iOS Keychain, is sent per request, and is never stored server-side. See
`CoachProvider` / `CoachKeyStore` and the backend router in `api/_lib/llm.ts`.

Why this first:

- **No cost to the project.** The user pays their own provider directly. That is
  what makes a free, open-source app with a real LLM behind it viable at all.
- **It sidesteps In-App Purchase.** Apple requires digital content and features
  sold in-app to go through IAP, at Apple's cut. BYO key isn't Otterpace selling
  anything — the user has an existing relationship with a third party.
- **It matches the privacy stance.** The key never leaves the device except on
  the request it authenticates.

The honest cost: **it asks a consumer to go create an API key**, which is a real
wall for the "beginner runner" audience in the product spec. Everything below is
about lowering that wall.

## Rejected for now: connecting a consumer subscription

The appealing version is "sign in with the ChatGPT / Claude / Gemini plan I
already pay for." As of this writing that is not something a third-party app can
build:

- **Claude Pro / Max, ChatGPT Plus, and Gemini Advanced are billed separately
  from their respective APIs.** Paying for the consumer chat product does not
  grant API quota, and API usage is metered separately.
- **None of the three publishes a consumer OAuth flow** that lets a third-party
  app spend a user's *subscription* on the user's behalf. Anthropic's OAuth
  exists for Claude Code specifically. Google's OAuth is for Cloud / Vertex,
  which is a GCP billing account, not a consumer Gemini Advanced plan.

So there is no integration to write. This is a provider-policy limitation, not
an engineering gap.

**Caveat, stated plainly:** this reflects provider policy as understood at the
date above, and that policy moves. Re-check before assuming it still holds. Do
not attempt to work around it by driving a consumer web session
programmatically — that would breach the providers' terms and break constantly.

## Recommended next: Apple Foundation Models

The genuinely key-free path on iOS is Apple's on-device Foundation Models
framework.

- **No key, no account, no signup.** The best possible onboarding — the coach
  just works on first launch.
- **Free**, both to the user and to the project.
- **Strongest possible privacy story**, and consistent with the spec's principle
  that health data stays on-device. Nothing leaves the phone at all.

Costs to weigh before doing it:

- **Deployment target.** Otterpace currently targets `IPHONEOS_DEPLOYMENT_TARGET
  = 17.0`; the framework needs a much newer floor. This has to be an
  availability-gated path alongside BYO key, not a replacement — older devices
  still need a provider.
- **Model size.** It is a small on-device model, well below frontier quality. In
  Otterpace's favour: a coach reply is two to four sentences of structured JSON
  against a well-specified prompt, which is within range. This should be
  validated against the existing coach scenarios before committing.
- The safety rules in the system prompt would need re-validating against it —
  they are the product, and a smaller model may follow them less reliably.

## Considered and not chosen: a hosted coach behind IAP

Otterpace could run the coach on its own key and sell it as an App Store
subscription.

- Best onboarding of any option: no key, no setup.
- But the project absorbs inference cost plus Apple's cut, and it **inverts the
  privacy model** — Otterpace's server would see the training data it currently
  never touches. For an open-source, privacy-forward project that is the wrong
  trade today.

## Also worth doing: a custom OpenAI-compatible endpoint

Cheap to add and high leverage. A base-URL field next to the key would let one
input cover xAI/Grok, DeepSeek, Mistral, Groq, Together, Fireworks, OpenRouter,
and self-hosted Ollama, because they all speak the OpenAI wire format that
`api/_lib/llm.ts` already implements. OpenRouter is especially notable: one key
reaches all three majors plus hundreds of models, which is friendlier than
opening three separate developer accounts.

Tracked as a follow-up; not part of the multi-provider change.

## Open item

The per-provider default model IDs in `api/_lib/llm.ts` (`COACH_MODEL`,
`COACH_MODEL_OPENAI`, `COACH_MODEL_GEMINI`) should be confirmed against each
provider's current lineup before the backend deploys. They are env-overridable,
so correcting them is configuration rather than a release.
