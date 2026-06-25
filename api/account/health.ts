import type { VercelRequest, VercelResponse } from "@vercel/node";
import {
  getHealth,
  upsertHealth,
  deleteHealth,
  incomingWins,
  type HealthRow,
} from "../_lib/account.js";

// /api/account/health — the OPTIONAL health/activity sync stream.
//
//   GET    ?userId=…           → the stored health row (or { found: false }).
//   PUT    { userId, health, updatedAt }
//                              → last-write-wins upsert (only ever called after
//                                the user consents + enables health sync).
//   DELETE { userId } | ?userId=…
//                              → remove the row — the opt-out / "delete my
//                                health data" path.
//
// Kept in a table distinct from account_prefs so revoking/deleting health sync
// never touches the user's settings, and a settings-only user never has a row
// here at all.
export default async function handler(req: VercelRequest, res: VercelResponse) {
  try {
    if (req.method === "GET") {
      const userId = (req.query?.userId ?? "").toString();
      if (!userId) {
        res.status(400).json({ error: "missing_user_id" });
        return;
      }
      const row = await getHealth(userId);
      res.status(200).json(row ? { found: true, ...row } : { found: false });
      return;
    }

    if (req.method === "PUT") {
      const body = (req.body ?? {}) as {
        userId?: string;
        health?: Record<string, unknown>;
        updatedAt?: string;
      };
      const userId = (body.userId ?? "").toString();
      const health = body.health;
      const updatedAt = (body.updatedAt ?? "").toString();
      if (!userId || !health || typeof health !== "object" || !updatedAt) {
        res.status(400).json({ error: "missing_user_id_health_or_updated_at" });
        return;
      }

      const stored = await getHealth(userId);
      if (!incomingWins(stored?.updated_at ?? null, updatedAt)) {
        res.status(200).json({ applied: false, ...(stored as HealthRow) });
        return;
      }
      const row: HealthRow = { user_id: userId, health, updated_at: updatedAt };
      await upsertHealth(row);
      res.status(200).json({ applied: true, ...row });
      return;
    }

    if (req.method === "DELETE") {
      const fromBody = (req.body ?? {}) as { userId?: string };
      const userId = (req.query?.userId ?? fromBody.userId ?? "").toString();
      if (!userId) {
        res.status(400).json({ error: "missing_user_id" });
        return;
      }
      await deleteHealth(userId);
      res.status(200).json({ ok: true });
      return;
    }

    res.status(405).json({ error: "method_not_allowed" });
  } catch (err) {
    console.error("account/health", (err as Error).message); // server-side only — don't leak internals
    res.status(502).json({ error: "health_sync_failed" });
  }
}
