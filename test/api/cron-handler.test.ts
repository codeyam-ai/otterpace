import { describe, it, expect, afterEach, beforeEach, vi } from "vitest";

// Handler test for the movement-nudge cron: the CRON_SECRET auth guard, and the
// scan/deliver loop itself. The nudge *policy* is proven pure in nudge.test.ts;
// what only a handler test can prove is the wiring — above all that the local
// hour is resolved PER USER inside the loop rather than once for the whole scan,
// which is the bug this feature fixes and which no policy-level test can catch.
const account = vi.hoisted(() => ({
  listNudgeCandidates: vi.fn(),
  stampNudgeSent: vi.fn(),
  removePushToken: vi.fn(),
}));
vi.mock("../../api/_lib/account.ts", () => account);

const apns = vi.hoisted(() => ({
  buildAps: vi.fn(() => ({ aps: {} })),
  providerToken: vi.fn(() => "jwt"),
  sendPush: vi.fn(),
}));
vi.mock("../../api/_lib/apns.ts", () => apns);

vi.mock("../../api/_lib/strava.ts", () => ({ env: vi.fn(() => "configured") }));

// `_lib/nudge.ts` is deliberately NOT mocked — shouldNudge and localHourIn are
// the real thing here, so these assertions exercise the actual quiet-hours math.
import handler from "../../api/cron/movement-nudge.ts";

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

afterEach(() => {
  delete process.env.CRON_SECRET;
  vi.restoreAllMocks();
});

describe("cron/movement-nudge handler", () => {
  // With a secret configured, a request without the matching bearer is rejected.
  it("rejects an unauthorized invocation when CRON_SECRET is set", async () => {
    process.env.CRON_SECRET = "s3cret";
    const r = res();
    await handler({ headers: {} } as never, r as never);
    expect(r.out.status).toBe(401);
  });

  // A wrong secret is also rejected.
  it("rejects a wrong bearer secret", async () => {
    process.env.CRON_SECRET = "s3cret";
    const r = res();
    await handler({ headers: { authorization: "Bearer nope" } } as never, r as never);
    expect(r.out.status).toBe(401);
  });
});

describe("cron/movement-nudge scan", () => {
  // 23:00 UTC — chosen because the zones genuinely disagree here:
  //   America/New_York 19:00 (awake)   Europe/London 00:00 (quiet)   UTC 23:00 (quiet)
  // A scan that resolved one hour for everyone could not produce different
  // answers for these users, so this instant is what makes the fix observable.
  const NOW = new Date("2026-07-15T23:00:00Z");

  // Idle for 8h against a 3h threshold, never nudged this spell: every user
  // below is due on the policy alone, leaving the local hour as the only variable.
  const candidate = (user_id: string, time_zone: string | null) => ({
    user_id,
    tokens: [`tok-${user_id}`],
    last_movement_at: "2026-07-15T15:00:00Z",
    inactivity_hours: 3,
    last_nudge_sent_at: null,
    time_zone,
  });

  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(NOW);
    account.listNudgeCandidates.mockReset();
    account.stampNudgeSent.mockReset().mockResolvedValue(undefined);
    account.removePushToken.mockReset().mockResolvedValue(undefined);
    apns.sendPush.mockReset().mockResolvedValue({ ok: true, status: 200 });
    vi.spyOn(console, "error").mockImplementation(() => {});
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  // The regression, stated directly: one instant, three users, three zones — and
  // only the one whose OWN clock says 19:00 gets a push. Before the fix all three
  // shared the 23:00 UTC hour and every one of them was silenced.
  it("resolves quiet hours per user, not once for the scan", async () => {
    account.listNudgeCandidates.mockResolvedValue([
      candidate("u-ny", "America/New_York"), // 19:00 local — awake
      candidate("u-utc", null),              // no zone → 23:00 UTC — quiet
      candidate("u-london", "Europe/London"), // 00:00 local — quiet
    ]);

    const r = res();
    await handler({ headers: {} } as never, r as never);

    expect(r.out.status).toBe(200);
    expect(r.out.body).toEqual({ scanned: 3, sent: 1 });
    expect(apns.sendPush).toHaveBeenCalledOnce();
    expect(apns.sendPush).toHaveBeenCalledWith("tok-u-ny", expect.anything(), "jwt");
    expect(account.stampNudgeSent).toHaveBeenCalledOnce();
    expect(account.stampNudgeSent).toHaveBeenCalledWith("u-ny", NOW.toISOString());
  });

  // A hostile or simply unknown identifier from one client must not throw out of
  // the loop and abort delivery for everyone scanned after it.
  it("keeps scanning past a row with an unusable zone", async () => {
    account.listNudgeCandidates.mockResolvedValue([
      candidate("u-junk", "Not/AZone"),     // unresolvable → UTC 23:00 — quiet
      candidate("u-ny", "America/New_York"), // still reached, still nudged
    ]);

    const r = res();
    await handler({ headers: {} } as never, r as never);

    expect(r.out.body).toEqual({ scanned: 2, sent: 1 });
    expect(apns.sendPush).toHaveBeenCalledWith("tok-u-ny", expect.anything(), "jwt");
  });

  // Delivery bookkeeping on the path a nudge actually takes: a token Apple no
  // longer recognizes is pruned, and a failed send is not stamped as sent.
  it("prunes an unregistered token and does not stamp a failed send", async () => {
    apns.sendPush.mockResolvedValue({ ok: false, status: 410, reason: "Unregistered" });
    account.listNudgeCandidates.mockResolvedValue([candidate("u-ny", "America/New_York")]);

    const r = res();
    await handler({ headers: {} } as never, r as never);

    expect(account.removePushToken).toHaveBeenCalledWith("u-ny", "tok-u-ny", NOW.toISOString());
    expect(account.stampNudgeSent).not.toHaveBeenCalled();
    expect(r.out.body).toEqual({ scanned: 1, sent: 0 });
  });

  // A backend failure is reported as 502 with the detail kept server-side.
  it("502s when the candidate scan fails", async () => {
    account.listNudgeCandidates.mockRejectedValue(new Error("supabase down"));
    const r = res();
    await handler({ headers: {} } as never, r as never);
    expect(r.out.status).toBe(502);
    expect(r.out.body).toEqual({ error: "movement_nudge_failed" });
  });
});
