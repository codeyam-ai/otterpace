---
title: "Conversational, Trust-First AI Coaching"
mode: ui
createdAt: "2026-07-10T20:15:00Z"
source: manual
---

## Summary

The Ask Coach chat feels annoying in two specific ways: it repeats the same
check-in question ("How are the legs?") turn after turn, and it drops into
"safety mode" (rest, see-a-clinician, shield-flagged bubbles) far too readily.
Both trace to concrete causes. The chat is **stateless per message** — the app
sends only `{question, context}` with no conversation history, so every reply is
generated as if it were the first, and the prompt's "usually end with a check-in
question" defaults to the same question forever. And the safety triggers are
blunt: any run ≥5 mi counts as "hard," the word "sore" routes to a full injury
lockdown, and the prompt biases hard toward rest. This plan gives the coach
**conversation memory** end-to-end (client → API → multi-turn prompt),
**de-repeats** the check-in question, and **rebalances safety** to trust the
athlete by default while keeping genuine injury/spike caution intact — across
both the real LLM coach and the offline deterministic engine.

## Key Decisions

- **Thread real conversation history, don't just tweak the prompt** — The root
  cause of repetition is that the model never sees what it already said. We add a
  `history` array to the request and rebuild the API's `messages` as proper
  multi-turn user/assistant turns. This is the single highest-leverage change; a
  prompt-only fix can't make a stateless call "remember."
- **Cap and bound the history** — Send only the last ~8 turns (client-trimmed)
  and validate/cap server-side, so we protect the user's own token spend (they
  pay on their BYO key) and stay within the existing `MAX_CONTEXT_BYTES` spirit.
- **Suppress, don't just rotate, the check-in question** — The prompt already
  says "usually end with one check-in question." The fix is an explicit rule:
  never repeat a question the user already answered, and only ask when it
  genuinely advances the conversation. The offline engine, which has no LLM to
  reason, gets a deterministic turn-aware suppression + rotation instead.
- **Split mild soreness from real pain** — "sore/ache/tight" after a run is
  normal training feedback, not an injury event. Only sharp/persistent/worsening
  pain should trigger the clinician lockdown and `safetyFlag`. This is the
  biggest driver of the "too much safety mode" feeling.
- **Raise the "hard run" bar** — `ranHardRecently` currently flags any run ≥5 mi.
  A routine easy 5-miler is not a hard effort. Gate on distance *and* effort
  signal (pace/intensity when available), and require a higher distance floor.
- **Keep genuine safety intact** — A true load spike (baseline classifier),
  sharp/persistent pain, and taper-week race caution still win and still set
  `safetyFlag`. We are dialing back false positives, not removing the guardrails.

## Implementation

### 1. Add conversation history to the request contract

**File**: `Sources/AppCore/Coach/RemoteCoach.swift`

Extend `RemoteCoach.RequestBody` with a `history` field: an array of
`{role, text}` turns (`role` ∈ `"user" | "coach"`). Change
`RemoteCoach.reply(to:context:apiKey:)` to `reply(to:context:history:apiKey:)`,
encoding the trimmed history alongside `question` and `context`. Define a small
`Encodable` turn struct local to `RemoteCoach` (mirrors `ChatMessage` but carries
only role + text — no mood/id). Keep the response shape unchanged.

### 2. Pass the running thread from the chat view

**File**: `Sources/AppCore/AskCoachView.swift`

In `submit(_:)`, before appending the placeholder, snapshot the current
`messages` (excluding the just-appended user question and any "thinking…"
placeholder), map them to the new turn type, and trim to the last ~8 turns.
Pass that to `remote.reply(to:context:history:apiKey:)`. The deterministic
`ask(_:)` path (offline/seeded) should likewise thread the prior `messages` into
`CoachEngine.reply` (see step 4) so the offline coach also stops repeating.

### 3. Rebuild the API as a real multi-turn conversation + rebalance safety

**File**: `api/coach.ts`

- **History intake**: accept `body.history` (optional array). Validate each entry
  is `{role: "user"|"coach", text: string}`, drop malformed entries, cap to the
  last ~8 turns, and enforce a per-turn and total byte bound consistent with
  `MAX_CONTEXT_BYTES`. Map `coach` → `assistant`, `user` → `user`.
- **Message construction**: build `messages` as `[...historyTurns, finalUserTurn]`
  instead of a single stuffed user message. The final user turn keeps the
  `Today's context (JSON):\n…\n\nUser's question:\n…` framing so the context test
  (`sentContent` assertions in `test/api/coach.test.ts`) still finds the payload
  in the *last* message. Prior coach turns are plain assistant text.
- **De-repeat rule** (SYSTEM_PROMPT, Style section): replace "Then usually end
  with one genuine check-in question…" with guidance that (a) you can now see the
  conversation so far, (b) never re-ask a question the user already answered or
  that you asked recently, (c) only ask a check-in when it genuinely moves the
  coaching forward, and (d) when you do ask, vary what you ask about (sleep,
  weekly goal, how a specific workout felt) rather than defaulting to the legs.
