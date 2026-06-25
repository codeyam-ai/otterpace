import { describe, it, expect, vi, beforeEach } from "vitest";

// The /api/account/* handlers are thin glue over the _lib/account helpers.
// Mock that module so we assert each handler's request validation, status
// codes, last-write-wins behavior, and the prefs health-field guard — without
// any network call.
const lib = vi.hoisted(() => ({
  getPrefs: vi.fn(),
  upsertPrefs: vi.fn(),
  getHealth: vi.fn(),
  upsertHealth: vi.fn(),
  deleteHealth: vi.fn(),
  // Pure helpers are re-exported through the mock with real-ish behavior.
  prefsContainHealthFields: vi.fn((p: Record<string, unknown>) =>
    Object.keys(p).some((k) => ["health", "steps"].includes(k.toLowerCase())),
  ),
  incomingWins: vi.fn(
    (stored: string | null, incoming: string) => !stored || Date.parse(incoming) > Date.parse(stored),
  ),
}));
vi.mock("../../api/_lib/account.ts", () => lib);

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

beforeEach(() => {
  vi.clearAllMocks();
  vi.spyOn(console, "error").mockImplementation(() => {});
  lib.prefsContainHealthFields.mockImplementation((p: Record<string, unknown>) =>
    Object.keys(p).some((k) => ["health", "steps"].includes(k.toLowerCase())),
  );
  lib.incomingWins.mockImplementation(
    (stored: string | null, incoming: string) => !stored || Date.parse(incoming) > Date.parse(stored),
  );
});

describe("account/sync (prefs)", () => {
  it("GET 400s without a user id", async () => {
    const res = await run(sync, { method: "GET", query: {} });
    expect(res.statusCode).toBe(400);
  });

  it("GET returns found:false when no row", async () => {
    lib.getPrefs.mockResolvedValue(null);
    const res = await run(sync, { method: "GET", query: { userId: "u1" } });
    expect(res.statusCode).toBe(200);
    expect(res.body).toEqual({ found: false });
  });

  it("GET returns the stored row", async () => {
    lib.getPrefs.mockResolvedValue({ user_id: "u1", prefs: { goalSteps: 10000 }, updated_at: "t" });
    const res = await run(sync, { method: "GET", query: { userId: "u1" } });
    expect(res.body).toMatchObject({ found: true, user_id: "u1" });
  });

  it("PUT 400s without the required fields", async () => {
    const res = await run(sync, { method: "PUT", body: { userId: "u1" } });
    expect(res.statusCode).toBe(400);
  });

  it("PUT rejects a payload carrying health fields", async () => {
    const res = await run(sync, {
      method: "PUT",
      body: { userId: "u1", prefs: { goalSteps: 10000, steps: 6420 }, updatedAt: "2026-06-25T00:00:00Z" },
    });
    expect(res.statusCode).toBe(400);
    expect(res.body).toMatchObject({ error: "health_fields_not_allowed_on_prefs" });
    expect(lib.upsertPrefs).not.toHaveBeenCalled();
  });

  it("PUT upserts when the incoming payload is newer", async () => {
    lib.getPrefs.mockResolvedValue({ user_id: "u1", prefs: { goalSteps: 8000 }, updated_at: "2026-06-24T00:00:00Z" });
    lib.upsertPrefs.mockResolvedValue(undefined);
    const res = await run(sync, {
      method: "PUT",
      body: { userId: "u1", prefs: { goalSteps: 12000 }, updatedAt: "2026-06-25T00:00:00Z" },
    });
    expect(res.statusCode).toBe(200);
    expect(res.body).toMatchObject({ applied: true });
    expect(lib.upsertPrefs).toHaveBeenCalledOnce();
  });

  it("PUT does NOT upsert when the stored row is newer (remote wins)", async () => {
    lib.getPrefs.mockResolvedValue({ user_id: "u1", prefs: { goalSteps: 15000 }, updated_at: "2026-06-26T00:00:00Z" });
    const res = await run(sync, {
      method: "PUT",
      body: { userId: "u1", prefs: { goalSteps: 12000 }, updatedAt: "2026-06-25T00:00:00Z" },
    });
    expect(res.statusCode).toBe(200);
    expect(res.body).toMatchObject({ applied: false, prefs: { goalSteps: 15000 } });
    expect(lib.upsertPrefs).not.toHaveBeenCalled();
  });

  it("405s on an unsupported method", async () => {
    const res = await run(sync, { method: "DELETE", body: {} });
    expect(res.statusCode).toBe(405);
  });

  it("502s on a helper error", async () => {
    lib.getPrefs.mockRejectedValue(new Error("supabase down"));
    const res = await run(sync, { method: "GET", query: { userId: "u1" } });
    expect(res.statusCode).toBe(502);
  });
});

describe("account/health", () => {
  it("GET 400s without a user id", async () => {
    const res = await run(health, { method: "GET", query: {} });
    expect(res.statusCode).toBe(400);
  });

  it("PUT upserts a newer health snapshot", async () => {
    lib.getHealth.mockResolvedValue(null);
    lib.upsertHealth.mockResolvedValue(undefined);
    const res = await run(health, {
      method: "PUT",
      body: { userId: "u1", health: { steps: 6420 }, updatedAt: "2026-06-25T00:00:00Z" },
    });
    expect(res.statusCode).toBe(200);
    expect(res.body).toMatchObject({ applied: true });
    expect(lib.upsertHealth).toHaveBeenCalledOnce();
  });

  it("DELETE removes the row (opt-out / delete data)", async () => {
    lib.deleteHealth.mockResolvedValue(undefined);
    const res = await run(health, { method: "DELETE", body: { userId: "u1" } });
    expect(res.statusCode).toBe(200);
    expect(res.body).toEqual({ ok: true });
    expect(lib.deleteHealth).toHaveBeenCalledWith("u1");
  });

  it("DELETE accepts the user id from the query string too", async () => {
    lib.deleteHealth.mockResolvedValue(undefined);
    const res = await run(health, { method: "DELETE", query: { userId: "u2" }, body: {} });
    expect(res.statusCode).toBe(200);
    expect(lib.deleteHealth).toHaveBeenCalledWith("u2");
  });

  it("DELETE 400s without a user id", async () => {
    const res = await run(health, { method: "DELETE", body: {} });
    expect(res.statusCode).toBe(400);
  });

  it("502s on a helper error", async () => {
    lib.getHealth.mockRejectedValue(new Error("boom"));
    const res = await run(health, { method: "GET", query: { userId: "u1" } });
    expect(res.statusCode).toBe(502);
  });
});
