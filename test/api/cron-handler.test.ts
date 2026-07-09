import { describe, it, expect, afterEach, vi } from "vitest";
import handler from "../../api/cron/movement-nudge.ts";

// Handler test for the movement-nudge cron. The scan/deliver path is exercised
// through the pure `shouldNudge` policy (see nudge.test.ts); here we verify the
// CRON_SECRET auth guard so the endpoint can't be triggered publicly.

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
