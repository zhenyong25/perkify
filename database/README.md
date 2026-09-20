# Perkify database setup

Target: **Supabase / PostgreSQL 15+**. No hosted database was provided or modified. The current UI still uses local browser storage. These migrations and the client repository prepare the database layer; adding environment variables alone does **not** enable sign-in or synchronization.

## Apply the SQL

1. Create a Supabase project, or open the project you want Perkify to use.
2. In its SQL Editor, run **`001_schema.sql`**, then **`002_functions.sql`**, then **`003_currencies.sql`**, then **`004_item_currency.sql`**, then **`005_stamp_cards.sql`**, then **`006_progressive_stamps.sql`**. Run each once, in order. Each file is transactional; a failure rolls back that file. These are initial migrations, not repeatable reset scripts. If you already ran earlier files on an existing project before a later one existed, just run the missing file(s) on their own, in order.
3. Enable your chosen sign-in provider in Supabase Authentication. Profiles are created for existing users and for new sign-ups.
4. Copy the root `.env.example` to `.env.local`. Set the project URL and **publishable key** (a legacy `anon` key also works). Restart Vite after changing environment variables.
5. Use `src/lib/supabase.js` for authentication and `src/lib/walletRepository.js` for cloud operations when wiring the UI to the backend.

Never place a database connection string, password, `service_role` key, or secret key in `VITE_*` variables. Vite exposes those variables to browsers. The publishable key is intentionally public; user sessions and database authorization protect wallet data.

## What is included

| Object | Purpose |
| --- | --- |
| `perkify_profiles` | Name, display currency, IANA timezone, and profile version; linked to Supabase Auth |
| `perkify_cards` | Reward programs, separate point balances, estimated cash values with their own currency, member IDs, expiry, category, color, notes |
| `perkify_vouchers` | Voucher title, merchant, value with its own currency, code, expiry, category, color, notes, and redemption timestamp |
| `perkify_stamp_cards` | Loyalty stamp cards: name, category, expiry, current progress, a list of stamp-count milestones each with its own reward text, which have been claimed, completion count, color, notes |
| `perkify_activity` | Historical name/value snapshots; preserved when a perk is deleted |
| `perkify_point_transactions` | Opening balances, manual adjustments, earnings, and redemptions with retry identifiers |
| `perkify_expiring_perks` | Unredeemed perks expiring in the next 30 days, using the profile timezone |
| `perkify_dashboard` | Estimated totals, active programs, available vouchers, and expiry count |

All tables have row-level security. Signed-in users can read only their own rows; anonymous clients have no access. Views use `security_invoker` so they obey the same rules. Direct client writes are disabled; the authenticated functions below enforce ownership, validation, locking, and history together. Deleting an Auth user cascades through that user's wallet.

## Client API

| Repository method | SQL function | Result |
| --- | --- | --- |
| `getWallet()` | `perkify_get_wallet()` | Existing Vue wallet shape with version fields |
| `saveProfile(settings)` | `perkify_save_profile(jsonb, bigint)` | Wallet |
| `saveCard(card)` | `perkify_save_card(jsonb, bigint)` | Repository fetches the updated wallet after saving |
| `saveVoucher(voucher)` | `perkify_save_voucher(jsonb, bigint)` | Repository fetches the updated wallet after saving |
| `saveStampCard(card)` | `perkify_save_stamp_card(jsonb, bigint)` | Repository fetches the updated wallet after saving; metadata only, not progress. `target` is derived from the highest milestone |
| `addStamp(id)` | `perkify_add_stamp(uuid)` | Wallet; rejects once the card is full |
| `removeStamp(id)` | `perkify_remove_stamp(uuid)` | Wallet; idempotent at zero stamps |
| `claimMilestone(id, stamps)` | `perkify_claim_milestone(uuid, integer)` | Wallet; claims one milestone's reward. Claiming the final one (`stamps = target`) resets stamps and claimed history and increments `completions`; earlier ones just mark themselves claimed and progress keeps counting |
| `redeemStampCard(id)` | `perkify_redeem_stamp_card(uuid)` | Wallet; thin alias for `claimMilestone(id, target)`, kept for the "reached the final reward" confirmation flow |
| `updatePoints(options)` | `perkify_update_points(uuid, numeric, text, uuid, numeric)` | Wallet |
| `redeemVoucher(id)` | `perkify_redeem_voucher(uuid)` | Wallet |
| `deletePerk(kind, item)` | `perkify_delete_perk(text, uuid, bigint)` | Wallet |
| `clearWallet()` | `perkify_clear_wallet()` | Empty wallet; profile retained |
| `replaceWallet(backup)` | `perkify_replace_wallet(jsonb)` | Atomically restored wallet |

