import type { VercelRequest, VercelResponse } from "@vercel/node";
import { listNudgeCandidates, stampNudgeSent, removePushToken } from "../_lib/account.js";
import { buildAps, providerToken, sendPush } from "../_lib/apns.js";
import { shouldNudge, DEFAULT_QUIET_HOURS } from "../_lib/nudge.js";
import { env } from "../_lib/strava.js";

// Scheduled scan for the server-driven movement nudge (Vercel cron, see
// vercel.json). For every opted-in user with a fresh last-movement time, decides
// with the pure `shouldNudge` policy whether they've been idle past their
// threshold — once per idle window, never during quiet hours — and sends the
// APNs "Stretch your legs?" push. Stamps `last_nudge_sent_at` on a send and
// prunes tokens APNs reports as unregistered.
//
// Copy mirrors the on-device `ReminderCopy.inactivity*` so the server and local
// nudges read identically.
const NUDGE_TITLE = "Stretch your legs?";
const NUDGE_BODY = "It's been a little while since you moved. A couple of easy minutes is plenty.";

// Vercel cron hits this unauthenticated from within the platform; a shared secret
// (CRON_SECRET, sent as `Authorization: Bearer`) blocks public invocation.
function authorized(req: VercelRequest): boolean {
  const secret = process.env.CRON_SECRET;
  if (!secret) return true; // not configured → allow (dev / preview)
  const header = req.headers["authorization"];
  const value = Array.isArray(header) ? header[0] : header;
  return value === `Bearer ${secret}`;
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (!authorized(req)) {
    res.status(401).json({ error: "unauthorized" });
    return;
  }
  try {
    const now = new Date();
    const localHour = now.getUTCHours(); // per-user timezone is a future refinement; UTC baseline
    const jwt = providerToken(env("APNS_KEY_ID"), env("APNS_TEAM_ID"), env("APNS_AUTH_KEY"), now);
    const payload = buildAps(NUDGE_TITLE, NUDGE_BODY);

    const candidates = await listNudgeCandidates();
    let sent = 0;
    for (const user of candidates) {
      const due = shouldNudge(
        {
          lastMovementAt: user.last_movement_at,
          inactivityHours: user.inactivity_hours ?? 3,
          lastNudgeSentAt: user.last_nudge_sent_at,
        },
        now,
        localHour,
        DEFAULT_QUIET_HOURS,
      );
      if (!due) continue;

      let delivered = false;
      for (const token of user.tokens) {
        const result = await sendPush(token, payload, jwt);
        if (result.ok) delivered = true;
        // Prune a token Apple no longer recognizes so we stop paying to try it.
        if (result.status === 410 || result.reason === "Unregistered" || result.reason === "BadDeviceToken") {
          await removePushToken(user.user_id, token, now.toISOString()).catch(() => {});
        }
      }
      if (delivered) {
        await stampNudgeSent(user.user_id, now.toISOString());
        sent += 1;
      }
    }
    res.status(200).json({ scanned: candidates.length, sent });
  } catch (err) {
    console.error("cron/movement-nudge", (err as Error).message); // server-side only
    res.status(502).json({ error: "movement_nudge_failed" });
  }
}
