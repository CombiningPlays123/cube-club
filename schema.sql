-- PostgreSQL/Supabase starting schema for the Cube Club backend.
-- Apply from trusted backend migration tooling only. Do not expose service credentials.
-- Adapt account_id to the canonical user/account table in Repository #1.

create extension if not exists pgcrypto;

create table if not exists users (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null unique,
  display_name text not null,
  role text not null default 'member' check (role in ('member','admin')),
  disabled_at timestamptz,
  profile_visibility jsonb not null default '{"points":true,"best_single":true,"best_average":true,"total_solves":true,"achievements":true}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists tokens (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null,
  token_hash bytea not null unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  last_used_at timestamptz,
  check (expires_at > created_at)
);
create index if not exists tokens_account_idx on tokens(account_id);

create table if not exists sessions (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null,
  session_hash bytea not null unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz
);

create table if not exists solves (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null,
  source text not null check (source in ('cs_timer_export','manual_admin','other')),
  source_solve_key text not null,
  duration_ms integer not null check (duration_ms > 0),
  scramble text,
  solved_at timestamptz,
  imported_at timestamptz not null default now(),
  review_status text not null default 'accepted' check (review_status in ('accepted','flagged','rejected')),
  review_reason text,
  unique(account_id, source, source_solve_key)
);
create index if not exists solves_account_time_idx on solves(account_id, solved_at desc);

create table if not exists goals (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text not null default '',
  kind text not null check (kind in ('solve_count','best_single','best_average','challenge')),
  threshold numeric not null check (threshold > 0),
  reward_points integer not null check (reward_points >= 0),
  one_time boolean not null default true,
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists user_goals (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null,
  goal_id uuid not null references goals(id),
  state text not null default 'IN PROGRESS' check (state in ('LOCKED','IN PROGRESS','COMPLETED')),
  progress numeric not null default 0,
  completed_at timestamptz,
  unique(account_id, goal_id)
);

create table if not exists points_transactions (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null,
  amount integer not null check (amount <> 0),
  reason text not null,
  source_type text not null check (source_type in ('goal','solve_milestone','challenge','event','redemption','refund','admin_adjustment')),
  source_id uuid,
  actor_account_id uuid,
  created_at timestamptz not null default now(),
  idempotency_key text unique
);
create index if not exists points_transactions_account_idx on points_transactions(account_id, created_at desc);

create table if not exists shop_items (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text not null default '',
  category text not null,
  price_points integer not null check (price_points >= 0),
  enabled boolean not null default true,
  fulfillment_type text not null default 'admin' check (fulfillment_type in ('admin','club_perk')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists redemptions (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null,
  shop_item_id uuid references shop_items(id),
  reward_name_snapshot text not null,
  cost_points integer not null check (cost_points >= 0),
  status text not null default 'PENDING' check (status in ('PENDING','APPROVED','FULFILLED','CANCELLED')),
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid,
  fulfilled_at timestamptz,
  fulfillment_note text
);

create table if not exists achievements (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text not null default '',
  icon text,
  enabled boolean not null default true
);
create table if not exists user_achievements (
  account_id uuid not null,
  achievement_id uuid not null references achievements(id),
  awarded_at timestamptz not null default now(),
  primary key(account_id, achievement_id)
);

create table if not exists audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_account_id uuid not null,
  action text not null,
  target_type text not null,
  target_id text not null,
  reason text,
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz not null default now()
);

create table if not exists club_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by uuid
);

-- Recommended transaction discipline: redemption inserts/debit transactions inside one DB transaction,
-- locks the account's balance row or ledger range, and rejects if sum(points_transactions) is too low.
-- Add RLS policies only after deciding whether browser clients can access tables directly. The default
-- recommendation is backend-only table access with a least-privilege database role.
