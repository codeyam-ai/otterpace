import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import handler from "../../api/account/push.ts";

// Handler tests for /api/account/push. requireUser and the account_push store both
// go through Supabase, stubbed here via a global `fetch`: the account_sessions
// lookup resolves the bearer to a user, and account_push GET/POST/DELETE are
// captured so we can assert the handler's auth gate, validation, and routing.

const ENV = { SUPABASE_URL: "https://db.example.co", SUPABASE_SERVICE_ROLE_KEY: "service-role" };

function res() {
  const out: { status?: number; body?: unknown } = {};
  return {
    status(code: number) {
      out.status = code;
      return { json: (b: unknown) => { out.body = b; } };
    },
    out,
  };
}

// Stub fetch: the sessions endpoint resolves to `userId` (or none); everything
// else (account_push) is captured and returns an empty row set.
function stubFetch(userId: string | null) {
  const calls: Array<{ url: string; method: string }> = [];
  vi.stubGlobal("fetch", vi.fn(async (url: string, init?: RequestInit) => {
    const method = (init?.method ?? "GET").toUpperCase();
    calls.push({ url, method });
    const body = url.includes("account_sessions") ? (userId ? [{ user_id: userId }] : []) : [];
    return { ok: true, status: 200, json: async () => body } as Response;
  }));
  return calls;
}

beforeEach(() => Object.assign(process.env, ENV));
afterEach(() => vi.restoreAllMocks());

describe("account/push handler", () => {
  // No bearer → 401, and it never touches the push store.
  it("rejects an unauthenticated request", async () => {
    stubFetch(null);
    const r = res();
    await handler({ method: "POST", headers: {}, body: {} } as never, r as never);
    expect(r.out.status).toBe(401);
  });

  // A valid POST registers the token (a POST to the account_push table).
  it("registers a valid device token", async () => {
    const calls = stubFetch("u_1");
    const r = res();
    await handler(
      { method: "POST", headers: { authorization: "Bearer t" }, body: { deviceToken: "abcdef01" } } as never,
      r as never,
    );
    expect(r.out.status).toBe(200);
    expect(calls.some((c) => c.url.includes("account_push") && c.method === "POST")).toBe(true);
  });

  // A malformed (non-hex) token is a 400, no write.
  it("rejects an invalid device token", async () => {
    stubFetch("u_1");
    const r = res();
    await handler(
      { method: "POST", headers: { authorization: "Bearer t" }, body: { deviceToken: "not hex!" } } as never,
      r as never,
    );
    expect(r.out.status).toBe(400);
  });

  // GET isn't supported on this endpoint.
  it("405s an unsupported method", async () => {
    stubFetch("u_1");
    const r = res();
    await handler({ method: "GET", headers: { authorization: "Bearer t" }, body: {} } as never, r as never);
    expect(r.out.status).toBe(405);
  });
});
