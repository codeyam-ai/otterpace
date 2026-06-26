import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import {
  prefsEndpoint,
  healthEndpoint,
  prefsContainHealthFields,
  incomingWins,
  getPrefs,
  upsertPrefs,
  getHealth,
  upsertHealth,
  deleteHealth,
} from "../../api/_lib/account.ts";

// Unit tests for the shared account-sync + Supabase helpers. Network calls are
// exercised against a stubbed global `fetch` (no real Supabase request); the
// pure helpers are tested directly.

const ENV = {
  SUPABASE_URL: "https://db.example.co",
  SUPABASE_SERVICE_ROLE_KEY: "service-role",
};

function fetchReturning(status: number, body: unknown) {
  return vi.fn().mockResolvedValue({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  });
}

beforeEach(() => {
  Object.assign(process.env, ENV);
});
afterEach(() => {
  vi.restoreAllMocks();
});

describe("pure helpers", () => {
  it("builds the table endpoints from SUPABASE_URL", () => {
    expect(prefsEndpoint()).toBe("https://db.example.co/rest/v1/account_prefs");
    expect(healthEndpoint()).toBe("https://db.example.co/rest/v1/account_health");
  });

  it("rejects prefs payloads that carry health fields", () => {
    expect(prefsContainHealthFields({ goalSteps: 10000 })).toBe(false);
    expect(prefsContainHealthFields({ goalSteps: 10000, steps: 6420 })).toBe(true);
    expect(prefsContainHealthFields({ health: {} })).toBe(true);
    expect(prefsContainHealthFields({ HEARTRATE: 60 })).toBe(true); // case-insensitive
  });

  it("catches health fields nested inside objects and arrays (not just top-level)", () => {
    expect(prefsContainHealthFields({ profile: { steps: 6420 } })).toBe(true);
    expect(prefsContainHealthFields({ list: [{ ok: 1 }, { workouts: [] }] })).toBe(true);
    expect(prefsContainHealthFields({ a: { b: { c: { restingHeartRate: 52 } } } })).toBe(true);
    // A clean, nested-but-health-free payload still passes.
    expect(prefsContainHealthFields({ ui: { theme: "light", goals: [10000] } })).toBe(false);
  });

  it("last-write-wins: incoming wins only when strictly newer or no stored row", () => {
    expect(incomingWins(null, "2026-06-25T00:00:00Z")).toBe(true);
    expect(incomingWins("2026-06-24T00:00:00Z", "2026-06-25T00:00:00Z")).toBe(true);
    expect(incomingWins("2026-06-25T00:00:00Z", "2026-06-24T00:00:00Z")).toBe(false);
    expect(incomingWins("2026-06-25T00:00:00Z", "2026-06-25T00:00:00Z")).toBe(false); // equal → stored stays
  });
});

describe("supabase reads/writes", () => {
  it("getPrefs returns the first row or null", async () => {
    const row = { user_id: "u1", prefs: { goalSteps: 10000 }, updated_at: "2026-06-25T00:00:00Z" };
    vi.stubGlobal("fetch", fetchReturning(200, [row]));
    expect(await getPrefs("u1")).toEqual(row);

    vi.stubGlobal("fetch", fetchReturning(200, []));
    expect(await getPrefs("u1")).toBeNull();
  });

  it("getPrefs throws on a non-ok read", async () => {
    vi.stubGlobal("fetch", fetchReturning(500, {}));
    await expect(getPrefs("u1")).rejects.toThrow(/supabase_read_failed/);
  });

  it("upsertPrefs posts with merge-duplicates", async () => {
    const f = fetchReturning(201, {});
    vi.stubGlobal("fetch", f);
    await upsertPrefs({ user_id: "u1", prefs: { goalSteps: 12000 }, updated_at: "2026-06-25T00:00:00Z" });
    expect(f).toHaveBeenCalledOnce();
    const [, init] = f.mock.calls[0];
    expect(init.method).toBe("POST");
    expect(init.headers.Prefer).toContain("merge-duplicates");
  });

  it("getHealth / upsertHealth hit the health table", async () => {
    const row = { user_id: "u1", health: { steps: 6420 }, updated_at: "2026-06-25T00:00:00Z" };
    const f = fetchReturning(200, [row]);
    vi.stubGlobal("fetch", f);
    expect(await getHealth("u1")).toEqual(row);
    expect(f.mock.calls[0][0]).toContain("account_health");
  });

  it("deleteHealth tolerates a 404 (already gone)", async () => {
    vi.stubGlobal("fetch", fetchReturning(404, {}));
    await expect(deleteHealth("u1")).resolves.toBeUndefined();
  });

  it("deleteHealth throws on a real failure", async () => {
    vi.stubGlobal("fetch", fetchReturning(500, {}));
    await expect(deleteHealth("u1")).rejects.toThrow(/supabase_delete_failed/);
  });
});
