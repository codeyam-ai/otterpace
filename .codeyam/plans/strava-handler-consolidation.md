---
title: "Consolidate Strava Handlers Into One Catch-All"
mode: backend
createdAt: "2026-07-30T19:06:00Z"
source: manual
order: 4
---

## Summary

`api/` contains **exactly 12** serverless handler files, which is Vercel's Hobby
tier ceiling for a single deployment. The next feature that needs an endpoint
cannot deploy. Fold the four tiny Strava handlers — `activities.ts` (29 lines),
`callback.ts` (29), `disconnect.ts` (23), `exchange.ts` (34), **115 lines
combined** — into one `api/strava/[...route].ts`, taking the deployment from 12
functions to **9** and freeing three slots.

This is pure infrastructure: every URL, request shape, response shape, and status
code stays byte-identical. All four handlers are already thin argument-validation
shells over `api/_lib/strava.ts`, which is where the real logic lives and which
this plan does not touch. The consolidation is mostly moving four `export default`
bodies into four branches of a `switch`.

## Key Decisions

- **Every public path is preserved exactly.** A Vercel catch-all at
  `api/strava/[...route].ts` serves `/api/strava/activities`,
  `/api/strava/callback`, `/api/strava/disconnect`, and `/api/strava/exchange`
  at the same URLs they have today. Nothing about the routing changes from the
  outside — this is a bundling change, not an API change.

- **`callback.ts` is the risk, and it must be verified, not assumed.**
  `StravaService.swift:26` hard-codes
  `redirectURI = "https://otterpace.com/api/strava/callback"`, and that URL is
  **registered with Strava** as the app's Authorization Callback Domain. It is
  also the one handler a browser hits directly rather than the app. If the
  catch-all fails to serve that path, OAuth breaks for every new connection and
  the failure surfaces as a user-facing dead end, not a test failure. Verify the
  live path on a preview deploy before merging. Do not change `redirectURI` — the
  whole point is that it doesn't need to.

- **Dispatch on the route segment, mirroring the pattern already planned for
  social.** `req.query.route` arrives as `string[]` for a catch-all; take the
  first segment, `switch` on it, and return 404 on anything unrecognized. Keeping
  this shape consistent with the future `api/social/[...route].ts` means one
  dispatch idiom in the codebase instead of two.

- **Per-route method checks stay per-route.** `disconnect` and `exchange` are
  POST-only and return 405 today; `activities` is GET; `callback` is GET. Hoisting
  a single method check to the top of the dispatcher would change behavior for at
  least one route. Each branch keeps its own guard exactly as written.

- **This is a prerequisite, not a nice-to-have.** The social feature is blocked on
  it. Landing it separately means the deploy-capacity problem is solved and
  verified on its own, rather than being discovered as a red deploy in the middle
  of a large feature branch.

## Implementation

### 1. The catch-all

**New file**: `api/strava/[...route].ts`

One `export default async function handler(req, res)` that resolves the segment
and dispatches:

```
const segments = req.query.route;
const route = Array.isArray(segments) ? segments[0] : segments;
switch (route) {
  case "activities":  return activities(req, res);
  case "callback":    return callback(req, res);
  case "disconnect":  return disconnect(req, res);
  case "exchange":    return exchange(req, res);
  default:            res.status(404).json({ error: "not_found" });
}
```

Move each existing handler body in verbatim as a module-local function. Preserve:

- the exact status codes and JSON error keys (`missing_device_key`,
  `missing_code_or_device_key`, `method_not_allowed`) — the client branches on
  these,
- the `200 { connected: false, activities: [] }` not-connected response in
  `activities`, which is a deliberate non-error path,
- the `CODE_RE` / `ERROR_RE` validation constants and the fixed-scheme redirect
  in `callback` — this is security-relevant input validation guarding against
  query-param injection into `otterpace://strava-callback`, and it must move
  across unaltered,
- every `console.error("strava/<route>", …)` tag, so log greps keep working,
- the header comments on each handler, which document real constraints (the
  device key riding in a header to stay out of access logs; tokens never reaching
  the app).

### 2. Delete the originals

Remove `api/strava/activities.ts`, `callback.ts`, `disconnect.ts`, `exchange.ts`.

Confirm the count afterward: `find api -name "*.ts" | grep -v _lib | wc -l`
should print **9**.

### 3. Tests

**File**: `test/api/strava-handlers.test.ts`

The existing tests import the four default exports directly. Repoint them at the
catch-all, invoking it with `req.query.route` set to each segment. Add:

- an unknown segment → 404,
- an empty/missing segment → 404,
- `req.query.route` as a **string** rather than an array (Vercel's shape varies
  with the request) → still dispatches.

Every existing assertion about status codes and bodies must pass unchanged. If
one needs editing, that is a behavior change and the port is wrong.

### 4. Deploy verification

Before merging, on a preview deployment:

- `GET /api/strava/callback?code=abc&state=<validkey>` returns the
  `otterpace://strava-callback` redirect, not a 404.
- `POST /api/strava/disconnect` with a bad body still returns 400.
- `GET /api/strava/activities` without the device-key header still returns 400.
- The Vercel build log reports 9 serverless functions.

Then run one real end-to-end Strava connect from a device against the preview.
The OAuth round trip is the thing that cannot be unit-tested and the thing that
breaks worst if this is wrong.

## Reused existing code

- `api/_lib/strava.ts` — `getToken`, `freshAccessToken`, `fetchMappedActivities`,
  `deviceKeyFromHeader`, `exchangeCode`, `upsertToken`, `deleteToken`,
  `isValidDeviceKey`. **Untouched.** All four handlers already delegate to it,
  which is what makes this consolidation mechanical.
- The four existing handler bodies (`api/strava/*.ts`) — moved verbatim, not
  rewritten.
- `test/api/strava-handlers.test.ts` — repointed, with its assertions preserved
  as the regression guard.
- `StravaService.swift` (`Sources/AppCore/Strava/StravaService.swift`) — read to
  confirm the client's paths; **not modified**. Its `post("strava/exchange")`,
  `post("strava/disconnect")`, and `strava/activities` calls all continue to work
  against the same URLs.

## Scenarios to Demonstrate

*(Backend-only — no simulator surface.)*

- Unit: each of the four segments dispatches to its handler with today's exact
  status code and body.
- Unit: unknown segment → 404.
- Unit: `route` as a bare string dispatches identically to `route` as an array.
- Unit: `callback` still rejects a malformed `code` against `CODE_RE` and still
  redirects to the fixed app scheme.
- Unit: `disconnect` and `exchange` still return 405 on GET.
- Build: the deployment reports 9 serverless functions, down from 12.
- Manual: a full device Strava connect against a preview deploy succeeds.
