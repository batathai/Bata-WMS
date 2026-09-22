# CLAUDE.md

Guidance for Claude Code (or any future AI/dev) working in this repository.

## What this project is

**Bata WMS** — a warehouse management web app for Bata Thailand. It is
mostly a thin, read-oriented front end over data that already lives (and is
still actively written to by other systems) in a legacy on-prem MySQL
database.

**As of 2026-09-22, the primary (and only actively used) way to run the
app is `api-server.js` on the office LAN** — `npm run start:api`, then
open `http://localhost:3001` (or `http://<lan-ip>:3001` from another
machine on the same network). The app was previously also deployed
publicly via GitHub Pages at a custom domain (`tms.batathai.com`,
configured via a `CNAME` file); that domain is no longer used and the
`CNAME` file was removed. `Index/index.html` still talks to Supabase for
everything except the live Dispatch/Transfer views (which need
`api-server.js`), so it would still work if redeployed publicly, but doing
so is not the current setup — check with the user before re-adding a
`CNAME`/public deployment.

1. `Index/index.html` — login, roles, Home KPIs, and most menus, all
   backed by **Supabase** (Postgres + Auth + RLS). Served as a static file
   by `api-server.js`.
2. **LAN-only live API** (`api-server.js`) — run from inside the office
   network, queries the source MySQL database **directly, on every
   request**, so Dispatch/Transfer views are always up to the second
   instead of waiting for the next sync.

A separate script (`sync.js`) incrementally copies `dispatch` and
`receiving` from MySQL into Supabase so the app's non-live views (Home
KPIs, etc.) have data to show without querying MySQL on every page load.

## Why the architecture is split this way

- The source MySQL server (`192.1.1.38`, db `reporting`) is **LAN-only** —
  not reachable from the internet, and other internal systems write to it
  directly, so we must not modify its schema or write to it from this app.
- Supabase gives us hosting, authentication, and row-level-security-based
  role access for everything that isn't the live Dispatch/Transfer data,
  without exposing MySQL itself.
- The LAN-only API (`api-server.js`) exists because warehouse staff who are
  physically on-site want live data (no sync lag); it deliberately has
  **no auth of its own** and must never be port-forwarded to the internet.

## Repo layout

| Path | Purpose |
|---|---|
| `Index/index.html` | The entire public app: login, sidebar nav, Home KPIs, all views. Single-file (HTML+CSS+JS), talks to Supabase via `@supabase/supabase-js` (CDN) and, for the live views, to `api-server.js` over `/api/:view`. |
| `api-server.js` | Express server. Serves `Index/` as static files **and** a `/api/:view` route (`dispatch`, `receiving`, or `receiving-return`) that queries MySQL directly. LAN-only, no auth. |
| `sync.js` | One-shot + cron-scheduled script: MySQL → Supabase incremental sync, watermarked by each row's `updatedAt`. Run with `npm start`. |
| `schema.sql` | Supabase/Postgres schema mirroring the MySQL `dispatch`/`receiving` tables. Run once in the Supabase SQL Editor before the first sync. |
| `.env.example` | Template for local secrets (MySQL creds, Supabase URL/keys, API port). **Never commit a real `.env`.** |
| `sync-state.json` | Auto-created by `sync.js`; stores the per-table sync watermark. Git-ignored. Delete it to force a full re-sync. |
| `README.md` | Setup instructions for a human running `sync.js`/`api-server.js` on a Windows PC. |

## Data model quirks (important, easy to get wrong)

- MySQL's primary key column is **`Id`** (capital I), not `id`. `sync.js`'s
  `COLUMN_MAP` handles this — if you ever query MySQL directly, remember
  the column is case-sensitive on the MySQL side.
- MySQL uses camelCase (`bookedDate`, `documentDate`, `isFootware`, …);
  Supabase/Postgres uses snake_case (`booked_date`, `document_date`,
  `is_footware`, …). The mapping lives in `sync.js`'s `COLUMN_MAP` /
  `PASSTHROUGH_COLUMNS` — keep both in sync if the source schema changes.
- `dispatch` has ~1.5M rows, `receiving` has ~4.9M rows, both growing daily.
  Any query against them (in `api-server.js` or ad-hoc) should filter by
  `documentDate`/`document_date` — never scan the full table.
- Supabase/PostgREST caps query results at **1000 rows by default**. Any
  client query that needs an accurate count/sum over a day (or more) must
  pass an explicit `.limit(N)` well above realistic daily volume, or use
  `{ count: 'exact' }` for the true count separately from the row array.
- `Pair` = `SUM(items) WHERE isFootware = 1`; `Accessories` =
  `SUM(items) WHERE isFootware = 0` — both grouped by invoice or by day.
  This math is duplicated in `api-server.js`'s `buildQuery`/`buildDailyQuery`
  — keep them consistent if you change one.

