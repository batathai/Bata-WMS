-- ══════════════════════════════════════════════════════════════════
-- Bata WMS — Barcode reconciliation ("กระทบยอด") schema
--
-- Backs the "กระทบยอด" page in Index/index.html: a warehouse staff
-- member uploads an Excel "starting file" for a batch/round, then
-- scans barcodes against it to reconcile expected vs. actual stock.
--
-- Run this ONCE in Supabase → SQL Editor before using the "กระทบยอด"
-- menu. Requires the `profiles` table from auth-and-roles.sql to
-- already exist (used for role-based access below).
-- ════════════════════════════════════════════════════════════════

create extension if not exists pgcrypto;

-- ─── reconcile_batches ──────────────────────────────────
-- One row per "Batch ID / รอบงาน".
create table if not exists reconcile_batches (
  id              uuid primary key default gen_random_uuid(),
  batch_code      text not null unique,       -- "Batch ID / รอบงาน", e.g. WK34-001
  source_filename text,                        -- ชื่อไฟล์ตั้งต้น, e.g. CN 2026 Week 34.xlsx
  status          text not null default 'open' check (status in ('open', 'closed')),
  created_by      uuid references auth.users(id),
  created_at      timestamptz not null default now(),
  closed_at       timestamptz
);

-- ─── reconcile_items ────────────────────────────────────
-- Parsed rows from the uploaded "ไฟล์ตั้งต้น" — the expected stock
-- for this batch ("ยอดตั้งต้น"). Re-uploading the file replaces
-- these rows for the batch (see app logic in index.html). Matched
-- against scans by article+size — the legacy source file this was
-- reverse-engineered from (T_Reconcile_Base) has no barcode column at
-- all, so `barcode` here is optional (kept in case a source file ever
-- includes one).
create table if not exists reconcile_items (
  id            bigserial primary key,
  batch_id      uuid not null references reconcile_batches(id) on delete cascade,
  barcode       text,
  cat           text,                          -- warehouse zone/rack code, e.g. "12", "Online", "ชั้นลอย" — not a product category
  article       text,
  size          text,
  qty_expected  integer not null default 0,
  remark        text,                          -- e.g. "Good" — condition note from the ไฟล์ตั้งต้น
  created_at    timestamptz not null default now()
);

-- Table may already exist from before this column was added.
alter table reconcile_items alter column barcode drop not null;
alter table reconcile_items add column if not exists remark text;

create index if not exists idx_reconcile_items_batch on reconcile_items (batch_id);
create index if not exists idx_reconcile_items_article_size on reconcile_items (batch_id, article, size);

-- ─── reconcile_scans ────────────────────────────────────
-- One row per barcode scan event ("ยิง Barcode"). Matched against
-- reconcile_items for the same batch by article+size (barcode is
-- parsed client-side into article+size, not compared literally) to
-- decide ตรง/ไม่ตรง. `qty` is 1 for an accepted (ตรง) scan and 0 for a
-- rejected one — once accepted scans for an article+size reach that
-- item's qty_expected, further scans of it are rejected rather than
-- over-counted (see `reason` values in app logic).
create table if not exists reconcile_scans (
  id            bigserial primary key,
  batch_id      uuid not null references reconcile_batches(id) on delete cascade,
  barcode       text not null,
  cat           text,
  article       text,
  size          text,
  qty           integer not null default 1,
  result        text not null check (result in ('ตรง', 'ไม่ตรง')),
  reason        text,                          -- สาเหตุที่ไม่ตรง, e.g. "ไม่พบ Article ... ในไฟล์ตั้งต้น"
  remark        text,
  scanned_by    uuid references auth.users(id),
  scanned_at    timestamptz not null default now()
);

create index if not exists idx_reconcile_scans_batch on reconcile_scans (batch_id);
create index if not exists idx_reconcile_scans_article_size on reconcile_scans (batch_id, article, size);

-- ─── reconcile_history ─────────────────────────────────
-- Append-only log: one row per "ปิดงาน / บันทึก History" click,
-- freezing the batch's summary numbers plus who closed it and when.
-- A batch can in principle be reopened (directly in Supabase) and
-- closed again, so this is a log rather than a 1:1 row per batch.
create table if not exists reconcile_history (
  id                bigserial primary key,
  batch_id          uuid not null references reconcile_batches(id) on delete cascade,
  closed_at         timestamptz not null default now(),
  closed_by         text not null,             -- ผู้ปิดรอบ (email)
  base_qty          integer not null,
  accepted_qty      integer not null,
  remaining_qty     integer not null,          -- ผลต่าง
  base_lines        integer not null,
  matched_lines     integer not null,
  partial_lines     integer not null,
  not_scanned_lines integer not null,
  total_scan_rows   integer not null,
  rejected_scans    integer not null,
  error_rows        integer not null,
  remark            text
);

create index if not exists idx_reconcile_history_batch on reconcile_history (batch_id);

-- ─── Row Level Security ──────────────────────────────────
-- Same admin/warehouse_staff gate as the rest of the app's write
-- operations (see auth-and-roles.sql for the `profiles` table).
alter table reconcile_batches enable row level security;
alter table reconcile_items enable row level security;
alter table reconcile_scans enable row level security;
alter table reconcile_history enable row level security;

create or replace function is_wms_staff()
returns boolean
language sql
stable
as $$
  select exists (
    select 1 from profiles p
    where p.id = auth.uid() and p.role in ('admin', 'warehouse_staff')
  );
$$;

create policy "reconcile_batches staff access" on reconcile_batches
  for all using (is_wms_staff()) with check (is_wms_staff());

create policy "reconcile_items staff access" on reconcile_items
  for all using (is_wms_staff()) with check (is_wms_staff());

create policy "reconcile_scans staff access" on reconcile_scans
  for all using (is_wms_staff()) with check (is_wms_staff());

create policy "reconcile_history staff access" on reconcile_history
  for all using (is_wms_staff()) with check (is_wms_staff());
