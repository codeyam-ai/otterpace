import { describe, it, expect } from "vitest";
import { shouldNudge, isQuietHour, DEFAULT_QUIET_HOURS, type NudgeState } from "../../api/_lib/nudge.ts";

// Unit tests for the pure server-side movement-nudge policy. No network — the
// decision is deterministic given (state, now, localHour), which is exactly why
// the cron delegates the "should we send?" call to it.

const NOW = new Date("2026-07-08T15:00:00Z"); // a non-quiet hour by default

function state(over: Partial<NudgeState> = {}): NudgeState {
  return { lastMovementAt: null, inactivityHours: 3, lastNudgeSentAt: null, ...over };
}

describe("isQuietHour", () => {
  // The default 21→8 window wraps past midnight: late night and early morning are quiet.
  it("treats a wrapping overnight window as quiet on both sides of midnight", () => {
    expect(isQuietHour(22)).toBe(true); // 10pm
    expect(isQuietHour(3)).toBe(true); // 3am
    expect(isQuietHour(8)).toBe(false); // 8am — window end is exclusive
    expect(isQuietHour(14)).toBe(false); // 2pm — clearly daytime
  });

  // A non-wrapping window is a simple half-open interval.
  it("handles a same-day window", () => {
    expect(isQuietHour(13, { startHour: 12, endHour: 14 })).toBe(true);
    expect(isQuietHour(14, { startHour: 12, endHour: 14 })).toBe(false);
  });

  // A degenerate start==end window is never quiet (so a misconfig can't mute everything).
  it("is never quiet when start equals end", () => {
    expect(isQuietHour(3, { startHour: 0, endHour: 0 })).toBe(false);
  });
});

describe("shouldNudge", () => {
  // No known movement → nothing to key off, so no nudge.
  it("does not nudge without a last-movement time", () => {
    expect(shouldNudge(state({ lastMovementAt: null }), NOW, 15)).toBe(false);
  });

  // Moved 30 minutes ago with a 3h threshold → still active, no nudge.
  it("does not nudge a user who moved recently", () => {
    const lastMovementAt = new Date(NOW.getTime() - 30 * 60_000).toISOString();
    expect(shouldNudge(state({ lastMovementAt }), NOW, 15)).toBe(false);
  });

  // Idle 4h past a 3h threshold → nudge.
  it("nudges a user idle past their threshold", () => {
    const lastMovementAt = new Date(NOW.getTime() - 4 * 3600_000).toISOString();
    expect(shouldNudge(state({ lastMovementAt }), NOW, 15)).toBe(true);
  });

  // Already nudged after the last movement → same idle window, don't nudge again.
  it("does not double-nudge within one idle window", () => {
    const lastMovementAt = new Date(NOW.getTime() - 5 * 3600_000).toISOString();
    const lastNudgeSentAt = new Date(NOW.getTime() - 1 * 3600_000).toISOString(); // after the movement
    expect(shouldNudge(state({ lastMovementAt, lastNudgeSentAt }), NOW, 15)).toBe(false);
  });

  // A prior nudge that predates the last movement is a stale spell — nudge again.
  it("nudges again in a new idle window", () => {
    const lastMovementAt = new Date(NOW.getTime() - 4 * 3600_000).toISOString();
    const lastNudgeSentAt = new Date(NOW.getTime() - 8 * 3600_000).toISOString(); // before the movement
    expect(shouldNudge(state({ lastMovementAt, lastNudgeSentAt }), NOW, 15)).toBe(true);
  });

  // Idle, but it's the middle of the night → suppressed by quiet hours.
  it("suppresses an idle nudge during quiet hours", () => {
    const lastMovementAt = new Date(NOW.getTime() - 4 * 3600_000).toISOString();
    expect(shouldNudge(state({ lastMovementAt }), NOW, 3, DEFAULT_QUIET_HOURS)).toBe(false);
  });
});
