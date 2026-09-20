-- Run once, after 004_item_currency.sql, in the Supabase SQL Editor.
-- Adds stamp cards: a simple loyalty tracker ("buy 9, get 1 free") separate
-- from cards (point balances) and vouchers (cash value). Progress changes
-- only through perkify_add_stamp/perkify_remove_stamp/perkify_redeem_stamp_card,
-- so rapid tapping stays race-free under the same row lock used elsewhere.
begin;

create table public.perkify_stamp_cards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.perkify_profiles(user_id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 80),
  category text not null default 'Other' check (category in ('Food & drink','Shopping','Travel','Lifestyle','Other')),
  target integer not null default 9 check (target between 1 and 100),
  stamps integer not null default 0 check (stamps >= 0 and stamps <= target),
  reward text not null default '' check (char_length(reward) <= 200),
  completions integer not null default 0 check (completions >= 0),
  color text not null default 'green' check (color in ('green','dark','red','blue','orange','lime','purple')),
  note text not null default '' check (char_length(note) <= 1000),
  version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index perkify_stamp_cards_owner_created on public.perkify_stamp_cards(user_id, created_at desc, id);
create trigger perkify_stamp_cards_touch before update on public.perkify_stamp_cards for each row execute function public.perkify_touch_row();

alter table public.perkify_stamp_cards enable row level security;
create policy owner_read on public.perkify_stamp_cards for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.perkify_stamp_cards from public, anon, authenticated;
grant select on public.perkify_stamp_cards to authenticated;

-- perkify_get_wallet, perkify_clear_wallet, perkify_delete_perk, and
-- perkify_replace_wallet gain stamp-card support below; their signatures
-- (and therefore existing grants) are unchanged.

create or replace function public.perkify_get_wallet() returns jsonb
language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object(
    'settings', (select jsonb_build_object('name', name, 'currency', currency, 'timezone', timezone, 'version', version)
      from public.perkify_profiles where user_id = auth.uid()),
    'cards', coalesce((select jsonb_agg(jsonb_build_object(
      'id', id, 'name', name, 'category', category, 'points', points, 'unit', unit,
      'value', estimated_value, 'currency', currency, 'expiry', coalesce(expires_on::text, ''), 'member', member_number,
      'color', color, 'note', note, 'version', version) order by created_at desc, id)
      from public.perkify_cards where user_id = auth.uid()), '[]'::jsonb),
    'vouchers', coalesce((select jsonb_agg(jsonb_build_object(
      'id', id, 'name', name, 'brand', brand, 'category', category, 'value', value, 'currency', currency, 'code', code,
      'expiry', coalesce(expires_on::text, ''), 'color', color, 'note', note,
      'redeemed', redeemed_at is not null, 'version', version) order by created_at desc, id)
      from public.perkify_vouchers where user_id = auth.uid()), '[]'::jsonb),
    'stampCards', coalesce((select jsonb_agg(jsonb_build_object(
      'id', id, 'name', name, 'category', category, 'target', target, 'stamps', stamps, 'reward', reward,
      'completions', completions, 'color', color, 'note', note, 'version', version) order by created_at desc, id)
      from public.perkify_stamp_cards where user_id = auth.uid()), '[]'::jsonb),
    'activity', coalesce((select jsonb_agg(jsonb_build_object(
      'id', id, 'name', name, 'detail', detail, 'amount', amount, 'unit', unit,
      'kind', kind, 'color', color, 'date', occurred_at, 'currency', currency)
      order by occurred_at desc, id)
      from (select * from public.perkify_activity where user_id = auth.uid()
        order by occurred_at desc, id limit 2000) a), '[]'::jsonb)
  );
$$;

