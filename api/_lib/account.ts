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