- **Trust-first rebalance** (SYSTEM_PROMPT, Hard rules + a new "Calibrating
  caution" note): keep the injury/spike/no-shame rules, but clarify that
  `safetyFlag` and rest-steering are for *genuine* signals only — sharp,
  persistent, or worsening pain; a true one-week spike vs. baseline; a recent
  genuinely hard effort. Normal post-run soreness, being modestly above an
  average week, and a declared ~10%/week build are NOT safety events; default to
  trusting the athlete and affirming good training. State plainly that
  over-flagging erodes trust.

### 4. Make the offline engine conversational and less trigger-happy

**File**: `Sources/AppCore/CoachEngine.swift`

- **Signature**: add an optional `history: [CoachTurn]` (or reuse `ChatMessage`
  role/text) parameter to `reply(to:context:asOf:)`, defaulting to empty so
  existing callers/tests compile. Use it to decide whether to append or suppress
  the closing check-in question, and to rotate which check-in is asked
  (legs → sleep → weekly goal → how a workout felt) based on how many coach turns
  have already happened. Never emit the same closing question twice in a row.
- **Soreness vs. pain split**: in `CoachIntent.classify`, separate mild soreness
  ("sore", "ache", "tight", "stiff") from injury signals ("sharp", "pain",
  "hurt", "injur", "strain", "sprain", plus persistent/worsening phrasing). Add a
  lighter intent (e.g. `.postRunSoreness`) that gives normal-training-feedback
  reassurance with `safetyFlag = false` and a non-`concerned` mood, reserving the
  full `injuryReply` lockdown + `safetyFlag` for genuine pain.
- **Hard-run threshold**: in `ranHardRecently`, raise the distance floor and,
  when the workout carries an effort/pace signal, require it to indicate a real
  effort — so a routine easy 5-miler no longer forces a recovery day. A true load
  spike still returns true unchanged.

### 5. Update tests to the new contract

**File**: `test/api/coach.test.ts`

Add cases: history is passed through as multi-turn `messages` (assert the first
messages carry the prior turns and the final message carries the fresh
context+question); malformed/oversized history is dropped/capped before the model
call; the de-repeat and trust-first rules are present in the system prompt (assert
on the new phrasings). Keep all existing status-code, key-safety, and
context-serialization assertions green (the final user message must still contain
the stringified context).

**File**: `Tests/AppCoreTests/CoachEngineTests.swift`

Add cases for the soreness-vs-pain split (soreness → no `safetyFlag`, calm mood;
sharp pain → `safetyFlag` + `concerned`), the raised hard-run threshold (an easy
5-mile run no longer forces recovery framing), and the turn-aware check-in
question (same question not repeated across consecutive coach turns; rotates).
Update any existing assertions that hardcoded the "How are the legs?" tail.

## Reused existing code

- `CoachEngine.reply(to:context:asOf:)` and the `CoachIntent` classifier from
  `Sources/AppCore/CoachEngine.swift` (glossary entry: `CoachEngine`) — extended,
  not rewritten; the pure/deterministic contract and safety-wins-over-build
  behavior are preserved.
- `RemoteCoach.reply` + `RequestBody`/`ResponseBody` from
  `Sources/AppCore/Coach/RemoteCoach.swift` — the request shape gains `history`;
  the response contract and `CoachError` fallback semantics are unchanged.
- `ChatMessage` (role/text/mood/safetyFlag) from
  `Sources/AppCore/AskCoachView.swift` — the existing thread state is the source
  of the history we now forward; the turn type mirrors its role/text.
- `SYSTEM_PROMPT` + `FORMAT` structured-output schema in `api/coach.ts` — the
  prompt is edited in place; the `{text, mood, safetyFlag}` JSON schema and the
  refusal/malformed-JSON graceful-degrade paths stay as-is.
- `TodayState` context serialization and the `MAX_CONTEXT_BYTES` bound in
  `api/coach.ts` — reused as the model for bounding the new `history` payload.

## Scenarios to Demonstrate

- **Multi-turn chat that builds instead of repeating** — user asks "run or
  rest?", answers a follow-up, asks again; the coach references the earlier
  answer and does NOT re-ask "how are the legs?".
- **Mild soreness, no lockdown** — "my legs are a little sore after Sunday's run"
  gets calm normal-training reassurance, no shield flag, upbeat/steady mood.
- **Real pain, caution holds** — "sharp pain in my knee that's getting worse"
  still triggers the clinician advice, rest, and `safetyFlag`.
- **Easy 5-miler is not "hard"** — an easy 5-mile run in context; asking "what
  should I do today?" gets normal go-ahead coaching, not a forced recovery day.
- **Genuine load spike still steers to rest** — a true one-week spike vs.
  baseline still yields caution + `safetyFlag` (guardrail intact).
- **Declared build affirmed, not flagged** — `trainingPhase: building` with a
  steady ~10%/week climb gets affirmation, no rest nudge, no safety flag.
- **Rotating check-in** — across several turns, the closing question varies
  (legs → sleep → weekly goal) or is omitted when it wouldn't add anything.
- **Empty chat state** — first-open prompt with no history renders unchanged.
