// Pure server-side decision logic for the movement nudge.
//
// Deliberately free of Supabase / APNs / network so it unit-tests directly: the
// cron scanner (api/cron/movement-nudge.ts) feeds it each candidate's stored
// state and only performs a send when this says so. Keeping the policy here (not
// buried in the cron handler) is what makes "idle past threshold, once per idle
// window, never overnight" testable without a backend.

export interface NudgeState {
  /** ISO timestamp of the user's last real movement (from the health heartbeat). */
  lastMovementAt: string | null;
  /** Hours of stillness before a nudge is warranted (the user's setting). */
  inactivityHours: number;
  /** ISO timestamp of the last nudge we sent this user, for de-dup. */
  lastNudgeSentAt: string | null;
}

export interface QuietHours {
  /** Local hour [0-23] the quiet window starts (inclusive). */
  startHour: number;
  /** Local hour [0-23] the quiet window ends (exclusive). */
  endHour: number;
}

/** Default overnight quiet window: 9pm–8am, no nudges. */
export const DEFAULT_QUIET_HOURS: QuietHours = { startHour: 21, endHour: 8 };

/**
 * True when `hour` falls inside the quiet window, handling a window that wraps
 * past midnight (e.g. 21→8). A window where start == end is treated as "never
 * quiet" so a misconfiguration can't silence every nudge.
 */
export function isQuietHour(hour: number, quiet: QuietHours = DEFAULT_QUIET_HOURS): boolean {
  const { startHour, endHour } = quiet;
  if (startHour === endHour) return false;
  if (startHour < endHour) return hour >= startHour && hour < endHour;
  // Wraps past midnight: quiet if after start OR before end.
  return hour >= startHour || hour < endHour;
}

/**
 * Decide whether to send a movement nudge to one user right now.
 *
 *   • no known movement            → no (nothing to key off).
 *   • moved within inactivityHours → no (they're not idle yet).
 *   • already nudged this idle spell (lastNudgeSentAt is after the last movement)
 *                                  → no (one nudge per idle window, never spam).
 *   • current local hour is quiet  → no (no overnight pings).
 *   • otherwise                    → yes.
 *
 * `now` and `localHour` are passed in so the decision is deterministic and
 * timezone handling stays the caller's concern.
 */
export function shouldNudge(state: NudgeState, now: Date, localHour: number, quiet: QuietHours = DEFAULT_QUIET_HOURS): boolean {
  if (!state.lastMovementAt) return false;
  const lastMovement = Date.parse(state.lastMovementAt);
  if (Number.isNaN(lastMovement)) return false;

  const idleMs = now.getTime() - lastMovement;
  const thresholdMs = Math.max(1, state.inactivityHours) * 3600_000;
  if (idleMs < thresholdMs) return false; // still within the active window

  // De-dup: one nudge per idle spell. If we already nudged AFTER the last
  // movement, the user is in the same idle window — don't nudge again until they
  // move (which resets lastMovementAt) or the next idle spell begins.
  if (state.lastNudgeSentAt) {
    const lastNudge = Date.parse(state.lastNudgeSentAt);
    if (!Number.isNaN(lastNudge) && lastNudge > lastMovement) return false;
  }

  if (isQuietHour(localHour, quiet)) return false;

  return true;
}