-- Metadata only (name/category/target/reward/color/note). Progress (stamps,
-- completions) is untouched here except on creation, where a backup/import
-- may carry starting values.
create function public.perkify_save_stamp_card(p_card jsonb, p_expected_version bigint default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := public.perkify_lock_wallet(); v_id uuid; v_new boolean;
  v_target integer; v_stamps integer; v_completions integer; v_old public.perkify_stamp_cards; v_card public.perkify_stamp_cards;
begin
  v_new := nullif(p_card->>'id', '') is null;
  v_target := coalesce((p_card->>'target')::integer, 9);
  if v_target < 1 or v_target > 100 then raise exception 'Stamps needed must be between 1 and 100' using errcode = '22023'; end if;
  if v_new then
    v_stamps := least(greatest(coalesce((p_card->>'stamps')::integer, 0), 0), v_target);
    v_completions := greatest(coalesce((p_card->>'completions')::integer, 0), 0);
    insert into public.perkify_stamp_cards(user_id, name, category, target, stamps, reward, completions, color, note)
    values(v_user, btrim(p_card->>'name'), p_card->>'category', v_target, v_stamps,
      coalesce(p_card->>'reward', ''), v_completions, p_card->>'color', coalesce(p_card->>'note', ''))
    returning * into v_card;
    perform public.perkify_log(v_user, v_card.name, 'Stamp card added', 0, 'stamp', 'add', v_card.color);
  else
    v_id := (p_card->>'id')::uuid;
    select * into v_old from public.perkify_stamp_cards where id = v_id and user_id = v_user for update;
    if not found then raise exception 'Stamp card not found' using errcode = '22023'; end if;
    if p_expected_version is null or v_old.version <> p_expected_version then
      raise exception 'Stamp card changed. Reload before saving.' using errcode = '40001';
    end if;
    update public.perkify_stamp_cards set name = btrim(p_card->>'name'), category = p_card->>'category',
      target = v_target, stamps = least(v_old.stamps, v_target), reward = coalesce(p_card->>'reward', ''),
      color = p_card->>'color', note = coalesce(p_card->>'note', '')
      where id = v_id returning * into v_card;
  end if;
  return v_card.id;
end;
$$;

create function public.perkify_add_stamp(p_card_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := public.perkify_lock_wallet(); v_card public.perkify_stamp_cards;
begin
  select * into v_card from public.perkify_stamp_cards where id = p_card_id and user_id = v_user for update;
  if not found then raise exception 'Stamp card not found' using errcode = '22023'; end if;
  if v_card.stamps >= v_card.target then raise exception 'This card is full. Redeem it before adding more stamps.' using errcode = '22023'; end if;
  update public.perkify_stamp_cards set stamps = stamps + 1 where id = p_card_id returning * into v_card;
  perform public.perkify_log(v_user, v_card.name, 'Stamp added', v_card.stamps, 'stamp', 'earn', v_card.color);
  return public.perkify_get_wallet();
end;
$$;

-- Idempotent at zero so a duplicate/late tap has no further effect.
create function public.perkify_remove_stamp(p_card_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := public.perkify_lock_wallet(); v_card public.perkify_stamp_cards;
begin
  select * into v_card from public.perkify_stamp_cards where id = p_card_id and user_id = v_user for update;
  if not found then raise exception 'Stamp card not found' using errcode = '22023'; end if;
  if v_card.stamps = 0 then return public.perkify_get_wallet(); end if;
  update public.perkify_stamp_cards set stamps = stamps - 1 where id = p_card_id;
  return public.perkify_get_wallet();
end;
$$;

create function public.perkify_redeem_stamp_card(p_card_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := public.perkify_lock_wallet(); v_card public.perkify_stamp_cards;
begin
  select * into v_card from public.perkify_stamp_cards where id = p_card_id and user_id = v_user for update;
  if not found then raise exception 'Stamp card not found' using errcode = '22023'; end if;
  if v_card.stamps < v_card.target then raise exception 'Not enough stamps yet' using errcode = '22023'; end if;
  update public.perkify_stamp_cards set stamps = 0, completions = completions + 1 where id = p_card_id;
  perform public.perkify_log(v_user, v_card.name, 'Reward redeemed', v_card.target, 'stamp', 'redeem', v_card.color);
  return public.perkify_get_wallet();
end;
$$;

create or replace function public.perkify_delete_perk(p_kind text, p_id uuid, p_expected_version bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := public.perkify_lock_wallet();
begin
  if p_kind = 'card' then
    delete from public.perkify_cards where id = p_id and user_id = v_user and version = p_expected_version;
  elsif p_kind = 'voucher' then
    delete from public.perkify_vouchers where id = p_id and user_id = v_user and version = p_expected_version;
  elsif p_kind = 'stamp' then
    delete from public.perkify_stamp_cards where id = p_id and user_id = v_user and version = p_expected_version;
  else raise exception 'Invalid perk type' using errcode = '22023';
  end if;
  if not found then raise exception 'Perk missing or changed. Reload before removing.' using errcode = '40001'; end if;
  return public.perkify_get_wallet();
end;
$$;

create or replace function public.perkify_clear_wallet() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := public.perkify_lock_wallet();
begin
  delete from public.perkify_point_transactions where user_id = v_user;
  delete from public.perkify_activity where user_id = v_user;
  delete from public.perkify_cards where user_id = v_user;
  delete from public.perkify_vouchers where user_id = v_user;
  delete from public.perkify_stamp_cards where user_id = v_user;
  return public.perkify_get_wallet();
end;
$$;

-- stampCards is optional in older backups; treated as empty when absent.
create or replace function public.perkify_replace_wallet(p_wallet jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := public.perkify_lock_wallet(); v_item jsonb; v_id uuid; v_version bigint; v_currency text;
begin
  if jsonb_typeof(p_wallet) is distinct from 'object'
    or jsonb_typeof(p_wallet->'settings') is distinct from 'object'
    or jsonb_typeof(p_wallet->'cards') is distinct from 'array'
    or jsonb_typeof(p_wallet->'vouchers') is distinct from 'array'
    or (p_wallet ? 'stampCards' and jsonb_typeof(p_wallet->'stampCards') is distinct from 'array')
    or jsonb_typeof(p_wallet->'activity') is distinct from 'array' then
    raise exception 'Invalid Perkify backup shape' using errcode = '22023';
  end if;
  if jsonb_array_length(p_wallet->'cards') > 1000 or jsonb_array_length(p_wallet->'vouchers') > 1000
    or jsonb_array_length(coalesce(p_wallet->'stampCards', '[]'::jsonb)) > 1000
    or jsonb_array_length(p_wallet->'activity') > 2000 or octet_length(p_wallet::text) > 5000000 then
    raise exception 'Backup exceeds the supported size' using errcode = '22023';
  end if;
  select version into v_version from public.perkify_profiles where user_id = v_user;
  perform public.perkify_save_profile(p_wallet->'settings', v_version);
  v_currency := p_wallet->'settings'->>'currency';
  perform public.perkify_clear_wallet();
  for v_item in select value from jsonb_array_elements(p_wallet->'cards') loop
    if jsonb_typeof(v_item) is distinct from 'object' then raise exception 'Invalid card'; end if;
    perform public.perkify_save_card(v_item - 'id');
  end loop;
  for v_item in select value from jsonb_array_elements(p_wallet->'vouchers') loop
    if jsonb_typeof(v_item) is distinct from 'object' or jsonb_typeof(v_item->'redeemed') is distinct from 'boolean' then raise exception 'Invalid voucher'; end if;
    v_id := public.perkify_save_voucher(v_item - 'id');
    if (v_item->>'redeemed')::boolean then
      update public.perkify_vouchers set redeemed_at = now() where id = v_id and user_id = v_user;
    end if;
  end loop;
  for v_item in select value from jsonb_array_elements(coalesce(p_wallet->'stampCards', '[]'::jsonb)) loop
    if jsonb_typeof(v_item) is distinct from 'object' then raise exception 'Invalid stamp card'; end if;
    perform public.perkify_save_stamp_card(v_item - 'id');
  end loop;
  -- Preserve backup history rather than generating fictitious new earnings.
  delete from public.perkify_activity where user_id = v_user;
  for v_item in select value from jsonb_array_elements(p_wallet->'activity') loop
    insert into public.perkify_activity(user_id, name, detail, amount, unit, kind, color, currency, occurred_at)
    values(v_user, v_item->>'name', v_item->>'detail', (v_item->>'amount')::numeric, v_item->>'unit',
      v_item->>'kind', v_item->>'color', coalesce(v_item->>'currency', v_currency), (v_item->>'date')::timestamptz);
  end loop;
  return public.perkify_get_wallet();
end;
$$;

revoke all on function public.perkify_save_stamp_card(jsonb,bigint), public.perkify_add_stamp(uuid),
  public.perkify_remove_stamp(uuid), public.perkify_redeem_stamp_card(uuid) from public, anon, authenticated;
grant execute on function public.perkify_save_stamp_card(jsonb,bigint), public.perkify_add_stamp(uuid),
  public.perkify_remove_stamp(uuid), public.perkify_redeem_stamp_card(uuid) to authenticated;

commit;
