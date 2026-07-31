---
title: "Get an API Key — Reach All Three Providers"
mode: ui
createdAt: "2026-07-30T21:05:00Z"
source: manual
order: 8
---

## Summary

The Settings → AI Coach card can only send you to the **Anthropic** console in
practice, even though Otterpace has supported OpenAI and Gemini keys since the
Multi-Provider BYOK release (`936b346`).

`CoachKeyField.swift:62` picks the link target from whichever provider it detects
in the pasted key, falling back to Anthropic while the field is empty:

```swift
let linkProvider = detected ?? .anthropic
```

That looks adaptive, and it is — but it inverts the actual user journey. You reach
the OpenAI or Gemini console link **only after pasting one of their keys**, and the
reason to visit that console is to *create a key you don't have yet*. So a user who
wants to use GPT or Gemini sees a row offering them an Anthropic key, with no path
to the other two. The links exist and are unreachable exactly when they're needed.

## What to build

Replace the single detected-provider link with one row — **"Get an API key"** —
that opens a `.confirmationDialog` listing all three providers. Tapping one opens
that provider's `consoleURL`.

- Same vertical space as the row it replaces (the card is already dense: provider
  rows, key field, Connect, and now "What Buddy sees").
- Uses the existing `CoachProvider.displayOrder` and `CoachProvider.consoleURL` —
  no new provider metadata.
- Keep the adaptive behavior where it genuinely helps: once a key **is** detected,
  the row may still lead with that provider, but every provider stays reachable.

## Scenarios

The dialog is a presentation, so seed its open state the way the codebase already
does for first-frame capture (`rbShowRaceEditor` / `rbShowCoachDataPreview`) rather
than via `.onAppear`:

| Scenario | State |
|---|---|
| Key Links — Picker Open | the dialog up, all three providers listed |
| Key Links — Row Closed | the collapsed row in the card, no key connected |

## Tests

`consoleURL` is non-nil for all three providers, and `displayOrder` yields the
stable Anthropic-first order the dialog renders — both pure logic, no view needed.

## Notes

Found while building Coach Data Preview, which added a row to this same card.
Deliberately kept out of that feature so each one's tests, scenarios, and journal
stay scoped to a single change.
