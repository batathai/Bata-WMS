-- ═══════════════════════════════════════════════════════════════
-- Bata Kore Stock Movement — Supabase schema
-- Mirrors the source MySQL tables `dispatch` and `receiving`
-- (host 192.1.1.38, database `reporting`)
--
-- Run this ONCE in Supabase → SQL Editor before running sync.js
-- ═══════════════════════════════════════════════════════════════

-- ─── dispatch ──────────────────────────────────────────────────
create table if not exists dispatch (
  id            bigint primary key,        -- same id as MySQL source (used for upsert)
  booked_date   date not null,
  document_date date not null,
  sender        varchar(5) not null,
  receiver      varchar(5),
  invoice       varchar(20),
  article       varchar(7) not null,
  size          varchar(3),
  items         integer,
  category      varchar(2),
  sub_category  varchar(2),
  price         numeric(8,2),
  amount        numeric(14,2),              -- computed in MySQL (price*items), synced as plain value here
  is_footware   boolean default false,
  is_fa2a       boolean default false,
  created_at    timestamptz not null default now(),  -- original createdAt from source
  updated_at    timestamptz not null default now(),  -- original updatedAt from source — used as sync watermark
  synced_at     timestamptz not null default now()   -- when THIS row was last written by sync.js
);

create index if not exists idx_dispatch_document_date on dispatch (document_date);
create index if not exists idx_dispatch_invoice on dispatch (invoice);
create index if not exists idx_dispatch_updated_at on dispatch (updated_at);

-- ─── receiving ─────────────────────────────────────────────────
create table if not exists receiving (
  id            bigint primary key,
  booked_date   date not null,
  send_date     date not null,               -- extra column vs dispatch
  document_date date not null,
  sender        varchar(5),
  receiver      varchar(5),
  invoice       varchar(20),
  article       varchar(7) not null,
  size          varchar(3),
  items         integer,
  category      varchar(2),
  sub_category  varchar(2),
  price         numeric(8,2),
  amount        numeric(14,2),
  is_footware   boolean default false,
  is_fa2a       boolean default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  synced_at     timestamptz not null default now()
);

create index if not exists idx_receiving_booked_date on receiving (booked_date);
create index if not exists idx_receiving_invoice on receiving (invoice);
create index if not exists idx_receiving_updated_at on receiving (updated_at);

-- ─── Row Level Security ────────────────────────────────────────
-- Uncomment and adjust once you know which roles/keys should read this data.
-- alter table dispatch enable row level security;
-- alter table receiving enable row level security;
-- create policy "read for authenticated" on dispatch for select using (auth.role() = 'authenticated');
-- create policy "read for authenticated" on receiving for select using (auth.role() = 'authenticated');

-- Note: intentionally NOT syncing the `users` table from the source MySQL DB.
-- It stores a `password` column directly, which is a separate/legacy concern
-- from this reporting sync — don't copy it here without a specific reason
-- and a plan for how it will be secured in the new system.
