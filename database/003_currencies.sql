-- Run once, after 001_schema.sql and 002_functions.sql, in the Supabase SQL Editor.
-- Widens the display/activity currency from the original 5-currency MVP set to
-- the fuller list now offered in Settings. Existing rows are unaffected; only
-- new values are validated against the wider list.
begin;

alter table public.perkify_profiles drop constraint if exists perkify_profiles_currency_check;
alter table public.perkify_profiles add constraint perkify_profiles_currency_check
  check (currency in ('MYR','USD','SGD','EUR','GBP','AUD','CAD','NZD','CHF','JPY','CNY','HKD','TWD','KRW','INR','IDR','THB','PHP','VND','AED'));

alter table public.perkify_activity drop constraint if exists perkify_activity_currency_check;
alter table public.perkify_activity add constraint perkify_activity_currency_check
  check (currency in ('MYR','USD','SGD','EUR','GBP','AUD','CAD','NZD','CHF','JPY','CNY','HKD','TWD','KRW','INR','IDR','THB','PHP','VND','AED'));

commit;
