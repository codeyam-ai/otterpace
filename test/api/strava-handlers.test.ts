import { describe, it, expect, vi, beforeEach } from "vitest";

// The four /api/strava/* handlers are thin glue over the _lib/strava helpers.
// Mock that module so we assert each handler's request validation, status
// codes, and response shaping without any network call.
const lib = vi.hoisted(() => ({
  getToken: vi.fn(),
  freshAccessToken: vi.fn(),
  fetchMappedActivities: vi.fn(),
  deleteToken: vi.fn(),
  exchangeCode: vi.fn(),
  upsertToken: vi.fn(),
}));
// Mock the network helpers but keep the PURE helpers (isValidDeviceKey,
// deviceKeyFromHeader) real so the handlers' validation is exercised for real.
vi.mock("../../api/_lib/strava.ts", async (importActual) => ({
  ...(await importActual<typeof import("../../api/_lib/strava.ts")>()),
  ...lib,
}));

// A well-formed device key: high-entropy, base64url, ≥16 chars.
const KEY = "dev_key_abcdef1234567890";

// The four routes now live behind one catch-all. Each suite below still calls
// "its" handler, but every call is dispatched through the real catch-all with
// the path segment set — so these tests exercise the routing too, not just the
// bodies. If a segment ever stops dispatching, every suite for it fails.
import stravaRoute from "../../api/strava.ts";

