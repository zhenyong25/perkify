-- Run after 001_schema.sql. All writes are atomic and authenticated.
begin;

-- Every mutation locks the owner's profile first. This serializes writes for
-- that wallet, including imports/clears, without blocking other users.
create function public.perkify_lock_wallet() returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Sign in to access your wallet' using errcode = '42501'; end if;
  perform 1 from public.perkify_profiles where user_id = v_user for update;
  if not found then raise exception 'Profile not found' using errcode = '42501'; end if;
  return v_user;
end;
$$;

create function public.perkify_log(p_user uuid, p_name text, p_detail text, p_amount numeric, p_unit text, p_kind text, p_color text)
returns void language sql security definer set search_path = '' as $$
  insert into public.perkify_activity(user_id, name, detail, amount, unit, kind, color, currency)
  select p_user, p_name, p_detail, p_amount, p_unit, p_kind, p_color, currency
  from public.perkify_profiles where user_id = p_user;
$$;

-- Returns the existing Vue wallet/backup shape, plus version fields for edits.
-- A single SQL statement gives the caller a consistent snapshot.
create function public.perkify_get_wallet() returns jsonb
language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object(
    'settings', (select jsonb_build_object('name', name, 'currency', currency, 'timezone', timezone, 'version', version)
      from public.perkify_profiles where user_id = auth.uid()),
    'cards', coalesce((select jsonb_agg(jsonb_build_object(
      'id', id, 'name', name, 'category', category, 'points', points, 'unit', unit,
      'value', estimated_value, 'expiry', coalesce(expires_on::text, ''), 'member', member_number,
      'color', color, 'note', note, 'version', version) order by created_at desc, id)
      from public.perkify_cards where user_id = auth.uid()), '[]'::jsonb),
    'vouchers', coalesce((select jsonb_agg(jsonb_build_object(
      'id', id, 'name', name, 'brand', brand, 'category', category, 'value', value, 'code', code,
      'expiry', coalesce(expires_on::text, ''), 'color', color, 'note', note,
      'redeemed', redeemed_at is not null, 'version', version) order by created_at desc, id)
      from public.perkify_vouchers where user_id = auth.uid()), '[]'::jsonb),
    'activity', coalesce((select jsonb_agg(jsonb_build_object(
      'id', id, 'name', name, 'detail', detail, 'amount', amount, 'unit', unit,
      'kind', kind, 'color', color, 'date', occurred_at, 'currency', currency)
      order by occurred_at desc, id)
      from (select * from public.perkify_activity where user_id = auth.uid()
        order by occurred_at desc, id limit 2000) a), '[]'::jsonb)
  );
$$;

create function public.perkify_save_profile(p_settings jsonb, p_expected_version bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := public.perkify_lock_wallet(); v_timezone text;
begin
  select coalesce(p_settings->>'timezone', timezone) into v_timezone from public.perkify_profiles where user_id = v_user;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = v_timezone) then
    raise exception 'Invalid IANA timezone' using errcode = '22023';
  end if;
  update public.perkify_profiles set name = p_settings->>'name', currency = p_settings->>'currency', timezone = v_timezone
  where user_id = v_user and version = p_expected_version;
  if not found then raise exception 'Profile changed. Reload before saving.' using errcode = '40001'; end if;
  return public.perkify_get_wallet();
end;
$$;

