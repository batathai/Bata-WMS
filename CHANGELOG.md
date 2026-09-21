# Changelog

All notable changes to this project are documented here. Format is
loosely based on [Keep a Changelog](https://keepachangelog.com/), grouped
by date.

## 2026-09-21

### Added
- 9 new sidebar menu items (placeholders, no UI built yet — Admin/
  Warehouse Staff) matching an updated WMS menu spec: วางแผนจ่ายสินค้า
  (Outbound Planning), การขนส่ง (Transport), OCR รับคืนสินค้า (Goods
  Return OCR), ตรวจสอบสต็อก (Stock Audit), ยิงรีเช็ค (Recheck Scan),
  ตำแหน่งจัดเก็บ (Bulk Location), สต็อกคงเหลือ (Stock On-Hand), OCR
  ตรวจเอกสาร, and ความเคลื่อนไหวสต็อก (Stock Movement).
- `CLAUDE.md` and `CHANGELOG.md` added to document the project's
  architecture and history for future contributors (human or AI).

### Note
- The spec's menu list included a few items that already exist under a
  different name (Transfer → โอนสินค้าระหว่างคลัง, Return →
  สินค้าคืนคลัง, Reconcile Scan → กระทบยอด). Per user confirmation, the
  existing menus were left as-is rather than duplicated or renamed.

## 2026-09-18

### Fixed
- Numeric column headers (จำนวนใบ, คู่, อุปกรณ์เสริม, ยอดรวม) in the daily
  summary and main live tables were left-aligned while the numbers below
  them were right-aligned — added `th.num` alongside `td.num` so headers
  and data line up.
- `sync.js` was silently failing to map MySQL's `Id` column (capital I) to
  Postgres's `id`, causing `null value in column "id"` errors. Added it to
  `COLUMN_MAP`.
- Home page KPI totals were undercounted on high-volume days because
  Supabase/PostgREST caps query results at 1000 rows by default. Added an
  explicit `.limit(20000)` to the dispatch/receiving queries in
  `loadHomeData()`.
- Upgraded `@supabase/supabase-js` to the latest version — the old version
  couldn't authenticate with Supabase's newer `sb_secret_...` key format.
- Switched from Supabase's legacy `service_role` JWT key to the new
  `sb_secret_.../sb_publishable_...` key format project-wide.

### Changed
- **Live view data remap** (per warehouse manager feedback on what each
  menu should actually display): the "จ่ายสินค้าออก" (Dispatch) menu now
  shows the MySQL `receiving` table's data, and a newly built-out
  "โอนสินค้าระหว่างคลัง" (Transfer) menu shows the MySQL `dispatch` table's
  data. "รับสินค้าเข้า" (Receive) is now an empty placeholder pending a
  real data source.
- Gave "โอนสินค้าระหว่างคลัง" the full live-view UI (filters, daily
  summary, pagination, CSV export) matching the existing Dispatch view.
  All English column headers/filter placeholders in the live views were
  translated to Thai.
- Renamed sidebar/home-shortcut menu labels: "ย้ายโลเคชั่น" →
  "โอนสินค้าระหว่างคลัง", "รับคืนสินค้า" → "สินค้าคืนคลัง".
- `sync.js` now loops internally through pages (5000 rows/page) until
  fully caught up in a single run, persisting the watermark after every
  page, instead of syncing only one page per invocation. A large backfill
  (millions of rows) now finishes in one run and safely resumes from the
  last saved page if interrupted (Ctrl+C or crash).
- Truncated the Supabase `dispatch`/`receiving` tables and reset the sync
  watermark to start the backfill from the beginning of the current year
  instead of full history, per request.

### Security
- **Incident**: a real MySQL password and a real (later found non-working
  legacy) Supabase `service_role` JWT were accidentally committed to
  `.env.example` on the public repo. Fixed by restoring the placeholder
  version of `.env.example`; the MySQL password and the Supabase legacy
  JWT secret should be rotated (the exposure remains permanently in git
  history regardless).
- Used a temporary `ngrok http 3001` tunnel to demo the LAN-only API to a
  warehouse manager across network segments — explicitly temporary, closed
  after the demo, since `api-server.js` has no auth layer of its own and
  talks directly to production MySQL.

## 2026-09-17

### Added
- Live Dispatch/Receiving views backed directly by MySQL via a new
  LAN-only `api-server.js` (Express), so warehouse staff on-site see data
  with no sync delay. Serves both the `/api/:table` live API and the
  static `Index/index.html` app from one process.
- Daily summary ("สรุปยอดรายวัน") panel above the main invoice table in
  the live Dispatch/Receiving views, grouped by document date.
- Date picker on the Home page so KPIs can be viewed for any day, not just
  today.
- Reset Filter button that clears both the field filters and the
  All/Warehouse scope toggle back to defaults.
- Initial WMS project scaffold: `schema.sql` (Supabase schema mirroring
  MySQL `dispatch`/`receiving`), `sync.js` (MySQL → Supabase incremental
  sync), and setup docs.

### Changed
- Merged the separate live-data page into the main `Index/index.html` app
  (removed redundant `public/index.html` and `public/live.html`).
- Dispatch/Receiving date filters default to today instead of showing an
  unfiltered (and therefore extremely slow) query across millions of rows.
- Pointed `Index/index.html` at the new Supabase project (new URL/key).

## 2026-06-08 to 2026-06-11

- Early iteration on `index.html` and removal of an unused `logistic.html`
  page. Added `CNAME` for the GitHub Pages custom domain.

## 2026-05-29

- Initial upload of the project.
