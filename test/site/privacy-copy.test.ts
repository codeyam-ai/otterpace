import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

// The privacy policy is the one copy surface with a correctness stake rather
// than a tidiness one: it tells users where their data goes.
//
// Regression: it said a connected AI coach sends the question, activity summary,
// personalization profile and journal slice "on to Anthropic" — false for anyone
// using an OpenAI or Gemini key, long after both worked. A policy that names the
// wrong data recipient is an accuracy problem, so this is the durable guard that
// keeps it honest the next time a provider is added.

const HERE = dirname(fileURLToPath(import.meta.url));
const PRIVACY = readFileSync(resolve(HERE, "../../site/privacy.html"), "utf8");

/** Every provider the app can route to, as the policy would name them. */
const PROVIDERS = ["Anthropic", "OpenAI", "Gemini"];

describe("privacy policy — AI coach disclosure", () => {
  it("names every supported provider if it names any", () => {
    const named = PROVIDERS.filter((p) => PRIVACY.includes(p));
    if (named.length === 0) return; // a provider-agnostic policy is also fine
    expect(named).toEqual(PROVIDERS);
  });

  // The load-bearing sentence: the destination is whichever key the user
  // connected, not a fixed vendor.
  it("says the destination is the provider the user connected", () => {
    expect(PRIVACY).toMatch(/provider whose key you connected/i);
  });

  it("does not claim a single fixed destination", () => {
    for (const p of PROVIDERS) {
      expect(PRIVACY).not.toMatch(new RegExp(`on to ${p}\\b`, "i"));
    }
  });

  // The rewrite must not have weakened any disclosure it already made. These are
  // the commitments the policy carried before, asserted so a future edit for
  // brevity cannot quietly drop one.
  it("keeps every existing disclosure", () => {
    expect(PRIVACY).toMatch(/Keychain/);                       // key never on our server
    expect(PRIVACY).toMatch(/don't retain your questions/i);
    expect(PRIVACY).toMatch(/never sent to analytics/i);
    expect(PRIVACY).toMatch(/two weeks/i);                     // bounded journal slice
    expect(PRIVACY).toMatch(/personalization profile/i);
    expect(PRIVACY).toMatch(/journal entries/i);
  });
});
