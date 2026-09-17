-- ═══════════════════════════════════════════════════════════════
-- Bata WMS — Auth & Role-based access control
-- Run this in Supabase → SQL Editor, AFTER schema.sql (dispatch/receiving)
-- has already been created.
-- ═══════════════════════════════════════════════════════════════

-- ─── profiles: one row per Supabase Auth user, holds the app role ─
create table if not exists profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text,
  full_name  text,
  role       text not null default 'viewer'
             check (role in ('admin', 'warehouse_staff', 'viewer')),
  created_at timestamptz not null default now()
);

-- Auto-create a profile row (default role: viewer) whenever a new
-- user is added in Supabase Auth (dashboard → Authentication → Add user).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Helper: current user's role, callable from RLS policies without
-- causing infinite recursion (SECURITY DEFINER bypasses the caller's
-- own RLS when this function reads `profiles`).
create or replace function public.my_role()
returns text
language sql
security definer
set search_path = public
stable
as $$
  select role from public.profiles where id = auth.uid();
$$;

-- ─── RLS: profiles ────────────────────────────────────────────────
alter table profiles enable row level security;

drop policy if exists "self can read own profile" on profiles;
create policy "self can read own profile" on profiles
  for select using (auth.uid() = id);

drop policy if exists "admin can read all profiles" on profiles;
create policy "admin can read all profiles" on profiles
  for select using (public.my_role() = 'admin');

drop policy if exists "admin can update roles" on profiles;
create policy "admin can update roles" on profiles
  for update using (public.my_role() = 'admin');

-- ─── RLS: dispatch / receiving ─────────────────────────────────────
-- Any signed-in user can read (the app hides nav items by role, but
-- that's a UX convenience only — this is the real enforcement layer).
-- Only admin / warehouse_staff can write, for when input forms are built.
alter table dispatch enable row level security;
alter table receiving enable row level security;

drop policy if exists "authenticated can read dispatch" on dispatch;
create policy "authenticated can read dispatch" on dispatch
  for select using (auth.role() = 'authenticated');

drop policy if exists "staff/admin can write dispatch" on dispatch;
create policy "staff/admin can write dispatch" on dispatch
  for insert with check (public.my_role() in ('admin', 'warehouse_staff'));

drop policy if exists "staff/admin can update dispatch" on dispatch;
create policy "staff/admin can update dispatch" on dispatch
  for update using (public.my_role() in ('admin', 'warehouse_staff'));

drop policy if exists "authenticated can read receiving" on receiving;
create policy "authenticated can read receiving" on receiving
  for select using (auth.role() = 'authenticated');

drop policy if exists "staff/admin can write receiving" on receiving;
create policy "staff/admin can write receiving" on receiving
  for insert with check (public.my_role() in ('admin', 'warehouse_staff'));

drop policy if exists "staff/admin can update receiving" on receiving;
create policy "staff/admin can update receiving" on receiving
  for update using (public.my_role() in ('admin', 'warehouse_staff'));

-- Note: sync.js (the MySQL -> Supabase script) uses the service_role
-- key, which bypasses RLS entirely — these policies only govern what
-- the browser app itself can do with the anon key.

-- ─── Bootstrap: make yourself the first admin ─────────────────────
-- 1. Create your own user in Supabase Dashboard -> Authentication -> Add user
-- 2. Run this once, with your own email, to promote yourself to admin:
--
-- update profiles set role = 'admin' where email = 'you@example.com';
