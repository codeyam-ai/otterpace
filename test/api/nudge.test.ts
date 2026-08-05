import { describe, it, expect } from "vitest";
import { shouldNudge, isQuietHour, localHourIn, DEFAULT_QUIET_HOURS, type NudgeState } from "../../api/_lib/nudge.ts";

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

// Regression: quiet hours were computed in UTC for the whole scan.
//
// DEFAULT_QUIET_HOURS is 9pm-8am *local*, but the cron read one
// `now.getUTCHours()` and applied it to every candidate. For America/New_York
// (UTC-4 in summer) that made the guard 5pm-4am local: it silenced the evening
// nudge that should fire, and opened 4am-8am where a push could wake someone.
describe("localHourIn", () => {
  // 2026-07-15T18:30:00Z — a summer instant, so US zones are on DST.
  const SUMMER = new Date("2026-07-15T18:30:00Z");

  it("resolves the wall-clock hour per zone", () => {
    expect(localHourIn("UTC", SUMMER)).toBe(18);
    expect(localHourIn("America/New_York", SUMMER)).toBe(14);   // UTC-4
    expect(localHourIn("America/Los_Angeles", SUMMER)).toBe(11); // UTC-7
    expect(localHourIn("Pacific/Auckland", SUMMER)).toBe(6);     // next day, UTC+12
  });

  // A half-hour offset would survive a naive hour-arithmetic implementation but
  // is worth pinning: the hour must come from the zone, not from rounding.
  it("handles a half-hour offset zone", () => {
    expect(localHourIn("Asia/Kolkata", SUMMER)).toBe(0); // UTC+5:30 -> 00:00
  });

  // The case a fixed stored offset would get wrong twice a year. Same zone,
  // instants either side of a US transition, one hour apart in UTC but NOT the
  // same shift in local time.
  it("tracks DST in both directions", () => {
    // Spring forward: 2026-03-08, 2am EST -> 3am EDT.
    const beforeSpring = new Date("2026-03-08T06:30:00Z"); // 01:30 EST
    const afterSpring = new Date("2026-03-08T07:30:00Z");  // 03:30 EDT (02:xx never exists)
    expect(localHourIn("America/New_York", beforeSpring)).toBe(1);
    expect(localHourIn("America/New_York", afterSpring)).toBe(3);

    // Fall back: 2026-11-01, 2am EDT -> 1am EST. The same local hour repeats.
    const beforeFall = new Date("2026-11-01T05:30:00Z"); // 01:30 EDT
    const afterFall = new Date("2026-11-01T06:30:00Z");  // 01:30 EST again
    expect(localHourIn("America/New_York", beforeFall)).toBe(1);
    expect(localHourIn("America/New_York", afterFall)).toBe(1);
  });

  // `hour12: false` renders midnight as 24 in some environments; the quiet-window
  // comparison expects a real [0-23] hour.
  it("normalizes midnight to 0, never 24", () => {
    const utcMidnight = new Date("2026-07-15T00:00:00Z");
    expect(localHourIn("UTC", utcMidnight)).toBe(0);
    // 20:00 EDT is 00:00 UTC — the zone that is actually at midnight here.
    expect(localHourIn("Europe/London", new Date("2026-01-15T00:00:00Z"))).toBe(0);
  });

  // A missing zone (older client) or a hostile identifier must degrade to
  // today's behavior. One bad row cannot be allowed to abort the whole scan.
  it("falls back to the UTC hour without throwing", () => {
    expect(localHourIn(null, SUMMER)).toBe(18);
    expect(localHourIn("", SUMMER)).toBe(18);
    expect(localHourIn(undefined, SUMMER)).toBe(18);
    expect(localHourIn("Not/AZone", SUMMER)).toBe(18);
    expect(localHourIn("../../etc/passwd", SUMMER)).toBe(18);
  });
});

describe("quiet hours end-to-end, per zone", () => {
  // One instant, two users: the fix is that they get different answers.
  // 2026-07-16T01:00:00Z = 21:00 in New York (quiet) and 01:00 UTC (also quiet),
  // so pick an instant where the zones genuinely disagree instead.
  const state = {
    lastMovementAt: "2026-07-15T10:00:00Z",
    inactivityHours: 2,
    lastNudgeSentAt: null,
  };
  const asOf = new Date("2026-07-15T23:00:00Z"); // 19:00 New York, 23:00 UTC

  it("nudges a New York user in their evening while UTC says quiet", () => {
    // 23:00 UTC is inside the 21-8 window; 19:00 New York is not.
    expect(shouldNudge(state, asOf, localHourIn("UTC", asOf))).toBe(false);
    expect(shouldNudge(state, asOf, localHourIn("America/New_York", asOf))).toBe(true);
  });

  it("stays quiet overnight in the user's own zone", () => {
    // 06:00 UTC = 02:00 New York — quiet in both, for different reasons.
    const night = new Date("2026-07-16T06:00:00Z");
    expect(shouldNudge(state, night, localHourIn("America/New_York", night))).toBe(false);
  });
});
