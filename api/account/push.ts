import type { VercelRequest, VercelResponse } from "@vercel/node";
import { addPushToken, removePushToken, deletePush } from "../_lib/account.js";
import { requireUser } from "../_lib/session.js";

// /api/account/push — APNs device-token registration for the OPT-IN server-driven
// movement nudge.
//
//   POST   { deviceToken, platform? }  → register the token for this user.
//   DELETE { deviceToken }             → deregister one token (sign-out / health-off
//                                        / account deletion). Dropping the last
//                                        token removes the row entirely.
//
// The user is ALWAYS resolved from the `Authorization: Bearer <session token>`
// via requireUser — never the body — so a caller can only register/remove tokens
// for themselves. Unauthenticated requests get 401. The client only ever calls
// this when signed in AND health sync is on AND OS push permission is granted;
// the server does not re-derive consent, but with no token registered no push is
// ever sent, so the opt-in gate holds regardless.

// APNs device tokens are 64 hex chars (32 bytes) today, but Apple has grown them
// before; bound generously so a hostile client can't store an unbounded blob.
const MAX_TOKEN_LEN = 200;
const HEX = /^[0-9a-fA-F]+$/;

export default async function handler(req: VercelRequest, res: VercelResponse) {
  try {
    const userId = await requireUser(req);
    if (!userId) {
      res.status(401).json({ error: "unauthorized" });
      return;
    }

    const body = (req.body ?? {}) as { deviceToken?: string; platform?: string };
    const deviceToken = (body.deviceToken ?? "").toString().trim();

    if (req.method === "POST") {
      if (!deviceToken || deviceToken.length > MAX_TOKEN_LEN || !HEX.test(deviceToken)) {
        res.status(400).json({ error: "invalid_device_token" });
        return;
      }
      const platform = (body.platform ?? "ios").toString();
      await addPushToken(userId, deviceToken, platform, new Date().toISOString());
      res.status(200).json({ ok: true });
      return;
    }

    if (req.method === "DELETE") {
      // A specific token removes just that device; no token deregisters the user
      // entirely (the sign-out / health-off / delete-account opt-out, where the
      // client may not have the exact token to hand).
      if (deviceToken) {
        await removePushToken(userId, deviceToken, new Date().toISOString());
      } else {
        await deletePush(userId);
      }
      res.status(200).json({ ok: true });
      return;
    }

    res.status(405).json({ error: "method_not_allowed" });
  } catch (err) {
    console.error("account/push", (err as Error).message); // server-side only
    res.status(502).json({ error: "push_registration_failed" });
  }
}
