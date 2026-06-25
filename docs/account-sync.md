# Account data sync (optional)

Otterpace can optionally back up a signed-in user's data to the same Supabase
backend used for Strava tokens, keyed to the stable **Sign in with Apple** user
identifier, so it survives reinstalls and follows the user across devices.

Sync is **off until the user turns it on**, and is split into two independent
opt-ins so a privacy-minded user can sync settings without ever syncing health
data:

| Stream | Toggle | Default | Table |
| --- | --- | --- | --- |
| Settings / preferences (step goal, etc.) | "Sync my settings" | off | `account_prefs` |
| Health / activity snapshot | "Sync my health & activity data" | **off** | `account_health` |

Health sync additionally requires a one-time **consent moment** before the first
upload (what's uploaded, where it's stored, that it's reversible + deletable),
and turning it off offers to delete the already-uploaded data.

## Endpoints (Vercel serverless, `api/account/*`)

All mirror the existing `api/_lib/strava.ts` pattern: Supabase reached via its
PostgREST endpoint with the service-role key (no SDK in the bundle), upserts use
`Prefer: resolution=merge-duplicates`. Conflict handling is **last-write-wins on
`updated_at`** — simple and predictable for single-user blobs.

- `GET  /api/account/sync?userId=…` → `{ found, prefs, updated_at }`
- `PUT  /api/account/sync   { userId, prefs, updatedAt }` → upsert (rejects any
  health field in `prefs`, as defense in depth; remote wins if newer)
- `GET  /api/account/health?userId=…` → `{ found, health, updated_at }`
- `PUT  /api/account/health { userId, health, updatedAt }` → upsert (remote wins if newer)
- `DELETE /api/account/health { userId }` → delete the row (opt-out / delete data)

## Environment

Reuses the Strava env — **no new variables**:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

## Supabase tables (create once)

```sql
create table account_prefs (
  user_id    text primary key,
  prefs      jsonb not null,
  updated_at timestamptz default now()
);

create table account_health (        -- only ever written when the user opts in
  user_id    text primary key,
  health     jsonb not null,
  updated_at timestamptz default now()
);
```

The two tables are kept separate so revoking/deleting health sync never touches
preferences, and a settings-only user never has a row in `account_health` at all.

## iOS side

- `Sources/AppCore/Account/AccountSyncService.swift` — gates every push on
  sign-in + the relevant opt-in; health upload has a single hard-gated chokepoint.
  The HTTP seam (`AccountSyncTransport`) is injectable; merge logic (`SyncMerge`)
  is pure and unit-tested in `Tests/AppCoreTests/AccountSyncTests.swift`.
- `Sources/AppCore/Account/SyncConsent.swift` — the two opt-in flags + the
  health-consent acknowledgement (health can't be enabled without it).
- `Sources/AppCore/SettingsView.swift` — the two toggles, consent sheet, and the
  delete-or-keep choice on health opt-out (signed-in only).

Guests, and signed-in users with the toggles off, sync nothing.