For new cards/vouchers, omit `id`. For edits and deletions, pass the original `version` returned by `getWallet()`. The database rejects stale edits with SQLSTATE `40001`: fetch again and let the user resolve their edit rather than automatically overwriting newer values. Keep row versions in application state when integrating cloud storage.

```js
import { getSupabase } from './src/lib/supabase'
import { walletRepository } from './src/lib/walletRepository'

const supabase = getSupabase()
const { error } = await supabase.auth.signInWithPassword({
  email: 'your-account@example.com',
  password: userEnteredPassword,
})
if (error) throw error

const wallet = await walletRepository.getWallet()
const requestId = crypto.randomUUID() // Once per action; reuse on retries.
const updated = await walletRepository.updatePoints({
  cardId: wallet.cards[0].id,
  amount: 50,
  kind: 'earn', // or 'redeem'
  requestId,
  estimatedValue: null, // Keep the previous estimated value per point.
})
```

This example belongs in application code with a real sign-in form, not in the browser console with a hard-coded password. The UI authentication, account switching, and sync policy remain the next integration step. Scope any cached cloud wallet to its user ID and clear its visible state on sign-out; do not reuse a previous user's local cache for another account.

## Importing the existing MVP wallet

Export a backup from Settings. After authentication and an explicit replacement confirmation, call `walletRepository.replaceWallet(backup)`. It replaces **only the current user's** cloud wallet in one transaction. Any invalid card, voucher, activity entry, or settings value rolls back the replacement. Local IDs such as `c1` are regenerated as database UUIDs; use the returned wallet afterward. Do not pass demo IDs directly to edit functions.

No data is uploaded automatically. To preserve an existing cloud wallet, export it before replacing it. For imported redeemed vouchers the timestamp records import time, since the original MVP backup does not contain a redemption timestamp. Imported point balances create opening ledger entries; old activity is retained as historical snapshots, not fabricated point transactions.

## Behavior and limits

- Amounts use PostgreSQL decimal arithmetic, two decimal places, and must be below one trillion. Each program retains its own point unit.
- Cash values are manual estimates. Each card and voucher has its own currency (defaulting to your profile's display currency when added, but changeable per item). Changing a currency changes its label, not the amount; no conversion is applied anywhere, including in dashboard totals, which sum raw amounts across whatever currencies your perks use. History stores the currency each amount was logged in.
- Voucher redemption is atomic and idempotent. An expired voucher cannot be redeemed. A voucher remains usable through its expiry date in the user's timezone (default `Asia/Kuala_Lumpur`).
- Point updates require a request UUID. Retries with the same UUID/payload do nothing twice; reusing an ID with different arguments is rejected. Redemptions cannot overdraw the point balance.
- All wallet mutations lock the profile before changing rows. This also prevents an import/clear from racing another mutation for the same user. Edits additionally check versions.
- Clearing a wallet removes its ledger and activity as well as its perks. Deleting a single card preserves history and sets its ledger `card_id` to null.
- `getWallet()` returns the latest 2,000 activity entries; the database retains older history. Restore accepts up to 1,000 cards, 1,000 vouchers, 2,000 activity entries, and a 5 MB JSON payload.
- A card has one expiry date for its whole balance, matching this MVP. Separate point-expiry batches, push subscriptions, merchant integrations, and live reward conversion rates are not modeled yet.
- Stamp cards have no currency. Progress only changes through `addStamp`/`removeStamp`/`claimMilestone`, each locking the row first so rapid taps stay race-free. A card can carry multiple reward milestones (e.g. 5 stamps -> free drink, 10 -> free pastry, 15 -> free meal); claiming a non-final milestone just marks it claimed while stamps keep counting, and claiming the final one (`stamps = target`) resets `stamps` and `claimed` and increments `completions`. An optional expiry date is supported like cards and vouchers.

## Verify locally

```sh
npm run test:db
```

This executes all migrations using embedded PostgreSQL (PGlite), with an isolated stand-in for Supabase's Auth schema and roles. It tests grants, per-user isolation, profile provisioning, CRUD, balance arithmetic, retry handling, stale versions, expiry, stamp card progress/redemption, views, invalid-import rollback, history retention, and deletion. It does not connect to a live project or test a hosted Supabase Auth/PostgREST deployment.

Implementation references: [Supabase row-level security](https://supabase.com/docs/guides/database/postgres/row-level-security), [database functions and execution privileges](https://supabase.com/docs/guides/database/functions), [PostgreSQL security-invoker views](https://www.postgresql.org/docs/current/sql-createview.html).
