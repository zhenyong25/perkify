-- Run once, after 005_stamp_cards.sql, in the Supabase SQL Editor.
-- Replaces a stamp card's single `reward` with a `milestones` list (e.g.
-- 5 stamps -> free drink, 10 -> free pastry, 15 -> free meal), tracks which
-- thresholds have been claimed, and adds an optional expiry date. `target`
-- is now derived from the highest milestone rather than set directly.
begin;

alter table public.perkify_stamp_cards add column milestones jsonb not null default '[]'::jsonb
  check (jsonb_typeof(milestones) = 'array');
alter table public.perkify_stamp_cards add column claimed integer[] not null default '{}';
alter table public.perkify_stamp_cards add column expires_on date
  check (expires_on between date '0001-01-01' and date '9999-12-31');

update public.perkify_stamp_cards
  set milestones = jsonb_build_array(jsonb_build_object('stamps', target, 'reward', reward));
alter table public.perkify_stamp_cards drop column reward;

create index perkify_stamp_cards_owner_expiry on public.perkify_stamp_cards(user_id, expires_on) where expires_on is not null;

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
      'id', id, 'name', name, 'category', category, 'target', target, 'stamps', stamps, 'milestones', milestones,
      'claimed', to_jsonb(claimed), 'completions', completions, 'color', color, 'note', note,
      'expiry', coalesce(expires_on::text, ''), 'version', version) order by created_at desc, id)
      from public.perkify_stamp_cards where user_id = auth.uid()), '[]'::jsonb),
    'activity', coalesce((select jsonb_agg(jsonb_build_object(
      'id', id, 'name', name, 'detail', detail, 'amount', amount, 'unit', unit,
      'kind', kind, 'color', color, 'date', occurred_at, 'currency', currency)
      order by occurred_at desc, id)
      from (select * from public.perkify_activity where user_id = auth.uid()
        order by occurred_at desc, id limit 2000) a), '[]'::jsonb)
  );
$$;

-- Metadata only. `target` is derived as the highest milestone's stamp count.
-- Stamps are clamped to the (possibly lower) new target on edit; `claimed`
-- entries whose milestone no longer exists are dropped.
create or replace function public.perkify_save_stamp_card(p_card jsonb, p_expected_version bigint default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := public.perkify_lock_wallet(); v_id uuid; v_new boolean;
  v_milestones jsonb := '[]'::jsonb; v_item jsonb; v_stamps_seen integer[] := '{}';
  v_target integer; v_old public.perkify_stamp_cards; v_card public.perkify_stamp_cards; v_claimed integer[];
begin
  v_new := nullif(p_card->>'id', '') is null;
  if jsonb_typeof(p_card->'milestones') is distinct from 'array' or jsonb_array_length(p_card->'milestones') < 1
    or jsonb_array_length(p_card->'milestones') > 20 then
    raise exception 'Add between 1 and 20 rewards' using errcode = '22023';
  end if;
  for v_item in select value from jsonb_array_elements(p_card->'milestones')
    order by (case when (value->>'stamps') ~ '^\d+$' then (value->>'stamps')::integer else 999999 end) loop
    if jsonb_typeof(v_item) is distinct from 'object' or (v_item->>'stamps') !~ '^\d+$'
      or (v_item->>'stamps')::integer < 1 or (v_item->>'stamps')::integer > 100 then
      raise exception 'Each reward needs a whole stamp count between 1 and 100' using errcode = '22023';
    end if;
    if (v_item->>'stamps')::integer = any(v_stamps_seen) then
      raise exception 'Rewards must use different stamp counts' using errcode = '22023';
    end if;
    v_stamps_seen := v_stamps_seen || (v_item->>'stamps')::integer;
    v_milestones := v_milestones || jsonb_build_object('stamps', (v_item->>'stamps')::integer, 'reward', left(coalesce(v_item->>'reward', ''), 200));
  end loop;
  v_target := (select max(x) from unnest(v_stamps_seen) x);
  if v_new then
    insert into public.perkify_stamp_cards(user_id, name, category, target, stamps, milestones, completions, color, note, expires_on)
    values(v_user, btrim(p_card->>'name'), p_card->>'category', v_target,
      least(greatest(coalesce((p_card->>'stamps')::integer, 0), 0), v_target), v_milestones,
      greatest(coalesce((p_card->>'completions')::integer, 0), 0), p_card->>'color', coalesce(p_card->>'note', ''),
      nullif(p_card->>'expiry', '')::date)
    returning * into v_card;
    perform public.perkify_log(v_user, v_card.name, 'Stamp card added', 0, 'stamp', 'add', v_card.color);
  else
    v_id := (p_card->>'id')::uuid;
    select * into v_old from public.perkify_stamp_cards where id = v_id and user_id = v_user for update;
    if not found then raise exception 'Stamp card not found' using errcode = '22023'; end if;
    if p_expected_version is null or v_old.version <> p_expected_version then
      raise exception 'Stamp card changed. Reload before saving.' using errcode = '40001';
    end if;
    select coalesce(array_agg(c), '{}') into v_claimed from unnest(v_old.claimed) c where c = any(v_stamps_seen) and c <= v_target;
    update public.perkify_stamp_cards set name = btrim(p_card->>'name'), category = p_card->>'category',
      target = v_target, stamps = least(v_old.stamps, v_target), milestones = v_milestones, claimed = v_claimed,
      color = p_card->>'color', note = coalesce(p_card->>'note', ''), expires_on = nullif(p_card->>'expiry', '')::date
      where id = v_id returning * into v_card;
  end if;
  return v_card.id;
end;
$$;

-- Claims one milestone's reward. Progress keeps counting toward later
-- milestones unless this is the final one (stamps = target), which resets
-- stamps and claimed history and counts as a full completion.
create function public.perkify_claim_milestone(p_card_id uuid, p_stamps integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := public.perkify_lock_wallet(); v_card public.perkify_stamp_cards; v_reward text;
begin
  select * into v_card from public.perkify_stamp_cards where id = p_card_id and user_id = v_user for update;
  if not found then raise exception 'Stamp card not found' using errcode = '22023'; end if;
  select value->>'reward' into v_reward from jsonb_array_elements(v_card.milestones) where (value->>'stamps')::integer = p_stamps;
  if v_reward is null then raise exception 'No reward at that stamp count' using errcode = '22023'; end if;
  if v_card.stamps < p_stamps then raise exception 'Not enough stamps yet' using errcode = '22023'; end if;
  if p_stamps = any(v_card.claimed) then return public.perkify_get_wallet(); end if;
  if p_stamps = v_card.target then
    update public.perkify_stamp_cards set stamps = 0, claimed = '{}', completions = completions + 1 where id = p_card_id;
  else
    update public.perkify_stamp_cards set claimed = claimed || p_stamps where id = p_card_id;
  end if;
  perform public.perkify_log(v_user, v_card.name, 'Reward redeemed', p_stamps, 'stamp', 'redeem', v_card.color);
  return public.perkify_get_wallet();
end;
$$;

-- Thin alias kept for the "reached the final reward" confirmation flow.
create or replace function public.perkify_redeem_stamp_card(p_card_id uuid) returns jsonb
language sql security definer set search_path = '' as $$
  select public.perkify_claim_milestone(p_card_id, (select target from public.perkify_stamp_cards where id = p_card_id and user_id = auth.uid()));
$$;

revoke all on function public.perkify_claim_milestone(uuid,integer) from public, anon, authenticated;
grant execute on function public.perkify_claim_milestone(uuid,integer) to authenticated;

commit;
