import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import {
  pushEndpoint,
  addPushToken,
  removePushToken,
  listNudgeCandidates,
  mirrorMovement,
  type PushRow,
} from "../../api/_lib/account.ts";

// Unit tests for the account_push store helpers backing the server-driven nudge.
// Supabase calls go through a stubbed global `fetch`: a GET returns the current
// row, a POST (upsert) / DELETE is captured so we can assert the mutation shape.

const ENV = { SUPABASE_URL: "https://db.example.co", SUPABASE_SERVICE_ROLE_KEY: "service-role" };
const NOW = "2026-07-08T15:00:00.000Z";

function row(over: Partial<PushRow> = {}): PushRow {
  return {
    user_id: "u_1",
    tokens: ["tok_a"],
    platform: "ios",
    last_movement_at: null,
    inactivity_hours: null,
    last_nudge_sent_at: null,
    updated_at: NOW,
    ...over,
  };
}

// A fetch stub: GETs return `getBody`; POST/DELETE record the call and return 200.
function stubFetch(getBody: unknown) {
  const calls: Array<{ url: string; method: string; body: unknown }> = [];
  const fn = vi.fn(async (url: string, init?: RequestInit) => {
    const method = (init?.method ?? "GET").toUpperCase();
    calls.push({ url, method, body: init?.body ? JSON.parse(init.body as string) : undefined });
    return { ok: true, status: 200, json: async () => getBody } as Response;
  });
  vi.stubGlobal("fetch", fn);
  return calls;
}

beforeEach(() => Object.assign(process.env, ENV));
afterEach(() => vi.restoreAllMocks());

describe("pushEndpoint", () => {
  it("builds the table endpoint from SUPABASE_URL", () => {
    expect(pushEndpoint()).toBe("https://db.example.co/rest/v1/account_push");
  });
});

describe("addPushToken", () => {
  it("appends a new token to the existing set without touching other state", async () => {
    const calls = stubFetch([row({ tokens: ["tok_a"], last_nudge_sent_at: "2026-07-08T10:00:00Z" })]);
    await addPushToken("u_1", "tok_b", "ios", NOW);
    const upsert = calls.find((c) => c.method === "POST")!.body as PushRow;
    expect(new Set(upsert.tokens)).toEqual(new Set(["tok_a", "tok_b"]));
    expect(upsert.last_nudge_sent_at).toBe("2026-07-08T10:00:00Z"); // preserved
  });

  it("is idempotent — re-registering the same token does not duplicate it", async () => {
    const calls = stubFetch([row({ tokens: ["tok_a"] })]);
    await addPushToken("u_1", "tok_a", "ios", NOW);
    const upsert = calls.find((c) => c.method === "POST")!.body as PushRow;
    expect(upsert.tokens).toEqual(["tok_a"]);
  });
});

describe("removePushToken", () => {
  it("deletes the whole row when the last token is removed", async () => {
    const calls = stubFetch([row({ tokens: ["tok_a"] })]);
    await removePushToken("u_1", "tok_a", NOW);
    expect(calls.some((c) => c.method === "DELETE")).toBe(true);
    expect(calls.some((c) => c.method === "POST")).toBe(false); // no upsert of an empty set
  });

  it("keeps the row when other tokens remain", async () => {
    const calls = stubFetch([row({ tokens: ["tok_a", "tok_b"] })]);
    await removePushToken("u_1", "tok_a", NOW);
    const upsert = calls.find((c) => c.method === "POST")!.body as PushRow;
    expect(upsert.tokens).toEqual(["tok_b"]);
  });
});

describe("mirrorMovement", () => {
  it("does nothing when the user has no push row (never created one)", async () => {
    const calls = stubFetch([]); // getPush → no row
    await mirrorMovement("u_1", NOW, 3, NOW);
    expect(calls.some((c) => c.method === "POST")).toBe(false);
  });

  it("updates the movement fields on an existing row", async () => {
    const calls = stubFetch([row({ tokens: ["tok_a"] })]);
    await mirrorMovement("u_1", "2026-07-08T14:00:00Z", 4, NOW);
    const upsert = calls.find((c) => c.method === "POST")!.body as PushRow;
    expect(upsert.last_movement_at).toBe("2026-07-08T14:00:00Z");
    expect(upsert.inactivity_hours).toBe(4);
    expect(upsert.tokens).toEqual(["tok_a"]); // token list untouched
  });
});

describe("listNudgeCandidates", () => {
  it("drops rows with no tokens (they can't receive a push)", async () => {
    stubFetch([
      row({ user_id: "u_1", tokens: ["tok_a"], last_movement_at: NOW }),
      row({ user_id: "u_2", tokens: [], last_movement_at: NOW }),
    ]);
    const candidates = await listNudgeCandidates();
    expect(candidates.map((c) => c.user_id)).toEqual(["u_1"]);
  });
});
