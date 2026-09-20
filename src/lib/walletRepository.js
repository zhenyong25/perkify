import { getSupabase } from './supabase'
import { validData } from '../data'

async function rpc(name, params = {}) {
  const client = getSupabase()
  const { data: { session }, error: sessionError } = await client.auth.getSession()
  if (sessionError) throw sessionError
  if (!session) throw new Error('Sign in before accessing your cloud wallet.')
  const { data, error } = await client.rpc(name, params)
  if (error) throw error
  return data
}

async function afterCommit() {
  try { return await rpc('perkify_get_wallet') }
  catch (error) { error.committed = true; throw error }
}

// A successful save followed by a failed reload must never be silently retried.
export const walletRepository = {
  getWallet: () => rpc('perkify_get_wallet'),
  saveProfile: settings => rpc('perkify_save_profile', { p_settings: settings, p_expected_version: settings.version }),
  async saveCard(card) {
    await rpc('perkify_save_card', { p_card: card, p_expected_version: card.version ?? null })
    return afterCommit()
  },
  async saveVoucher(voucher) {
    await rpc('perkify_save_voucher', { p_voucher: voucher, p_expected_version: voucher.version ?? null })
    return afterCommit()
  },
  async saveStampCard(card) {
    await rpc('perkify_save_stamp_card', { p_card: card, p_expected_version: card.version ?? null })
    return afterCommit()
  },
  addStamp: id => rpc('perkify_add_stamp', { p_card_id: id }),
  removeStamp: id => rpc('perkify_remove_stamp', { p_card_id: id }),
  redeemStampCard: id => rpc('perkify_redeem_stamp_card', { p_card_id: id }),
  claimMilestone: (id, stamps) => rpc('perkify_claim_milestone', { p_card_id: id, p_stamps: stamps }),
  // Generate requestId once for the user action; reuse it for network retries.
  updatePoints: ({ cardId, amount, kind, requestId, estimatedValue = null }) => rpc('perkify_update_points', {
    p_card_id: cardId, p_amount: amount, p_kind: kind, p_request_id: requestId, p_estimated_value: estimatedValue,
  }),
  redeemVoucher: id => rpc('perkify_redeem_voucher', { p_voucher_id: id }),
  deletePerk: (kind, item) => rpc('perkify_delete_perk', { p_kind: kind, p_id: item.id, p_expected_version: item.version }),
  clearWallet: () => rpc('perkify_clear_wallet'),
  replaceWallet(wallet) {
    if (!validData(wallet)) throw new Error('Invalid Perkify backup.')
    return rpc('perkify_replace_wallet', { p_wallet: wallet })
  },
}
