import { describe, it, expect, vi, beforeEach } from "vitest";

// The /api/account/* handlers are thin glue over the _lib/account helpers, now
// gated by requireUser (session-token auth). Mock both modules so we assert each
// handler's auth gating, request validation, status codes, last-write-wins
// behavior, and the prefs health-field guard — without any network call.
const lib = vi.hoisted(() => ({
  getPrefs: vi.fn(),
  upsertPrefs: vi.fn(),
  getHealth: vi.fn(),
  upsertHealth: vi.fn(),
  deleteHealth: vi.fn(),
  mirrorMovement: vi.fn(),
  prefsContainHealthFields: vi.fn((p: Record<string, unknown>) =>
    Object.keys(p).some((k) => ["health", "steps"].includes(k.toLowerCase())),
  ),
  incomingWins: vi.fn(
    (stored: string | null, incoming: string) => !stored || Date.parse(incoming) > Date.parse(stored),
  ),
}));
vi.mock("../../api/_lib/account.ts", () => lib);

const session = vi.hoisted(() => ({ requireUser: vi.fn() }));
vi.mock("../../api/_lib/session.ts", () => session);

import sync from "../../api/account/sync.ts";
import health from "../../api/account/health.ts";

function makeRes() {
  return {
    statusCode: 0,
    body: undefined as unknown,
    headers: {} as Record<string, string>,
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
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function run(handler: any, req: any) {
  const res = makeRes();
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return Promise.resolve(handler(req as any, res as any)).then(() => res);
}

// A request carrying a valid session for user "u1".
const AUTH = { headers: { authorization: "Bearer tok-u1" } };

beforeEach(() => {
  vi.clearAllMocks();
  vi.spyOn(console, "error").mockImplementation(() => {});
  session.requireUser.mockResolvedValue("u1"); // authenticated as u1 by default
  lib.prefsContainHealthFields.mockImplementation((p: Record<string, unknown>) =>
    Object.keys(p).some((k) => ["health", "steps"].includes(k.toLowerCase())),
  );
  lib.incomingWins.mockImplementation(
    (stored: string | null, incoming: string) => !stored || Date.parse(incoming) > Date.parse(stored),
  );
});

describe("account auth gating (BE-1)", () => {
  it("sync 401s without a valid session", async () => {
    session.requireUser.mockResolvedValue(null);
    const res = await run(sync, { method: "GET", headers: {} });
    expect(res.statusCode).toBe(401);
    expect(lib.getPrefs).not.toHaveBeenCalled();
  });

  it("health 401s without a valid session", async () => {
    session.requireUser.mockResolvedValue(null);
    const res = await run(health, { method: "GET", headers: {} });
    expect(res.statusCode).toBe(401);
    expect(lib.getHealth).not.toHaveBeenCalled();
  });

  // The core IDOR fix: the user id comes ONLY from the verified session, never
  // from a client-supplied field. A body claiming someone else's id is ignored.
  it("sync ignores a client-supplied userId and uses the authenticated one", async () => {
    lib.getPrefs.mockResolvedValue(null);
    lib.upsertPrefs.mockResolvedValue(undefined);
    const res = await run(sync, {
      method: "PUT",
      ...AUTH,
      body: { userId: "victim", prefs: { goalSteps: 12000 }, updatedAt: "2026-06-25T00:00:00Z" },
    });
    expect(res.statusCode).toBe(200);
    // Stored under "u1" (the session), NOT "victim" (the body).
    expect(lib.upsertPrefs).toHaveBeenCalledWith(
      expect.objectContaining({ user_id: "u1" }),
    );
  });

  it("health DELETE removes only the authenticated user's row, ignoring the body", async () => {
    lib.deleteHealth.mockResolvedValue(undefined);
    const res = await run(health, { method: "DELETE", ...AUTH, body: { userId: "victim" } });
    expect(res.statusCode).toBe(200);
    expect(lib.deleteHealth).toHaveBeenCalledWith("u1");
    expect(lib.deleteHealth).not.toHaveBeenCalledWith("victim");
  });
});

describe("account/sync (prefs)", () => {
  it("GET returns found:false when no row", async () => {
    lib.getPrefs.mockResolvedValue(null);
    const res = await run(sync, { method: "GET", ...AUTH });
    expect(res.statusCode).toBe(200);
    expect(res.body).toEqual({ found: false });
  });

  it("GET returns the stored row", async () => {
    lib.getPrefs.mockResolvedValue({ user_id: "u1", prefs: { goalSteps: 10000 }, updated_at: "t" });
    const res = await run(sync, { method: "GET", ...AUTH });
    expect(res.body).toMatchObject({ found: true, user_id: "u1" });
  });

  it("PUT 400s without the required fields", async () => {
    const res = await run(sync, { method: "PUT", ...AUTH, body: {} });
    expect(res.statusCode).toBe(400);
  });

  it("PUT rejects a payload carrying health fields", async () => {
    const res = await run(sync, {
      method: "PUT",
      ...AUTH,
      body: { prefs: { goalSteps: 10000, steps: 6420 }, updatedAt: "2026-06-25T00:00:00Z" },
    });
    expect(res.statusCode).toBe(400);
    expect(res.body).toMatchObject({ error: "health_fields_not_allowed_on_prefs" });
    expect(lib.upsertPrefs).not.toHaveBeenCalled();
  });

  it("PUT 413s on an oversized prefs payload", async () => {
    const huge = { blob: "x".repeat(20 * 1024) };
    const res = await run(sync, {
      method: "PUT",
      ...AUTH,
      body: { prefs: huge, updatedAt: "2026-06-25T00:00:00Z" },
    });
    expect(res.statusCode).toBe(413);
    expect(lib.upsertPrefs).not.toHaveBeenCalled();
  });

  it("PUT upserts when the incoming payload is newer", async () => {
    lib.getPrefs.mockResolvedValue({ user_id: "u1", prefs: { goalSteps: 8000 }, updated_at: "2026-06-24T00:00:00Z" });
    lib.upsertPrefs.mockResolvedValue(undefined);
    const res = await run(sync, {
      method: "PUT",
      ...AUTH,
      body: { prefs: { goalSteps: 12000 }, updatedAt: "2026-06-25T00:00:00Z" },
    });
    expect(res.statusCode).toBe(200);
    expect(res.body).toMatchObject({ applied: true });
    expect(lib.upsertPrefs).toHaveBeenCalledOnce();
  });

  it("PUT does NOT upsert when the stored row is newer (remote wins)", async () => {
    lib.getPrefs.mockResolvedValue({ user_id: "u1", prefs: { goalSteps: 15000 }, updated_at: "2026-06-26T00:00:00Z" });
    const res = await run(sync, {
      method: "PUT",
      ...AUTH,
      body: { prefs: { goalSteps: 12000 }, updatedAt: "2026-06-25T00:00:00Z" },
    });
    expect(res.statusCode).toBe(200);
    expect(res.body).toMatchObject({ applied: false, prefs: { goalSteps: 15000 } });
    expect(lib.upsertPrefs).not.toHaveBeenCalled();
  });

  it("405s on an unsupported method", async () => {
    const res = await run(sync, { method: "DELETE", ...AUTH, body: {} });
    expect(res.statusCode).toBe(405);
  });

  it("502s on a helper error", async () => {
    lib.getPrefs.mockRejectedValue(new Error("supabase down"));
    const res = await run(sync, { method: "GET", ...AUTH });
    expect(res.statusCode).toBe(502);
  });
});

describe("account/health", () => {
  it("PUT upserts a newer health snapshot", async () => {
    lib.getHealth.mockResolvedValue(null);
    lib.upsertHealth.mockResolvedValue(undefined);
    const res = await run(health, {
      method: "PUT",
      ...AUTH,
      body: { health: { steps: 6420 }, updatedAt: "2026-06-25T00:00:00Z" },
    });
    expect(res.statusCode).toBe(200);
    expect(res.body).toMatchObject({ applied: true });
    expect(lib.upsertHealth).toHaveBeenCalledOnce();
  });

  it("PUT 413s on an oversized health payload", async () => {
    const huge = { blob: "x".repeat(80 * 1024) };
    const res = await run(health, {
      method: "PUT",
      ...AUTH,
      body: { health: huge, updatedAt: "2026-06-25T00:00:00Z" },
    });
    expect(res.statusCode).toBe(413);
    expect(lib.upsertHealth).not.toHaveBeenCalled();
  });

  it("DELETE removes the row (opt-out / delete data)", async () => {
    lib.deleteHealth.mockResolvedValue(undefined);
    const res = await run(health, { method: "DELETE", ...AUTH });
    expect(res.statusCode).toBe(200);
    expect(res.body).toEqual({ ok: true });
    expect(lib.deleteHealth).toHaveBeenCalledWith("u1");
  });

  it("502s on a helper error", async () => {
    lib.getHealth.mockRejectedValue(new Error("boom"));
    const res = await run(health, { method: "GET", ...AUTH });
    expect(res.statusCode).toBe(502);
  });
});

// The movement-heartbeat branch, and the timezone it now carries. `mirrorMovement`
// was missing from the mock above until this block existed, which is the tell: no
// test had ever driven the handler down this path, so timeZoneFrom — the shape
// guard standing between a client string and both the database and Intl — shipped
// with no coverage at all.
describe("account/health movement mirror (timezone)", () => {
  const LAST_MOVEMENT = "2026-07-15T10:00:00Z";
  const UPDATED_AT = "2026-06-25T00:00:00Z";
  const BASE = { lastMovementAt: LAST_MOVEMENT, inactivityHours: 2 };

  const putHealth = (health_: Record<string, unknown>) =>
    run(health, { method: "PUT", ...AUTH, body: { health: health_, updatedAt: UPDATED_AT } });

  beforeEach(() => {
    lib.getHealth.mockResolvedValue(null);
    lib.upsertHealth.mockResolvedValue(undefined);
    lib.mirrorMovement.mockResolvedValue(undefined);
  });

  it("forwards a valid IANA zone to the push row", async () => {
    await putHealth({ ...BASE, timeZone: "America/New_York" });
    expect(lib.mirrorMovement).toHaveBeenCalledWith("u1", LAST_MOVEMENT, 2, UPDATED_AT, "America/New_York", null);
  });

  // Underscores and a `+` are both legal in IANA identifiers; rejecting them
  // would silently push those users back onto the UTC fallback this fix removes.
  it("accepts the full legal identifier shape", async () => {
    for (const zone of ["Europe/Isle_of_Man", "Etc/GMT+5", "UTC"]) {
      lib.mirrorMovement.mockClear();
      await putHealth({ ...BASE, timeZone: zone });
      expect(lib.mirrorMovement).toHaveBeenCalledWith("u1", LAST_MOVEMENT, 2, UPDATED_AT, zone, null);
    }
  });

  // An older client that never learned to send one. Explicitly null, so the
  // helper preserves the stored zone rather than treating it as "clear it".
  it("passes null when the snapshot carries no zone", async () => {
    await putHealth(BASE);
    expect(lib.mirrorMovement).toHaveBeenCalledWith("u1", LAST_MOVEMENT, 2, UPDATED_AT, null, null);
  });

  // Every one of these must degrade to null (→ UTC fallback), never reach Intl
  // or the row: a traversal-shaped string, an unbounded blob, a non-string, and
  // an identifier with a character no real zone contains.
  it("rejects hostile or malformed zone values", async () => {
    for (const bad of ["../../etc/passwd", "x".repeat(65), "", "America/New York", "<script>", 42, null]) {
      lib.mirrorMovement.mockClear();
      await putHealth({ ...BASE, timeZone: bad });
      expect(lib.mirrorMovement).toHaveBeenCalledWith("u1", LAST_MOVEMENT, 2, UPDATED_AT, null, null);
    }
  });

  // The mirror is best-effort: it must never fail the sync the user asked for.
  it("still returns 200 when the mirror rejects", async () => {
    lib.mirrorMovement.mockRejectedValue(new Error("push row gone"));
    const res = await putHealth({ ...BASE, timeZone: "America/New_York" });
    expect(res.statusCode).toBe(200);
    expect(res.body).toMatchObject({ applied: true });
  });

  // No heartbeat fields → no mirror call at all, so a health-only sync from a
  // user who never granted push stays untouched.
  it("does not mirror a snapshot without movement fields", async () => {
    await putHealth({ steps: 6420, timeZone: "America/New_York" });
    expect(lib.mirrorMovement).not.toHaveBeenCalled();
  });
});
