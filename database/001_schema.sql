-- Perkify / Supabase PostgreSQL 15+
-- Run once in the Supabase SQL editor before 002_functions.sql.
-- Supabase supplies auth.users, auth.uid(), anon, and authenticated.
begin;

create table public.perkify_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '' check (char_length(name) <= 40),
  currency text not null default 'MYR' check (currency in ('MYR','USD','SGD','EUR','GBP')),
  timezone text not null default 'Asia/Kuala_Lumpur',
  version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.perkify_cards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.perkify_profiles(user_id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 80),
  category text not null default 'Other' check (category in ('Food & drink','Shopping','Travel','Lifestyle','Other')),
  points numeric(16,2) not null default 0 check (points >= 0 and points < 1000000000000),
  unit text not null default 'Points' check (char_length(btrim(unit)) between 1 and 25),
  estimated_value numeric(16,2) not null default 0 check (estimated_value >= 0 and estimated_value < 1000000000000),
  expires_on date check (expires_on between date '0001-01-01' and date '9999-12-31'),
  member_number text not null default '' check (char_length(member_number) <= 60),
  color text not null default 'green' check (color in ('green','dark','red','blue','orange','lime','purple')),
  note text not null default '' check (char_length(note) <= 1000),
  version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.perkify_vouchers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.perkify_profiles(user_id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 80),
  brand text not null check (char_length(btrim(brand)) between 1 and 60),
  category text not null default 'Shopping' check (category in ('Food & drink','Shopping','Travel','Lifestyle','Other')),
  value numeric(16,2) not null default 0 check (value >= 0 and value < 1000000000000),
  code text not null default '' check (char_length(code) <= 100),
  expires_on date check (expires_on between date '0001-01-01' and date '9999-12-31'),
  color text not null default 'orange' check (color in ('green','dark','red','blue','orange','lime','purple')),
  note text not null default '' check (char_length(note) <= 1000),
  redeemed_at timestamptz,
  version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Immutable snapshots retain their meaning even after a card or voucher is removed.
create table public.perkify_activity (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.perkify_profiles(user_id) on delete cascade,
  name text not null check (char_length(name) <= 80),
  detail text not null check (char_length(detail) <= 100),
  amount numeric(16,2) not null default 0 check (amount >= 0 and amount < 1000000000000),
  unit text not null default '' check (char_length(unit) <= 25),
  kind text not null check (kind in ('add','earn','redeem')),
  color text not null check (color in ('green','dark','red','blue','orange','lime','purple')),
  currency text not null check (currency in ('MYR','USD','SGD','EUR','GBP')),
  occurred_at timestamptz not null default now() check (isfinite(occurred_at))
);

-- Requests are idempotent: retrying the same request_id never earns/redeems twice.
create table public.perkify_point_transactions (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique,
  user_id uuid not null references public.perkify_profiles(user_id) on delete cascade,
  card_id uuid references public.perkify_cards(id) on delete set null,
  kind text not null check (kind in ('opening','adjust','earn','redeem')),
  points_delta numeric(16,2) not null,
  balance_after numeric(16,2) not null check (balance_after >= 0 and balance_after < 1000000000000),
  estimated_value_after numeric(16,2) not null check (estimated_value_after >= 0 and estimated_value_after < 1000000000000),
  request_payload jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create index perkify_cards_owner_created on public.perkify_cards(user_id, created_at desc, id);
create index perkify_cards_owner_expiry on public.perkify_cards(user_id, expires_on) where expires_on is not null;
create index perkify_vouchers_owner_created on public.perkify_vouchers(user_id, created_at desc, id);
create index perkify_vouchers_owner_expiry on public.perkify_vouchers(user_id, expires_on) where redeemed_at is null;
create index perkify_activity_owner_date on public.perkify_activity(user_id, occurred_at desc, id);
create index perkify_transactions_owner_date on public.perkify_point_transactions(user_id, created_at desc);
create index perkify_transactions_card on public.perkify_point_transactions(card_id);

create function public.perkify_touch_row() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := clock_timestamp();
  new.version := old.version + 1;
  return new;
end;
$$;
create trigger perkify_profiles_touch before update on public.perkify_profiles for each row execute function public.perkify_touch_row();
create trigger perkify_cards_touch before update on public.perkify_cards for each row execute function public.perkify_touch_row();
create trigger perkify_vouchers_touch before update on public.perkify_vouchers for each row execute function public.perkify_touch_row();

create function public.perkify_on_signup() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.perkify_profiles(user_id, name)
  values (new.id, left(coalesce(new.raw_user_meta_data ->> 'name', ''), 40))
  on conflict (user_id) do nothing;
  return new;
end;
$$;
create trigger perkify_user_created after insert on auth.users for each row execute function public.perkify_on_signup();
-- Also support users created before this migration.
insert into public.perkify_profiles(user_id, name)
select id, left(coalesce(raw_user_meta_data ->> 'name', ''), 40) from auth.users
on conflict (user_id) do nothing;

alter table public.perkify_profiles enable row level security;
alter table public.perkify_cards enable row level security;
alter table public.perkify_vouchers enable row level security;
alter table public.perkify_activity enable row level security;
alter table public.perkify_point_transactions enable row level security;

create policy owner_read on public.perkify_profiles for select to authenticated using (user_id = (select auth.uid()));
create policy owner_read on public.perkify_cards for select to authenticated using (user_id = (select auth.uid()));
create policy owner_read on public.perkify_vouchers for select to authenticated using (user_id = (select auth.uid()));
create policy owner_read on public.perkify_activity for select to authenticated using (user_id = (select auth.uid()));
create policy owner_read on public.perkify_point_transactions for select to authenticated using (user_id = (select auth.uid()));

-- Writes go through the functions in 002, not client-side table updates.
revoke all on public.perkify_profiles, public.perkify_cards, public.perkify_vouchers,
  public.perkify_activity, public.perkify_point_transactions from public, anon, authenticated;
grant select on public.perkify_profiles, public.perkify_cards, public.perkify_vouchers,
  public.perkify_activity, public.perkify_point_transactions to authenticated;
revoke all on function public.perkify_touch_row(), public.perkify_on_signup() from public, anon, authenticated;

commit;
