-- ═══════════════════════════════════════════════════════════════
-- Bata WMS — Barcode reconciliation ("กระทบยอด") schema
--
-- Backs the "กระทบยอด" page in Index/index.html: a warehouse staff
-- member uploads an Excel "starting file" for a batch/round, then
-- scans barcodes against it to reconcile expected vs. actual stock.
--
-- Run this ONCE in Supabase → SQL Editor before using the "กระทบยอด"
-- menu. Requires the `profiles` table from auth-and-roles.sql to
-- already exist (used for role-based access below).
-- ═══════════════════════════════════════════════════════════════

create extension if not exists pgcrypto;

-- ─── reconcile_batches ─────────────────────────────────────────
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

-- ─── reconcile_items ───────────────────────────────────────────
-- Parsed rows from the uploaded "ไฟล์ตั้งต้น" — the expected stock
-- for this batch ("ยอดตั้งต้น"). Re-uploading the file replaces
-- these rows for the batch (see app logic in index.html).
create table if not exists reconcile_items (
  id            bigserial primary key,
  batch_id      uuid not null references reconcile_batches(id) on delete cascade,
  barcode       text not null,
  cat           text,
  article       text,
  size          text,
  qty_expected  integer not null default 0,
  created_at    timestamptz not null default now()
);

create index if not exists idx_reconcile_items_batch on reconcile_items (batch_id);
create index if not exists idx_reconcile_items_barcode on reconcile_items (batch_id, barcode);

-- ─── reconcile_scans ───────────────────────────────────────────
-- One row per barcode scan event ("ยิง Barcode"). Matched against
-- reconcile_items for the same batch to decide ตรง/ไม่ตรง.
create table if not exists reconcile_scans (
  id            bigserial primary key,
  batch_id      uuid not null references reconcile_batches(id) on delete cascade,
  barcode       text not null,
  cat           text,
  article       text,
  size          text,
  qty           integer not null default 1,
  result        text not null check (result in ('ตรง', 'ไม่ตรง')),
  reason        text,                          -- สาเหตุ, e.g. "ไม่พบใน Batch", "ยิงเกินจำนวนที่กำหนด"
  remark        text,
  scanned_by    uuid references auth.users(id),
  scanned_at    timestamptz not null default now()
);

create index if not exists idx_reconcile_scans_batch on reconcile_scans (batch_id);
create index if not exists idx_reconcile_scans_barcode on reconcile_scans (batch_id, barcode);

-- ─── Row Level Security ────────────────────────────────────────
-- Same admin/warehouse_staff gate as the rest of the app's write
-- operations (see auth-and-roles.sql for the `profiles` table).
alter table reconcile_batches enable row level security;
alter table reconcile_items enable row level security;
alter table reconcile_scans enable row level security;

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
