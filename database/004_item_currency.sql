-- Run once, after 003_currencies.sql, in the Supabase SQL Editor.
-- Lets each card and voucher carry its own currency (useful when a perk was
-- earned in a different country than your display currency), instead of
-- always following the profile's display currency.
begin;

alter table public.perkify_cards add column currency text;
alter table public.perkify_vouchers add column currency text;

update public.perkify_cards c set currency = p.currency
  from public.perkify_profiles p where p.user_id = c.user_id and c.currency is null;
update public.perkify_vouchers v set currency = p.currency
  from public.perkify_profiles p where p.user_id = v.user_id and v.currency is null;

alter table public.perkify_cards alter column currency set default 'MYR';
alter table public.perkify_cards alter column currency set not null;
alter table public.perkify_cards add constraint perkify_cards_currency_check
  check (currency in ('MYR','USD','SGD','EUR','GBP','AUD','CAD','NZD','CHF','JPY','CNY','HKD','TWD','KRW','INR','IDR','THB','PHP','VND','AED'));

alter table public.perkify_vouchers alter column currency set default 'MYR';
alter table public.perkify_vouchers alter column currency set not null;
alter table public.perkify_vouchers add constraint perkify_vouchers_currency_check
  check (currency in ('MYR','USD','SGD','EUR','GBP','AUD','CAD','NZD','CHF','JPY','CNY','HKD','TWD','KRW','INR','IDR','THB','PHP','VND','AED'));

-- perkify_log gains a signature (a new trailing parameter), so it must be
-- dropped and recreated rather than replaced in place. It now records the
-- currency of the value being logged instead of always assuming the
-- profile's display currency.
drop function if exists public.perkify_log(uuid, text, text, numeric, text, text, text);
create function public.perkify_log(p_user uuid, p_name text, p_detail text, p_amount numeric, p_unit text, p_kind text, p_color text, p_currency text default null)
returns void language sql security definer set search_path = '' as $$
  insert into public.perkify_activity(user_id, name, detail, amount, unit, kind, color, currency)
  select p_user, p_name, p_detail, p_amount, p_unit, p_kind, p_color, coalesce(p_currency, currency)
  from public.perkify_profiles where user_id = p_user;
$$;
revoke all on function public.perkify_log(uuid, text, text, numeric, text, text, text, text) from public, anon, authenticated;

-- Returns each card/voucher's own currency alongside its value.
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
    'activity', coalesce((select jsonb_agg(jsonb_build_object(
      'id', id, 'name', name, 'detail', detail, 'amount', amount, 'unit', unit,
      'kind', kind, 'color', color, 'date', occurred_at, 'currency', currency)
      order by occurred_at desc, id)
      from (select * from public.perkify_activity where user_id = auth.uid()
        order by occurred_at desc, id limit 2000) a), '[]'::jsonb)
  );
$$;

-- Accepts an optional 'currency' key in the card payload; falls back to the
-- profile's current display currency when omitted (e.g. older backups).
create or replace function public.perkify_save_card(p_card jsonb, p_expected_version bigint default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := public.perkify_lock_wallet(); v_id uuid; v_currency text;
  v_old public.perkify_cards; v_card public.perkify_cards; v_new boolean;
begin
  v_new := nullif(p_card->>'id', '') is null;
  v_currency := coalesce(nullif(p_card->>'currency', ''), (select currency from public.perkify_profiles where user_id = v_user));
  if v_new then
    insert into public.perkify_cards(user_id, name, category, points, unit, estimated_value, expires_on, member_number, color, note, currency)
    values(v_user, btrim(p_card->>'name'), p_card->>'category', (p_card->>'points')::numeric,
      coalesce(nullif(btrim(p_card->>'unit'), ''), 'Points'), (p_card->>'value')::numeric,
      nullif(p_card->>'expiry', '')::date, coalesce(p_card->>'member', ''), p_card->>'color', coalesce(p_card->>'note', ''), v_currency)
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
      color = p_card->>'color', note = coalesce(p_card->>'note', ''), currency = v_currency where id = v_id returning * into v_card;
  end if;
  if v_new or v_card.points <> v_old.points or v_card.estimated_value <> v_old.estimated_value then
    insert into public.perkify_point_transactions(request_id, user_id, card_id, kind, points_delta, balance_after, estimated_value_after)
    values(gen_random_uuid(), v_user, v_card.id, case when v_new then 'opening' else 'adjust' end,
      v_card.points - coalesce(v_old.points, 0), v_card.points, v_card.estimated_value);
  end if;
  if v_new then
    perform public.perkify_log(v_user, v_card.name, 'Membership added', v_card.estimated_value, 'money', 'add', v_card.color, v_card.currency);
  elsif v_card.points <> v_old.points then
    perform public.perkify_log(v_user, v_card.name, 'Balance adjusted', abs(v_card.points - v_old.points), v_card.unit,
      case when v_card.points > v_old.points then 'earn' else 'redeem' end, v_card.color, v_card.currency);
  end if;
  return v_card.id;
end;
$$;

create or replace function public.perkify_save_voucher(p_voucher jsonb, p_expected_version bigint default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := public.perkify_lock_wallet(); v_voucher public.perkify_vouchers; v_id uuid; v_currency text;
begin
  v_currency := coalesce(nullif(p_voucher->>'currency', ''), (select currency from public.perkify_profiles where user_id = v_user));
  if nullif(p_voucher->>'id', '') is null then
    insert into public.perkify_vouchers(user_id, name, brand, category, value, code, expires_on, color, note, currency)
    values(v_user, btrim(p_voucher->>'name'), btrim(p_voucher->>'brand'), p_voucher->>'category', (p_voucher->>'value')::numeric,
      coalesce(p_voucher->>'code', ''), nullif(p_voucher->>'expiry', '')::date, p_voucher->>'color', coalesce(p_voucher->>'note', ''), v_currency)
    returning * into v_voucher;
    perform public.perkify_log(v_user, v_voucher.brand, 'Voucher added', v_voucher.value, 'money', 'add', v_voucher.color, v_voucher.currency);
  else
    v_id := (p_voucher->>'id')::uuid;
    update public.perkify_vouchers set name = btrim(p_voucher->>'name'), brand = btrim(p_voucher->>'brand'),
      category = p_voucher->>'category', value = (p_voucher->>'value')::numeric, code = coalesce(p_voucher->>'code', ''),
      expires_on = nullif(p_voucher->>'expiry', '')::date, color = p_voucher->>'color', note = coalesce(p_voucher->>'note', ''), currency = v_currency
    where id = v_id and user_id = v_user and version = p_expected_version returning * into v_voucher;
    if not found then raise exception 'Voucher missing or changed. Reload before saving.' using errcode = '40001'; end if;
  end if;
  -- Redemption state cannot be changed through this metadata operation.
  return v_voucher.id;
end;
$$;

create or replace function public.perkify_update_points(p_card_id uuid, p_amount numeric, p_kind text,
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
    p_amount, v_card.unit, p_kind, v_card.color, v_card.currency);
  return public.perkify_get_wallet();
end;
$$;

create or replace function public.perkify_redeem_voucher(p_voucher_id uuid) returns jsonb
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
  perform public.perkify_log(v_user, v_voucher.brand, 'Voucher redeemed', v_voucher.value, 'money', 'redeem', v_voucher.color, v_voucher.currency);
  return public.perkify_get_wallet();
end;
$$;

commit;
