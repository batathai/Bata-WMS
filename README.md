# MySQL (reporting) → Supabase sync

Syncs `dispatch` and `receiving` from the source MySQL database (`192.1.1.38`,
db `reporting`) into your new Supabase project, incrementally, on a daily
schedule.

## Setup (one time)

1. **Create the Supabase tables**
   Open your Supabase project → SQL Editor → paste and run `schema.sql`.

2. **Install Node.js** (if not already installed) — https://nodejs.org (LTS version).

3. **Install dependencies**
   Open a terminal in this folder and run:
   ```
   npm install
   ```

4. **Configure credentials**
   Copy `.env.example` to `.env`, then fill in:
   - `MYSQL_PASSWORD` — the `talend` account password (rotate this if it was
     ever shared in plaintext anywhere — see CHANGELOG.md from the access
     recovery)
   - `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` — from your Supabase
     project's Settings → API page

5. **Run once manually to test**
   ```
   npm start
   ```
   or double-click `เริ่ม-Sync.bat`.

   First run pulls **all** existing rows (full backfill), since there's no
   watermark yet — this may take a bit if the tables are large. After that,
   every run only pulls rows changed since the last successful sync.

6. **Leave it running**
   The script re-syncs automatically at 12:00, 18:00, and 22:00 every day
   (edit the `SCHEDULE` array at the top of `sync.js` to change the times).
   Keep the terminal window open, same as the earlier `auto-sync.js` setup.

## How incremental sync works

- Each row in MySQL has `updatedAt`. Every sync run remembers, per table, the
  latest `updatedAt` it has already copied (stored in `sync-state.json`,
  created automatically next to this script).
- On each run it only pulls rows with `updatedAt` greater than that watermark,
  and **upserts** them into Supabase by `id` — so re-running never creates
  duplicates, and edits to existing rows in MySQL get reflected too.
- If a run fails partway, the watermark is not advanced, so the next run
  retries the same window.

## What is intentionally NOT synced

- The `users` table (has its own `password` column, separate from this
  reporting data — don't copy that into the new system without deciding
  first how it'll be secured there).
- Everything else in the `reporting` database besides `dispatch` /
  `receiving` — that DB has many unrelated tables from other systems/teams.

## If you need to re-sync everything from scratch

Delete `sync-state.json` and run again — it will treat it as a first run and
pull all rows again (upsert means this is safe, just slower).

## Live Dispatch/Receiving API (LAN only)

`api-server.js` is a separate, optional tool: it queries the source MySQL
database directly on every request (no sync delay) and serves a small web
page for browsing Dispatch/Receiving grouped by invoice, with filters and
CSV export.

**This is for use inside the office LAN only** — it has no login/auth yet,
and talks straight to the production MySQL database. Do not port-forward
its port to the internet.

1. Same `.env` as above (uses `MYSQL_HOST`/`MYSQL_USER`/`MYSQL_PASSWORD`/`MYSQL_DATABASE`).
2. `npm install` (adds `express` on top of the sync dependencies).
3. `npm run start:api` — starts on `http://localhost:3001` by default
   (change with `API_PORT` in `.env`).
4. From another PC on the same network, find this machine's LAN IP
   (`ipconfig` → IPv4 Address) and open `http://<that-ip>:3001` in a browser.

`Pair` = sum of `items` where `isFootware = 1`, `Accessories` = sum of
`items` where `isFootware = 0`, both grouped by `invoice`.