/** Invoke the catch-all as if the request arrived at /api/strava/<segment>. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function via(segment: string) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return (req: any, res: any) =>
    stravaRoute({ ...req, query: { ...(req?.query ?? {}), route: [segment] } }, res);
}

const activities = via("activities");
const callback = via("callback");
const disconnect = via("disconnect");
const exchange = via("exchange");

function makeRes() {
  return {
    statusCode: 0,
    body: undefined as unknown,
    headers: {} as Record<string, string>,
    ended: false,
    status(c: number) {
      this.statusCode = c;
      return this;
    },
    json(b: unknown) {
      this.body = b;
      return this;
    },
    setHeader(k: string, v: string) {
      this.headers[k] = v;
    },
    end() {
      this.ended = true;
    },
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function run(handler: any, req: any) {
  const res = makeRes();
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return Promise.resolve(handler(req as any, res as any)).then(() => res);
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.spyOn(console, "error").mockImplementation(() => {});
});

describe("strava/activities", () => {
  // A request without a device-key header is a 400.
  it("400s without a device key", async () => {
    const res = await run(activities, { headers: {} });
    expect(res.statusCode).toBe(400);
  });

  // A malformed (too short) device key is rejected before any lookup.
  it("400s on a malformed device key", async () => {
    const res = await run(activities, { headers: { "x-device-key": "short" } });
    expect(res.statusCode).toBe(400);
    expect(lib.getToken).not.toHaveBeenCalled();
  });

  // No stored token → not-connected with an empty list (not an error).
  it("reports not-connected when no token", async () => {
    lib.getToken.mockResolvedValue(null);
    const res = await run(activities, { headers: { "x-device-key": KEY } });
    expect(res.statusCode).toBe(200);
    expect(res.body).toEqual({ connected: false, activities: [] });
  });

  // With a token, it refreshes, fetches, and returns mapped activities.
  it("returns mapped activities when connected", async () => {
    lib.getToken.mockResolvedValue({ device_key: KEY });
    lib.freshAccessToken.mockResolvedValue("acc");
    lib.fetchMappedActivities.mockResolvedValue([{ id: "1" }]);
    const res = await run(activities, { headers: { "x-device-key": KEY } });
    expect(res.statusCode).toBe(200);
    expect(res.body).toEqual({ connected: true, activities: [{ id: "1" }] });
  });

  // A thrown helper error becomes a generic 502 (details logged server-side only).
  it("502s on a helper error", async () => {
    lib.getToken.mockRejectedValue(new Error("supabase down"));
    const res = await run(activities, { headers: { "x-device-key": KEY } });
    expect(res.statusCode).toBe(502);
  });
});

describe("strava/callback", () => {
  // A successful auth bounces back into the app scheme with code + state.
  it("redirects with the code and state", async () => {
    const res = await run(callback, { query: { code: "abc", state: KEY } });
    expect(res.statusCode).toBe(302);
    expect(res.headers.Location).toContain("otterpace://strava-callback?");
    expect(res.headers.Location).toContain("code=abc");
    expect(res.headers.Location).toContain(`state=${KEY}`);
  });

  // An OAuth error is forwarded in the redirect.
  it("forwards an oauth error", async () => {
    const res = await run(callback, { query: { error: "access_denied", state: KEY } });
    expect(res.headers.Location).toContain("error=access_denied");
  });

  // A malformed code / injection attempt is replaced with a safe error, and a
  // malformed state is dropped entirely (no arbitrary params reach the app).
  it("sanitizes a malformed code and drops a bad state", async () => {
    const res = await run(callback, { query: { code: "abc&evil=1", state: "../../x" } });
    expect(res.headers.Location).toContain("error=invalid_callback");
    expect(res.headers.Location).not.toContain("evil");
    expect(res.headers.Location).not.toContain("state=");
  });

  // No code and no error becomes an explicit invalid_callback error redirect.
  it("redirects with an error when nothing usable", async () => {
    const res = await run(callback, { query: {} });
    expect(res.headers.Location).toContain("error=invalid_callback");
  });
});

describe("strava/disconnect", () => {
  // Only POST is allowed.
  it("405s on non-POST", async () => {
    const res = await run(disconnect, { method: "GET", body: {} });
    expect(res.statusCode).toBe(405);
  });

  // Missing device key is a 400.
  it("400s without a device key", async () => {
    const res = await run(disconnect, { method: "POST", body: {} });
    expect(res.statusCode).toBe(400);
  });

  // A valid request deletes the token and returns ok.
  it("deletes the token", async () => {
    lib.deleteToken.mockResolvedValue(undefined);
    const res = await run(disconnect, { method: "POST", body: { deviceKey: KEY } });
    expect(res.statusCode).toBe(200);
    expect(res.body).toEqual({ ok: true });
    expect(lib.deleteToken).toHaveBeenCalledWith(KEY);
  });

  // A delete failure is a generic 502.
  it("502s on a delete error", async () => {
    lib.deleteToken.mockRejectedValue(new Error("nope"));
    const res = await run(disconnect, { method: "POST", body: { deviceKey: KEY } });
    expect(res.statusCode).toBe(502);
  });
});

describe("strava/exchange", () => {
  // Only POST is allowed.
  it("405s on non-POST", async () => {
    const res = await run(exchange, { method: "GET", body: {} });
    expect(res.statusCode).toBe(405);
  });

  // Both code and device key are required.
  it("400s without code or device key", async () => {
    const res = await run(exchange, { method: "POST", body: { code: "only-code" } });
    expect(res.statusCode).toBe(400);
  });

  // A malformed device key is rejected before any exchange.
  it("400s on a malformed device key", async () => {
    const res = await run(exchange, { method: "POST", body: { code: "c", deviceKey: "dev" } });
    expect(res.statusCode).toBe(400);
    expect(lib.exchangeCode).not.toHaveBeenCalled();
  });

  // A valid exchange stores tokens and returns the athlete first name only.
  it("exchanges and stores tokens", async () => {
    lib.exchangeCode.mockResolvedValue({
      access_token: "a",
      refresh_token: "r",
      expires_at: 123,
      athlete: { id: 7, firstname: "Sam" },
    });
    lib.upsertToken.mockResolvedValue(undefined);
    const res = await run(exchange, { method: "POST", body: { code: "c", deviceKey: KEY } });
    expect(res.statusCode).toBe(200);
    expect(res.body).toEqual({ connected: true, athleteName: "Sam" });
    expect(lib.upsertToken).toHaveBeenCalledOnce();
  });

  // A failed exchange is a generic 502.
  it("502s on an exchange error", async () => {
    lib.exchangeCode.mockRejectedValue(new Error("bad code"));
    const res = await run(exchange, { method: "POST", body: { code: "c", deviceKey: KEY } });
    expect(res.statusCode).toBe(502);
  });
});

// Regression guard for the consolidation itself.
//
// Collapsing four handler files into one catch-all freed three Vercel function
// slots, but it also moved routing from the filesystem (where it could not be
// wrong) into a switch (where it can). The paths are public contracts: the iOS
// client calls them, and /api/strava/callback is registered with Strava as the
// Authorization Callback Domain. If the catch-all ever stops serving a segment,
// OAuth breaks for every new connection — so every path is asserted to dispatch.
describe("strava catch-all routing", () => {
  const PUBLIC_ROUTES = ["activities", "callback", "disconnect", "exchange"];

  it("dispatches every previously-public path", async () => {
    for (const route of PUBLIC_ROUTES) {
      // A bare request: each route rejects it in its own way (400/405/302), but
      // NONE may fall through to the catch-all's 404 — that would mean the path
      // is no longer served at all.
      const res = await run(stravaRoute, { method: "GET", query: { route: [route] }, headers: {} });
      expect(res.statusCode, `/api/strava/${route} did not dispatch`).not.toBe(404);
    }
  });

  it("404s an unknown segment instead of falling into a real route", async () => {
    const res = await run(stravaRoute, { method: "GET", query: { route: ["nope"] }, headers: {} });
    expect(res.statusCode).toBe(404);
    expect(res.body).toEqual({ error: "not_found" });
  });

  it("takes the first segment, so a nested path cannot bypass the switch", async () => {
    // Vercel hands a catch-all its segments as an array; a deeper path must
    // still resolve to its route rather than silently 404.
    const res = await run(stravaRoute, {
      method: "POST",
      query: { route: ["disconnect", "extra"] },
      headers: {},
      body: { deviceKey: KEY },
    });
    expect(res.statusCode).not.toBe(404);
  });

  it("serves the OAuth callback as a redirect into the app scheme", async () => {
    // The single most breakage-sensitive path: Strava redirects a real browser
    // here, and the only correct outcome is a 302 into otterpace://.
    const res = await run(stravaRoute, {
      method: "GET",
      query: { route: ["callback"], code: "abc123", state: KEY },
      headers: {},
    });
    expect(res.statusCode).toBe(302);
    expect(res.headers.Location).toMatch(/^otterpace:\/\/strava-callback\?/);
  });
});