-- Omit id for a new card. Updates require the version returned by get_wallet.
create function public.perkify_save_card(p_card jsonb, p_expected_version bigint default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := public.perkify_lock_wallet(); v_id uuid;
  v_old public.perkify_cards; v_card public.perkify_cards; v_new boolean;
begin
  v_new := nullif(p_card->>'id', '') is null;
  if v_new then
    insert into public.perkify_cards(user_id, name, category, points, unit, estimated_value, expires_on, member_number, color, note)
    values(v_user, btrim(p_card->>'name'), p_card->>'category', (p_card->>'points')::numeric,
      coalesce(nullif(btrim(p_card->>'unit'), ''), 'Points'), (p_card->>'value')::numeric,
      nullif(p_card->>'expiry', '')::date, coalesce(p_card->>'member', ''), p_card->>'color', coalesce(p_card->>'note', ''))
    returning * into v_card;
  else
    v_id := (p_card->>'id')::uuid;
    select * into v_old from public.perkify_cards where id = v_id and user_id = v_user for update;
    if not found then raise exception 'Card not found' using errcode = '22023'; end if;
    if p_expected_version is null or v_old.version <> p_expected_version then
      raise exception 'Card changed. Reload before saving.' using errcode = '40001';
    end if;
    update public.perkify_cards set name = btrim(p_card->>'name'), category = p_card->>'category', points = (p_card->>'points')::numeric,
      unit = coalesce(nullif(btrim(p_card->>'unit'), ''), 'Points'), estimated_value = (p_card->>'value')::numeric,
      expires_on = nullif(p_card->>'expiry', '')::date, member_number = coalesce(p_card->>'member', ''),
      color = p_card->>'color', note = coalesce(p_card->>'note', '') where id = v_id returning * into v_card;
  end if;
  if v_new or v_card.points <> v_old.points or v_card.estimated_value <> v_old.estimated_value then
    insert into public.perkify_point_transactions(request_id, user_id, card_id, kind, points_delta, balance_after, estimated_value_after)
    values(gen_random_uuid(), v_user, v_card.id, case when v_new then 'opening' else 'adjust' end,
      v_card.points - coalesce(v_old.points, 0), v_card.points, v_card.estimated_value);
  end if;
  if v_new then
    perform public.perkify_log(v_user, v_card.name, 'Membership added', v_card.estimated_value, 'money', 'add', v_card.color);
  elsif v_card.points <> v_old.points then
    perform public.perkify_log(v_user, v_card.name, 'Balance adjusted', abs(v_card.points - v_old.points), v_card.unit,
      case when v_card.points > v_old.points then 'earn' else 'redeem' end, v_card.color);
  end if;
  return v_card.id;
end;
$$;

create function public.perkify_save_voucher(p_voucher jsonb, p_expected_version bigint default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := public.perkify_lock_wallet(); v_voucher public.perkify_vouchers; v_id uuid;
begin
  if nullif(p_voucher->>'id', '') is null then
    insert into public.perkify_vouchers(user_id, name, brand, category, value, code, expires_on, color, note)
    values(v_user, btrim(p_voucher->>'name'), btrim(p_voucher->>'brand'), p_voucher->>'category', (p_voucher->>'value')::numeric,
      coalesce(p_voucher->>'code', ''), nullif(p_voucher->>'expiry', '')::date, p_voucher->>'color', coalesce(p_voucher->>'note', ''))
    returning * into v_voucher;
    perform public.perkify_log(v_user, v_voucher.brand, 'Voucher added', v_voucher.value, 'money', 'add', v_voucher.color);
  else
    v_id := (p_voucher->>'id')::uuid;
    update public.perkify_vouchers set name = btrim(p_voucher->>'name'), brand = btrim(p_voucher->>'brand'),
      category = p_voucher->>'category', value = (p_voucher->>'value')::numeric, code = coalesce(p_voucher->>'code', ''),
      expires_on = nullif(p_voucher->>'expiry', '')::date, color = p_voucher->>'color', note = coalesce(p_voucher->>'note', '')
    where id = v_id and user_id = v_user and version = p_expected_version returning * into v_voucher;
    if not found then raise exception 'Voucher missing or changed. Reload before saving.' using errcode = '40001'; end if;
  end if;
  -- Redemption state cannot be changed through this metadata operation.
  return v_voucher.id;
end;
$$;

create function public.perkify_update_points(p_card_id uuid, p_amount numeric, p_kind text,
  p_request_id uuid, p_estimated_value numeric default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := public.perkify_lock_wallet(); v_card public.perkify_cards;
  v_prior public.perkify_point_transactions; v_delta numeric; v_balance numeric; v_value numeric; v_payload jsonb;
begin
  if p_amount is null or p_amount <= 0 or p_amount >= 1000000000000 or p_amount <> round(p_amount, 2)
    or p_kind is null or p_kind not in ('earn','redeem') or p_request_id is null then
    raise exception 'Use a positive amount with at most two decimal places, earn/redeem, and a request UUID' using errcode = '22023';
  end if;
  if p_estimated_value is not null and (p_estimated_value < 0 or p_estimated_value >= 1000000000000) then
    raise exception 'Invalid estimated value' using errcode = '22023';
  end if;
  v_payload := jsonb_build_object('card_id', p_card_id, 'amount', p_amount, 'kind', p_kind, 'estimated_value', p_estimated_value);
  select * into v_prior from public.perkify_point_transactions where request_id = p_request_id and user_id = v_user;
  if found then
    if v_prior.request_payload <> v_payload then raise exception 'Request UUID was already used for a different operation' using errcode = '22023'; end if;
    return public.perkify_get_wallet();
  end if;
  select * into v_card from public.perkify_cards where id = p_card_id and user_id = v_user for update;
  if not found then raise exception 'Card not found' using errcode = '22023'; end if;
  v_delta := case when p_kind = 'redeem' then -p_amount else p_amount end;
  v_balance := v_card.points + v_delta;
  if v_balance < 0 then raise exception 'Not enough points' using errcode = '22023'; end if;
  v_value := coalesce(p_estimated_value, case when v_card.points = 0 then 0 else round(v_balance * v_card.estimated_value / v_card.points, 2) end);
  update public.perkify_cards set points = v_balance, estimated_value = v_value where id = p_card_id;
  insert into public.perkify_point_transactions(request_id, user_id, card_id, kind, points_delta, balance_after, estimated_value_after, request_payload)
  values(p_request_id, v_user, p_card_id, p_kind, v_delta, v_balance, v_value, v_payload);
  perform public.perkify_log(v_user, v_card.name, case when p_kind = 'earn' then 'Points earned' else 'Points redeemed' end,
    p_amount, v_card.unit, p_kind, v_card.color);
  return public.perkify_get_wallet();
end;
$$;

create function public.perkify_redeem_voucher(p_voucher_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := public.perkify_lock_wallet(); v_voucher public.perkify_vouchers; v_today date;
begin
  select * into v_voucher from public.perkify_vouchers where id = p_voucher_id and user_id = v_user for update;
  if not found then raise exception 'Voucher not found' using errcode = '22023'; end if;
  -- Repeated taps/retries have no further effect.
  if v_voucher.redeemed_at is not null then return public.perkify_get_wallet(); end if;
  select (now() at time zone timezone)::date into v_today from public.perkify_profiles where user_id = v_user;
  if v_voucher.expires_on < v_today then raise exception 'This voucher has expired' using errcode = '22023'; end if;
  update public.perkify_vouchers set redeemed_at = now() where id = p_voucher_id;
  perform public.perkify_log(v_user, v_voucher.brand, 'Voucher redeemed', v_voucher.value, 'money', 'redeem', v_voucher.color);
  return public.perkify_get_wallet();
end;
$$;

create function public.perkify_delete_perk(p_kind text, p_id uuid, p_expected_version bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := public.perkify_lock_wallet();
begin
  if p_kind = 'card' then
    delete from public.perkify_cards where id = p_id and user_id = v_user and version = p_expected_version;
  elsif p_kind = 'voucher' then
    delete from public.perkify_vouchers where id = p_id and user_id = v_user and version = p_expected_version;
  else raise exception 'Invalid perk type' using errcode = '22023';
  end if;
  if not found then raise exception 'Perk missing or changed. Reload before removing.' using errcode = '40001'; end if;
  return public.perkify_get_wallet();
end;
$$;

create function public.perkify_clear_wallet() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := public.perkify_lock_wallet();
begin
  delete from public.perkify_point_transactions where user_id = v_user;
  delete from public.perkify_activity where user_id = v_user;
  delete from public.perkify_cards where user_id = v_user;
  delete from public.perkify_vouchers where user_id = v_user;
  return public.perkify_get_wallet();
end;
$$;

-- Explicit replace operation, intended for the existing backup-restore flow.
-- All imported IDs are regenerated, including MVP sample IDs such as c1/v1.
-- Any invalid row rolls back the entire replacement, preserving the old wallet.
create function public.perkify_replace_wallet(p_wallet jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := public.perkify_lock_wallet(); v_item jsonb; v_id uuid; v_version bigint; v_currency text;
begin
  if jsonb_typeof(p_wallet) is distinct from 'object'
    or jsonb_typeof(p_wallet->'settings') is distinct from 'object'
    or jsonb_typeof(p_wallet->'cards') is distinct from 'array'
    or jsonb_typeof(p_wallet->'vouchers') is distinct from 'array'
    or jsonb_typeof(p_wallet->'activity') is distinct from 'array' then
    raise exception 'Invalid Perkify backup shape' using errcode = '22023';
  end if;
  if jsonb_array_length(p_wallet->'cards') > 1000 or jsonb_array_length(p_wallet->'vouchers') > 1000
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

-- Views obey the caller's RLS (PostgreSQL 15+).
create view public.perkify_expiring_perks with (security_invoker = true) as
select c.user_id, c.id, 'card'::text as type, c.name, c.points as amount, c.unit,
  c.expires_on, c.expires_on - (now() at time zone p.timezone)::date as days_remaining
from public.perkify_cards c join public.perkify_profiles p using(user_id)
where c.expires_on between (now() at time zone p.timezone)::date and (now() at time zone p.timezone)::date + 30
union all
select v.user_id, v.id, 'voucher', v.brand, v.value, 'money',
  v.expires_on, v.expires_on - (now() at time zone p.timezone)::date
from public.perkify_vouchers v join public.perkify_profiles p using(user_id)
where v.redeemed_at is null and v.expires_on between (now() at time zone p.timezone)::date and (now() at time zone p.timezone)::date + 30;

create view public.perkify_dashboard with (security_invoker = true) as
select p.user_id, p.currency,
  coalesce(c.estimated_points_value, 0) as estimated_points_value,
  coalesce(v.available_voucher_value, 0) as available_voucher_value,
  coalesce(c.estimated_points_value, 0) + coalesce(v.available_voucher_value, 0) as total_perk_value,
  c.active_programs, v.available_vouchers,
  (select count(*) from public.perkify_expiring_perks e where e.user_id = p.user_id) as expiring_perks
from public.perkify_profiles p
left join lateral (select sum(estimated_value) as estimated_points_value, count(*) as active_programs
  from public.perkify_cards where user_id = p.user_id and (expires_on is null or expires_on >= (now() at time zone p.timezone)::date)) c on true
left join lateral (select sum(value) as available_voucher_value, count(*) as available_vouchers
  from public.perkify_vouchers where user_id = p.user_id and redeemed_at is null
    and (expires_on is null or expires_on >= (now() at time zone p.timezone)::date)) v on true;

revoke all on public.perkify_expiring_perks, public.perkify_dashboard from public, anon, authenticated;
grant select on public.perkify_expiring_perks, public.perkify_dashboard to authenticated;

-- PostgreSQL grants function EXECUTE to PUBLIC by default: revoke it explicitly.
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as signature from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in (
      'perkify_lock_wallet','perkify_log','perkify_get_wallet','perkify_save_profile',
      'perkify_save_card','perkify_save_voucher','perkify_update_points','perkify_redeem_voucher',
      'perkify_delete_perk','perkify_clear_wallet','perkify_replace_wallet')
  loop execute format('revoke all on function %s from public, anon, authenticated', f.signature); end loop;
end;
$$;
grant execute on function public.perkify_get_wallet(), public.perkify_save_profile(jsonb,bigint),
  public.perkify_save_card(jsonb,bigint), public.perkify_save_voucher(jsonb,bigint),
  public.perkify_update_points(uuid,numeric,text,uuid,numeric), public.perkify_redeem_voucher(uuid),
  public.perkify_delete_perk(text,uuid,bigint), public.perkify_clear_wallet(), public.perkify_replace_wallet(jsonb)
to authenticated;

commit;
