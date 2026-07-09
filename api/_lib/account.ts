// Shared account-sync + Supabase helpers for the /api/account/* functions.
//
// Optional, account-backed persistence for signed-in (Sign in with Apple) users.
// Two INDEPENDENT streams, each in its own table keyed by the stable Apple
// userID, so they can be opted into — and deleted — separately:
//
//   account_prefs   — synced settings/preferences (step goal, reminder prefs).
//                     Written only when the user enables "Sync my settings".
//   account_health  — a derived health/activity snapshot. OFF BY DEFAULT;
//                     written only after explicit consent + the separate
//                     "Sync my health & activity data" opt-in. Deletable.
//
// Reuses the exact Strava pattern: Supabase via its PostgREST endpoint with the
// service-role key (no SDK in the function bundle), merge-duplicates upsert.
//
// Required env (set in Vercel, shared with Strava): SUPABASE_URL,
// SUPABASE_SERVICE_ROLE_KEY. See docs/account-sync.md.
//
// Supabase tables (create once — see docs/account-sync.md):
//   create table account_prefs (
//     user_id    text primary key,
//     prefs      jsonb not null,
//     updated_at timestamptz default now()
//   );
//   create table account_health (        -- only written when the user opts in
//     user_id    text primary key,
//     health     jsonb not null,
//     updated_at timestamptz default now()
//   );

import { env, supabaseHeaders } from "./strava.js";

export interface PrefsRow {
  user_id: string;
  prefs: Record<string, unknown>;
  updated_at: string; // ISO timestamp
}

export interface HealthRow {
  user_id: string;
  health: Record<string, unknown>;
  updated_at: string; // ISO timestamp
}

export function prefsEndpoint(): string {
  return `${env("SUPABASE_URL")}/rest/v1/account_prefs`;
}

export function healthEndpoint(): string {
  return `${env("SUPABASE_URL")}/rest/v1/account_health`;
}

// Health-ish keys that must NEVER appear in a settings/preferences payload.
// Defense in depth: even if a client bug routed a health snapshot to the prefs
// endpoint, we reject it so a settings-only user never leaks health data into
// the wrong row. Match is case-insensitive on the top-level keys.
const HEALTH_KEY_DENYLIST = [
  "health",
  "steps",
  "distancemiles",
  "activeminutes",
  "activeenergykcal",
  "heartrate",
  "restingheartrate",
  "workouts",
  "weeklymileage",
  "sleep",
];

// Bound the recursion so a deeply nested (or pathological) payload can't blow the
// stack. Real prefs are shallow; this is purely a safety ceiling.
const MAX_SCAN_DEPTH = 8;

/**
 * True when a prefs payload carries any health field anywhere in its structure
 * (so it must be rejected). Walks nested objects and arrays, not just top-level
 * keys, so a health field hidden one level down can't slip past the guard.
 */
export function prefsContainHealthFields(prefs: Record<string, unknown>): boolean {
  return scanForHealthKey(prefs, 0);
}

function scanForHealthKey(value: unknown, depth: number): boolean {
  if (depth > MAX_SCAN_DEPTH || value === null || typeof value !== "object") return false;
  if (Array.isArray(value)) {
    return value.some((item) => scanForHealthKey(item, depth + 1));
  }
  for (const [key, child] of Object.entries(value as Record<string, unknown>)) {
    if (HEALTH_KEY_DENYLIST.includes(key.toLowerCase())) return true;
    if (scanForHealthKey(child, depth + 1)) return true;
  }
  return false;
}

/**
 * Last-write-wins decision shared by both streams: should the incoming payload
 * replace the stored row? Yes when there is no stored row, or the incoming
 * `updated_at` is strictly newer than the stored one. Equal timestamps keep the
 * stored row (idempotent — re-pushing the same snapshot is a no-op).
 */
export function incomingWins(storedUpdatedAt: string | null, incomingUpdatedAt: string): boolean {
  if (!storedUpdatedAt) return true;
  return Date.parse(incomingUpdatedAt) > Date.parse(storedUpdatedAt);
}

// MARK: account_prefs

export async function getPrefs(userId: string): Promise<PrefsRow | null> {
  const url = `${prefsEndpoint()}?user_id=eq.${encodeURIComponent(userId)}&select=*`;
  const res = await fetch(url, { headers: supabaseHeaders() });
  if (!res.ok) throw new Error(`supabase_read_failed:${res.status}`);
  const rows = (await res.json()) as PrefsRow[];
  return rows[0] ?? null;
}

