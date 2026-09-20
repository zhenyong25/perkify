import { PGlite } from '@electric-sql/pglite'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { seedData, dateIn, validData } from '../src/data.js'

const db = new PGlite()
const userA = '11111111-1111-4111-8111-111111111111'
const userB = '22222222-2222-4222-8222-222222222222'
const request = '33333333-3333-4333-8333-333333333333'
const call = async (name, args = []) => (await db.query(`select public.${name}(${args.map((_, i) => '$' + (i + 1)).join(',')}) as result`, args)).rows[0].result
const count = async table => Number((await db.query(`select count(*) as total from public.${table}`)).rows[0].total)
async function asUser(id) {
  await db.exec('reset role; set role authenticated;')
  await db.query("select set_config('request.jwt.claim.sub', $1, false)", [id])
}
async function rejects(action, pattern) { await assert.rejects(action, pattern) }
try {
  // Supabase-owned auth infrastructure is simulated only in this isolated DB.
  await db.exec(`
    create role anon nologin;
    create role authenticated nologin;
    create schema auth;
    create table auth.users(id uuid primary key, raw_user_meta_data jsonb default '{}');
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    grant usage on schema auth, public to authenticated, anon;
    grant execute on function auth.uid() to authenticated, anon;
    insert into auth.users(id, raw_user_meta_data) values ('${userA}', '{"name":"Alice"}');
  `)
  for (const file of ['001_schema.sql', '002_functions.sql', '003_currencies.sql', '004_item_currency.sql', '005_stamp_cards.sql', '006_progressive_stamps.sql']) {
    await db.exec(await readFile(new URL(`../database/${file}`, import.meta.url), 'utf8'))
  }
  await db.query('insert into auth.users(id, raw_user_meta_data) values ($1, $2)', [userB, { name: 'Bob' }])
  await asUser(userA)
  let wallet = await call('perkify_get_wallet')
  assert.equal(wallet.settings.name, 'Alice')
  assert.equal(wallet.cards.length, 0)
  assert.ok(validData(wallet))
  const fixture = { ...seedData().cards[0], points: 100, value: 20 }
  delete fixture.id
  const cardId = await call('perkify_save_card', [fixture, null])
  wallet = await call('perkify_update_points', [cardId, 50, 'earn', request, null])
  assert.equal(wallet.cards[0].points, 150)
  assert.equal(wallet.cards[0].value, 30)
  const txCount = await count('perkify_point_transactions')
  const activityCount = await count('perkify_activity')
  const retried = await call('perkify_update_points', [cardId, 50, 'earn', request, null])
  assert.equal(retried.cards[0].points, 150)
  assert.equal(await count('perkify_point_transactions'), txCount)
  assert.equal(await count('perkify_activity'), activityCount)
  await rejects(() => call('perkify_update_points', [cardId, 51, 'earn', request, null]), /different operation/)
  await rejects(() => call('perkify_update_points', [cardId, 151, 'redeem', crypto.randomUUID(), null]), /Not enough points/)
  await rejects(() => call('perkify_update_points', [cardId, -1, 'earn', crypto.randomUUID(), null]), /positive amount/)
  await rejects(() => call('perkify_update_points', [cardId, 'NaN', 'earn', crypto.randomUUID(), null]), /positive amount/)
  wallet = await call('perkify_update_points', [cardId, 25, 'redeem', crypto.randomUUID(), null])
  assert.equal(wallet.cards[0].points, 125)
  assert.equal(wallet.cards[0].value, 25)
  assert.equal(await count('perkify_activity'), activityCount + 1)
  const old = wallet.cards[0]
  await call('perkify_save_card', [{ ...old, name: 'Updated card' }, old.version])
  await rejects(() => call('perkify_save_card', [{ ...old, name: 'Stale edit' }, old.version]), /Card changed/)
  await rejects(() => db.query('update public.perkify_cards set points = 999 where id = $1', [cardId]), /permission denied/)
  await rejects(() => call('perkify_log', [userA, 'Fake', 'Fake', 1, 'Points', 'earn', 'green']), /permission denied/)
  await rejects(() => call('perkify_save_profile', [{ name: 'Alice', currency: 'MYR', timezone: 'Not/AZone' }, 1]), /Invalid IANA timezone/)

  const voucher = { ...seedData().vouchers[0], expiry: dateIn(0) }
  delete voucher.id
  const voucherId = await call('perkify_save_voucher', [voucher, null])
  wallet = await call('perkify_redeem_voucher', [voucherId])
  assert.equal(wallet.vouchers[0].redeemed, true)
  const afterRedeem = await count('perkify_activity')
  await call('perkify_redeem_voucher', [voucherId])
  assert.equal(await count('perkify_activity'), afterRedeem)
  const expiredId = await call('perkify_save_voucher', [{ ...voucher, expiry: dateIn(-1) }, null])
  await rejects(() => call('perkify_redeem_voucher', [expiredId]), /has expired/)
  const dashboard = (await db.query('select * from public.perkify_dashboard')).rows[0]
  assert.equal(Number(dashboard.available_vouchers), 0)
  assert.equal(Number(dashboard.total_perk_value), 25)

  // Stamp cards: metadata edits, tap-to-stamp/untap, and progressive milestones.
  const stampFixture = { ...seedData().stampCards[0], stamps: 0, claimed: [], completions: 0 }
  delete stampFixture.id
  const stampCardId = await call('perkify_save_stamp_card', [stampFixture, null])
  wallet = await call('perkify_add_stamp', [stampCardId])
  assert.equal(wallet.stampCards[0].stamps, 1)
  assert.equal(wallet.stampCards[0].target, 15)
  wallet = await call('perkify_remove_stamp', [stampCardId])
  assert.equal(wallet.stampCards[0].stamps, 0)
  await call('perkify_remove_stamp', [stampCardId]) // idempotent at zero
  for (let i = 0; i < 5; i++) wallet = await call('perkify_add_stamp', [stampCardId])
  assert.equal(wallet.stampCards[0].stamps, 5)
  await rejects(() => call('perkify_claim_milestone', [stampCardId, 10]), /Not enough stamps/)
  await rejects(() => call('perkify_claim_milestone', [stampCardId, 7]), /No reward/)
  wallet = await call('perkify_claim_milestone', [stampCardId, 5])
  assert.deepEqual(wallet.stampCards[0].claimed, [5])
  assert.equal(wallet.stampCards[0].stamps, 5) // an intermediate claim never resets progress
  wallet = await call('perkify_claim_milestone', [stampCardId, 5]) // idempotent: already claimed
  assert.deepEqual(wallet.stampCards[0].claimed, [5])
  for (let i = 0; i < 5; i++) wallet = await call('perkify_add_stamp', [stampCardId])
  wallet = await call('perkify_claim_milestone', [stampCardId, 10])
  assert.deepEqual(wallet.stampCards[0].claimed, [5, 10])
  for (let i = 0; i < 5; i++) wallet = await call('perkify_add_stamp', [stampCardId])
  assert.equal(wallet.stampCards[0].stamps, 15)
  await rejects(() => call('perkify_add_stamp', [stampCardId]), /card is full/)
  wallet = await call('perkify_redeem_stamp_card', [stampCardId]) // alias for claiming the final milestone
  assert.equal(wallet.stampCards[0].stamps, 0)
  assert.deepEqual(wallet.stampCards[0].claimed, [])
  assert.equal(wallet.stampCards[0].completions, 1)
  await rejects(() => call('perkify_redeem_stamp_card', [stampCardId]), /Not enough stamps/)
  const stampOld = wallet.stampCards[0]
  await rejects(() => call('perkify_save_stamp_card', [{ ...stampOld, milestones: [] }, stampOld.version]), /Add between 1 and 20/)
  await rejects(() => call('perkify_save_stamp_card', [{ ...stampOld, milestones: [{ stamps: 5, reward: 'a' }, { stamps: 5, reward: 'b' }] }, stampOld.version]), /different stamp counts/)
  await rejects(() => call('perkify_save_stamp_card', [{ ...stampOld, milestones: [{ stamps: 200, reward: 'a' }] }, stampOld.version]), /between 1 and 100/)
  const renamed = await call('perkify_save_stamp_card', [{ ...stampOld, name: 'Renamed loyalty card', milestones: [{ stamps: 5, reward: 'Free drink' }] }, stampOld.version])
  assert.equal(renamed, stampCardId)
  await rejects(() => call('perkify_save_stamp_card', [{ ...stampOld, name: 'Stale edit' }, stampOld.version]), /Stamp card changed/)

  // A second signed-in user cannot read or mutate Alice's rows or views.
  await asUser(userB)
  assert.equal((await call('perkify_get_wallet')).settings.name, 'Bob')
  assert.equal(await count('perkify_cards'), 0)
  assert.equal(await count('perkify_activity'), 0)
  assert.equal(await count('perkify_point_transactions'), 0)
  assert.equal(await count('perkify_expiring_perks'), 0)
  assert.equal((await db.query('select * from public.perkify_dashboard')).rows[0].user_id, userB)
  await rejects(() => call('perkify_update_points', [cardId, 10, 'earn', crypto.randomUUID(), null]), /Card not found/)
  await rejects(() => call('perkify_redeem_voucher', [voucherId]), /Voucher not found/)
  await rejects(() => call('perkify_save_card', [{ ...old, name: 'Stolen card' }, old.version]), /Card not found/)
  await rejects(() => call('perkify_delete_perk', ['card', cardId, old.version]), /missing or changed/)
  await call('perkify_clear_wallet')
  await asUser(userA)
  assert.equal(await count('perkify_cards'), 1)

  // Imports regenerate local IDs and roll back completely on an invalid row.
  wallet = await call('perkify_replace_wallet', [seedData()])
  assert.ok(validData(wallet))
  assert.equal(wallet.cards.length, 4)
  assert.equal(wallet.vouchers.length, 3)
  assert.equal(wallet.activity.length, 3)
  assert.notEqual(wallet.cards[0].id, 'c1')
  const snapshot = JSON.stringify(wallet)
  const bad = seedData()
  bad.cards[2].points = -10
  await rejects(() => call('perkify_replace_wallet', [bad]), /check constraint/)
  assert.equal(JSON.stringify(await call('perkify_get_wallet')), snapshot)
  await rejects(() => call('perkify_replace_wallet', [{}]), /Invalid Perkify backup/)
  const remove = wallet.cards[0]
  const historyCount = await count('perkify_activity')
  await call('perkify_delete_perk', ['card', remove.id, remove.version])
  assert.equal(await count('perkify_cards'), 3)
  assert.equal(await count('perkify_activity'), historyCount)
  assert.equal(Number((await db.query('select count(*) as n from public.perkify_point_transactions where card_id is null')).rows[0].n), 1)
  await call('perkify_clear_wallet')
  assert.equal(await count('perkify_cards'), 0)
  assert.equal(await count('perkify_vouchers'), 0)
  assert.equal(await count('perkify_activity'), 0)
  assert.equal(await count('perkify_point_transactions'), 0)
  assert.equal((await call('perkify_get_wallet')).settings.name, 'Alex')

  await db.exec('reset role; set role anon;')
  await db.query("select set_config('request.jwt.claim.sub', '', false)")
  await rejects(() => call('perkify_get_wallet'), /permission denied/)
  await rejects(() => call('perkify_clear_wallet'), /permission denied/)
  await rejects(() => db.query('select * from public.perkify_cards'), /permission denied/)
  // Account deletion cascades through all private wallet rows.
  await db.exec('reset role;')
  await db.query('delete from auth.users where id = $1', [userA])
  assert.equal(Number((await db.query('select count(*) as n from public.perkify_profiles where user_id = $1', [userA])).rows[0].n), 0)
  console.log('PASS: both SQL migrations execute; RLS, grants, profile provisioning, atomic writes, overdrafts, retry idempotency, optimistic concurrency, expiry, views, rollback on invalid restore, clear, and account deletion.')
} finally { await db.close() }
