import type { VercelRequest, VercelResponse } from "@vercel/node";
import {
  deleteToken,
  deviceKeyFromHeader,
  exchangeCode,
  fetchMappedActivities,
  freshAccessToken,
  getToken,
  isValidDeviceKey,
  upsertToken,
} from "../_lib/strava.js";

// Every Strava route behind ONE serverless function.
//
// `api/` was at exactly 12 handler files, Vercel's Hobby-tier ceiling for a
// single deployment, so the next feature needing an endpoint could not deploy at
// all. Strava is the natural place to reclaim slots: four small handlers that
// share one `_lib/strava.ts` and one client. Collapsing them frees three.
//
// The public paths are UNCHANGED. A catch-all at `api/strava/[...route].ts`
// serves `/api/strava/activities`, `/callback`, `/disconnect` and `/exchange`
// exactly as the four files did — the iOS client and the Strava app's registered
// Authorization Callback Domain both keep working untouched. Each handler body
// moved across verbatim: same status codes, same JSON error keys (the client
// branches on them), same `console.error` tags (so log greps keep working), and
// the same header comments, which document real constraints.

export default async function handler(req: VercelRequest, res: VercelResponse) {
  // A catch-all delivers `route` as string[]; take the first segment so a
  // nested or trailing-slash path can't slip past the switch into the default.
  const segments = req.query.route;
  const route = Array.isArray(segments) ? segments[0] : segments;

  switch (route) {
    case "activities":
      return activities(req, res);
    case "callback":
      return callback(req, res);
    case "disconnect":
      return disconnect(req, res);
    case "exchange":
      return exchange(req, res);
    default:
      res.status(404).json({ error: "not_found" });
      return;
  }
}

// GET (x-device-key header) — read the device's Strava token from Supabase
// (refreshing it server-side if expired), fetch recent activities, and return
// them mapped to the app's workout shape. The app never handles the Strava
// access token. The device key rides in a header, never the query string, so it
// stays out of access logs.
async function activities(req: VercelRequest, res: VercelResponse) {
  const deviceKey = deviceKeyFromHeader(req.headers);
  if (!deviceKey) {
    res.status(400).json({ error: "missing_device_key" });
    return;
  }

  try {
    const row = await getToken(deviceKey);
    if (!row) {
      // Deliberate non-error path: not connected is a normal state, not a fault.
      res.status(200).json({ connected: false, activities: [] });
      return;
    }
    const accessToken = await freshAccessToken(row);
    const list = await fetchMappedActivities(accessToken);
    res.status(200).json({ connected: true, activities: list });
  } catch (err) {
    console.error("strava/activities", (err as Error).message); // server-side only
    res.status(502).json({ error: "activities_failed" });
  }
}

// Strava redirects the browser here after the user approves (Authorization
// Callback Domain = otterpace.com). We bounce straight back into the app's
// custom scheme so ASWebAuthenticationSession can capture the code. The device
// key rides along in `state` so the exchange step knows whose tokens to store.
//
// Every reflected value is validated against its expected shape before it goes
// into the redirect URL, so a crafted callback can't inject arbitrary query
// params into the app's `otterpace://strava-callback` handler. The redirect host
// is a fixed app scheme — never derived from input.
const CODE_RE = /^[A-Za-z0-9]{1,256}$/;        // Strava authorization codes are hex-ish
const ERROR_RE = /^[a-z_]{1,64}$/;             // OAuth error codes, e.g. access_denied

function callback(req: VercelRequest, res: VercelResponse) {
  const { code, state, error } = req.query as Record<string, string | undefined>;
  const params = new URLSearchParams();

  if (error && ERROR_RE.test(error)) params.set("error", error);
  else if (code && CODE_RE.test(code)) params.set("code", code);
  else params.set("error", "invalid_callback");

  if (state && isValidDeviceKey(state)) params.set("state", state);

  res.statusCode = 302;
  res.setHeader("Location", `otterpace://strava-callback?${params.toString()}`);
  res.end();
}

// POST { deviceKey } — forget this device's Strava tokens (server-side delete).
async function disconnect(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }
  const body = (req.body ?? {}) as { deviceKey?: string };
  const deviceKey = (body.deviceKey ?? "").toString();
  if (!isValidDeviceKey(deviceKey)) {
    res.status(400).json({ error: "missing_device_key" });
    return;
  }
  try {
    await deleteToken(deviceKey);
    res.status(200).json({ ok: true });
  } catch (err) {
    console.error("strava/disconnect", (err as Error).message); // server-side only
    res.status(502).json({ error: "disconnect_failed" });
  }
}

// POST { code, deviceKey } — exchange the OAuth code for tokens (server-side,
// using the client secret) and store them in Supabase keyed by the device key.
// Returns only a success flag + athlete first name; the tokens never go to the app.
async function exchange(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }
  const body = (req.body ?? {}) as { code?: string; deviceKey?: string };
  const code = (body.code ?? "").toString();
  const deviceKey = (body.deviceKey ?? "").toString();
  if (!code || !isValidDeviceKey(deviceKey)) {
    res.status(400).json({ error: "missing_code_or_device_key" });
    return;
  }

  try {
    const tok = await exchangeCode(code);
    await upsertToken({
      device_key: deviceKey,
      athlete_id: tok.athlete?.id ?? null,
      access_token: tok.access_token,
      refresh_token: tok.refresh_token,
      expires_at: tok.expires_at,
    });
    res.status(200).json({ connected: true, athleteName: tok.athlete?.firstname ?? null });
  } catch (err) {
    console.error("strava/exchange", (err as Error).message); // server-side only — don't leak internals to the client
    res.status(502).json({ error: "exchange_failed" });
  }
}