export async function upsertPrefs(row: PrefsRow): Promise<void> {
  const res = await fetch(prefsEndpoint(), {
    method: "POST",
    headers: { ...supabaseHeaders(), Prefer: "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify(row),
  });
  if (!res.ok) throw new Error(`supabase_upsert_failed:${res.status}`);
}

// MARK: account_health

export async function getHealth(userId: string): Promise<HealthRow | null> {
  const url = `${healthEndpoint()}?user_id=eq.${encodeURIComponent(userId)}&select=*`;
  const res = await fetch(url, { headers: supabaseHeaders() });
  if (!res.ok) throw new Error(`supabase_read_failed:${res.status}`);
  const rows = (await res.json()) as HealthRow[];
  return rows[0] ?? null;
}

export async function upsertHealth(row: HealthRow): Promise<void> {
  const res = await fetch(healthEndpoint(), {
    method: "POST",
    headers: { ...supabaseHeaders(), Prefer: "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify(row),
  });
  if (!res.ok) throw new Error(`supabase_upsert_failed:${res.status}`);
}

/** Remove the user's health row entirely — the opt-out / "delete my health data" path. */
export async function deleteHealth(userId: string): Promise<void> {
  const url = `${healthEndpoint()}?user_id=eq.${encodeURIComponent(userId)}`;
  const res = await fetch(url, { method: "DELETE", headers: supabaseHeaders() });
  if (!res.ok && res.status !== 404) throw new Error(`supabase_delete_failed:${res.status}`);
}

// MARK: account_push — server-driven movement nudge (opt-in)
//
// One row per signed-in, health-sync-on user who granted push. It holds
// EVERYTHING the movement-nudge cron scans, so the scheduler reads a single
// table: the APNs device token(s), the last-movement time + inactivity setting
// mirrored from the health heartbeat, and the last-nudge stamp for de-dup.
//
//   create table account_push (
//     user_id            text primary key,
//     tokens             jsonb not null default '[]'::jsonb,  -- APNs device tokens (hex)
//     platform           text not null default 'ios',
//     last_movement_at   timestamptz,   -- mirrored from the health heartbeat
//     inactivity_hours   int,           -- the user's setting
//     last_nudge_sent_at timestamptz,   -- de-dup: one nudge per idle window
//     updated_at         timestamptz default now()
//   );

export interface PushRow {
  user_id: string;
  tokens: string[];
  platform: string;
  last_movement_at: string | null;
  inactivity_hours: number | null;
  last_nudge_sent_at: string | null;
  updated_at: string;
}

export function pushEndpoint(): string {
  return `${env("SUPABASE_URL")}/rest/v1/account_push`;
}

export async function getPush(userId: string): Promise<PushRow | null> {
  const url = `${pushEndpoint()}?user_id=eq.${encodeURIComponent(userId)}&select=*`;
  const res = await fetch(url, { headers: supabaseHeaders() });
  if (!res.ok) throw new Error(`supabase_read_failed:${res.status}`);
  const rows = (await res.json()) as PushRow[];
  return rows[0] ?? null;
}

async function upsertPush(row: PushRow): Promise<void> {
  const res = await fetch(pushEndpoint(), {
    method: "POST",
    headers: { ...supabaseHeaders(), Prefer: "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify(row),
  });
  if (!res.ok) throw new Error(`supabase_upsert_failed:${res.status}`);
}

/**
 * Register an APNs device token for a user (idempotent — re-registering the same
 * token is a no-op, and multiple devices accumulate distinct tokens). Preserves
 * any mirrored movement/nudge state on the existing row.
 */
export async function addPushToken(userId: string, token: string, platform: string, now: string): Promise<void> {
  const existing = await getPush(userId);
  const tokens = new Set(existing?.tokens ?? []);
  tokens.add(token);
  await upsertPush({
    user_id: userId,
    tokens: [...tokens],
    platform,
    last_movement_at: existing?.last_movement_at ?? null,
    inactivity_hours: existing?.inactivity_hours ?? null,
    last_nudge_sent_at: existing?.last_nudge_sent_at ?? null,
    updated_at: now,
  });
}

/**
 * Remove one device token. When it was the last token, drop the row entirely so
 * a signed-out / health-off user leaves no push footprint. Idempotent.
 */
export async function removePushToken(userId: string, token: string, now: string): Promise<void> {
  const existing = await getPush(userId);
  if (!existing) return;
  const tokens = (existing.tokens ?? []).filter((t) => t !== token);
  if (tokens.length === 0) {
    await deletePush(userId);
    return;
  }
  await upsertPush({ ...existing, tokens, updated_at: now });
}

/** Remove the user's entire push row — sign-out / health-off / account deletion. */
export async function deletePush(userId: string): Promise<void> {
  const url = `${pushEndpoint()}?user_id=eq.${encodeURIComponent(userId)}`;
  const res = await fetch(url, { method: "DELETE", headers: supabaseHeaders() });
  if (!res.ok && res.status !== 404) throw new Error(`supabase_delete_failed:${res.status}`);
}

/**
 * Mirror the latest movement heartbeat onto the push row so the cron can scan a
 * single table. Only touches an EXISTING row (a user without push registration
 * gets no row created), and never clobbers the token list.
 */
export async function mirrorMovement(userId: string, lastMovementAt: string, inactivityHours: number, now: string): Promise<void> {
  const existing = await getPush(userId);
  if (!existing) return; // no push registration → nothing to mirror
  await upsertPush({ ...existing, last_movement_at: lastMovementAt, inactivity_hours: inactivityHours, updated_at: now });
}

/** Every push row with at least one token and a known last-movement time — the cron's scan set. */
export async function listNudgeCandidates(): Promise<PushRow[]> {
  const url = `${pushEndpoint()}?select=*&last_movement_at=not.is.null`;
  const res = await fetch(url, { headers: supabaseHeaders() });
  if (!res.ok) throw new Error(`supabase_read_failed:${res.status}`);
  const rows = (await res.json()) as PushRow[];
  return rows.filter((r) => (r.tokens ?? []).length > 0);
}

/** Stamp the last-nudge time after a successful send, for one-per-idle-window de-dup. */
export async function stampNudgeSent(userId: string, at: string): Promise<void> {
  const existing = await getPush(userId);
  if (!existing) return;
  await upsertPush({ ...existing, last_nudge_sent_at: at, updated_at: at });
}