## Live-view menu → MySQL table mapping (non-obvious, changed once already)

As of the September 2026 remap (see CHANGELOG), the sidebar labels do
**not** map 1:1 to MySQL table names. In `Index/index.html`:

```js
const LIVE_TABLE = { dispatch: 'receiving', transfer: 'dispatch', return: 'receiving-return' };
```

- Menu **"จ่ายสินค้าออก"** (`data-view="dispatch"`) shows the MySQL
  **`receiving`** table's data, **excluding** rows where `receiver = '57702'`.
- Menu **"โอนสินค้าระหว่างคลัง"** (`data-view="transfer"`) shows the MySQL
  **`dispatch`** table's data.
- Menu **"สินค้าคืนคลัง"** (`data-view="return"`) shows the MySQL
  **`receiving`** table's data, **locked to only** `receiver = '57702'`.
- Menu **"รับสินค้าเข้า"** (`data-view="receive"`) is currently an empty
  placeholder — no live source wired up.

This was an explicit, confirmed business decision from the warehouse
manager, not a bug. Do not "fix" it back to the literal name-matching
without checking with the user first.

### The receiver=57702 split (dispatch vs return)

`receiver` code `57702` marks a `receiving` row as a warehouse return
rather than a normal dispatch. `api-server.js` enforces this server-side,
not in the front end — see its `VIEWS`/`RETURN_RECEIVER` constant and
`buildWhere`'s `opts.lockReceiver`/`opts.excludeReceiver`. The API exposes
two views over the same `receiving` table:
- `/api/receiving` — always adds `receiver <> '57702'` (used by "จ่ายสินค้าออก").
- `/api/receiving-return` — always adds `receiver = '57702'` (used by
  "สินค้าคืนคลัง"; that page has no ผู้รับ filter input since it's fixed).

Both conditions are baked into `VIEWS` server-side and can't be overridden
by query params — if the return-receiver code ever changes, update
`RETURN_RECEIVER` in `api-server.js` (single source of truth).

## Secrets / credentials

- `.env` (git-ignored) holds `MYSQL_HOST/USER/PASSWORD/DATABASE`,
  `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `API_PORT`.
- `Index/index.html` embeds `SUPABASE_URL` and a **publishable** key
  (`sb_publishable_...`) directly in client-side JS — this is intentional
  and safe as long as it's the new-format publishable key (or legacy
  `anon` key) and RLS policies are correctly scoped. **Never** put the
  `service_role` / `sb_secret_...` key in `Index/index.html`.
- This repo is **public**. `.env.example` must only ever contain
  placeholders. A real MySQL password and a real Supabase service_role JWT
  were accidentally committed to `.env.example` once (see CHANGELOG,
  2026-09-17/18) — both were rotated/replaced, but the exposure is
  permanent in git history. Always double check `.env.example` (and any
  other file about to be committed) for real secrets before pushing.
- Supabase has two key systems: legacy JWT keys (`anon`/`service_role`,
  HS256, under "Legacy API keys") and the newer
  `sb_publishable_.../sb_secret_...` keys (under "Publishable and secret
  API keys"). This project uses the newer system — `sync.js` requires
  `@supabase/supabase-js@2.4x+` to support it (older versions fail with
  "Invalid API key" against `sb_secret_...` keys).

## Common gotchas hit during development

- **Windows environment variables persisted in the registry**
  (`HKCU\Environment`) silently override `.env` file values, since
  `dotenv` does not overwrite existing `process.env` entries. If a secret
  seems to be "wrong" even after fixing `.env`, check for a stale env var
  with `reg query "HKCU\Environment"` and remove it, then reopen the
  terminal.
- `git push` from a sandboxed/remote Claude session typically cannot reach
  GitHub directly (403) — pushes here are done via the GitHub MCP
  (`push_files`), then the local clone is fast-forwarded with
  `git fetch` + `git reset --hard origin/<branch>`.
- `api-server.js`'s `VIEWS` map (view name → MySQL table + fixed WHERE
  conditions) is the single place that defines what each `/api/:view`
  route actually queries — adding a live-backed menu usually means adding
  an entry there plus a matching one in `LIVE_TABLE` in `Index/index.html`.

## Working conventions for this repo

- All user-facing text in `Index/index.html` is Thai. Keep new UI strings
  Thai, matching the existing tone (short, plain, warehouse-operational).
- Numeric table columns use `class="num"` on **both** the `<td>` and its
  matching `<th>` (right-aligned, Space Grotesk font) — always add both
  when adding a new numeric column, not just the data cell.
- Don't widen `sync.js`/`api-server.js` beyond `dispatch`/`receiving`
  without confirming with the user — the `reporting` MySQL database has
  many unrelated tables from other systems that are explicitly out of
  scope.
- Treat `sync-state.json` as precious operational state, not a scratch
  file — deleting it forces a full multi-million-row re-sync.
