# Bata WMS — with login & role-based access

`index.html` is a single self-contained file. It uses Supabase for both
login (Supabase Auth) and data (the `dispatch` / `receiving` tables from
the MySQL sync).

## Roles

| Role | Thai label | Can see |
|---|---|---|
| `admin` | ผู้ดูแลระบบ | Everything, plus "จัดการผู้ใช้งาน" to set other users' roles |
| `warehouse_staff` | เจ้าหน้าที่คลังสินค้า | หน้าหลัก, แดชบอร์ด, แจ้งเตือน + ทุกเมนูงานคลังสินค้า (รับเข้า/จ่ายออก/ย้าย/รับคืน/เบิกใช้) + มาสเตอร์ดาต้า, ตรวจนับสต็อก, กระทบยอด, ประวัติเอกสาร |
| `viewer` | ผู้บริหาร / ดูรายงาน | หน้าหลัก, แดชบอร์ด, รายงานบริหาร, แจ้งเตือน, มาสเตอร์ดาต้า, ประวัติเอกสาร (อ่านอย่างเดียว — ไม่เห็นเมนูที่แก้ไขข้อมูล) |

Edit the `data-roles="..."` attribute on any nav button / shortcut card in
`index.html` to change what each role can see.

**Important:** hiding menu items in the browser is UX only, not security.
The real enforcement is the Row Level Security policies in
`auth-and-roles.sql` — those control what each role can actually read/write
in the database, regardless of what the page shows.

## Setup

1. **Run `schema.sql`** from the sync project first (creates `dispatch`/`receiving`), if you haven't already.
2. **Run `auth-and-roles.sql`** in Supabase → SQL Editor. This creates:
   - `profiles` table (one row per user, holds their `role`)
   - a trigger that auto-creates a `profiles` row (default role `viewer`) whenever you add a user in Supabase Auth
   - RLS policies for `profiles`, `dispatch`, `receiving`
3. **Create your users** in Supabase → Authentication → Users → Add user (email + password). Do this for everyone who needs to log in.
4. **Promote your own account to admin** — run once in SQL Editor:
   ```sql
   update profiles set role = 'admin' where email = 'you@example.com';
   ```
   Everyone else defaults to `viewer` until an admin changes their role
   from the app's "จัดการผู้ใช้งาน" page.
5. **Fill in Supabase connection details** at the top of `index.html`:
   ```js
   const SUPABASE_URL = 'https://YOUR-PROJECT.supabase.co';
   const SUPABASE_ANON_KEY = 'YOUR-ANON-KEY';
   ```
   Use the **anon** key here (Settings → API), not the service_role key —
   this file runs in every visitor's browser, so it must only carry the
   key that RLS is designed to restrict.
6. **Host it** via `api-server.js` — see the root `README.md`. This is now
   the only way the app is deployed (`http://<lan-ip>:3001`); the earlier
   public GitHub Pages deployment (`tms.batathai.com`) is no longer used.

## What's wired to real data vs. placeholder

- **Home page KPIs, spark chart, recent documents table** — live queries
  against `dispatch` / `receiving` in Supabase (today's rows).
- **Login, logout, role detection, nav/shortcut visibility** — fully working.
- **User management (admin)** — lists everyone in `profiles`, lets an admin
  change any user's role live.
- **รับสินค้าเข้า (Receiving) / จ่ายสินค้าออก (Dispatch)** — live, grouped-by-invoice
  tables with filters, CSV export, but **only when this page is opened from
  inside the office LAN** (e.g. `http://<lan-ip>:3001`, served by
  `../api-server.js`). They call `/api/dispatch` and `/api/receiving`, which
  query the source MySQL directly (no sync delay).
- **All other menu items** (มาสเตอร์ดาต้า, ตรวจนับสต็อก, etc.)
  — the navigation and role-gating work, but each page is currently a
  placeholder panel. Building out each one as a real form/table is the
  natural next step — happy to do any of them next.

## Known gaps to flag before this goes to real users

- KPI cards for "จำนวนสินค้า (Article)" and "จำนวนตำแหน่งจัดเก็บ (Location)"
  from the original mockup aren't shown yet — there's no synced master-data
  table for articles/locations yet, only movement data (`dispatch`/`receiving`).
  Let me know if you want those tables added to the sync too.
- No password-reset flow yet (Supabase Auth supports one — can add a
  "ลืมรหัสผ่าน" link if needed).
- `viewer` role currently only reads; if execs need to export data, that's
  worth adding as its own explicit feature rather than a role side-effect.
