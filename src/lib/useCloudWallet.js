import { computed, onMounted, onUnmounted, ref } from 'vue'
import { getSupabase, isSupabaseConfigured } from './supabase'
import { walletRepository } from './walletRepository'
import { validData } from '../data'

export const emptyWallet = () => ({ settings: { name: '', currency: 'MYR' }, cards: [], vouchers: [], stampCards: [], activity: [] })
export function cloudError(error) {
  if (error?.code === '40001') return 'This perk changed on another device. Refresh your wallet and reopen the edit to use its latest values.'
  if (['PGRST202', '42P01', '42883'].includes(error?.code)) return 'The database setup is incomplete. Run database/001_schema.sql and database/002_functions.sql in your Supabase SQL Editor.'
  if (error?.code === '42501') return 'Your session cannot access this wallet. Sign in again; if this continues, check the database access policies.'
  if (error?.message?.includes('Failed to fetch') || error?.name === 'AbortError') return 'The connection was interrupted. Refresh your wallet to check its latest saved state before trying again.'
  return error?.message || 'Could not reach your wallet. Please try again.'
}

export function useCloudWallet(data) {
  const enabled = isSupabaseConfigured
  const session = ref(null), authReady = ref(!enabled), recovery = ref(false)
  const loading = ref(false), saving = ref(false), loaded = ref(false), fresh = ref(false)
  const online = ref(navigator.onLine), error = ref(''), cacheWarning = ref('')
  const lastSynced = ref(null)
  let generation = 0, loadSequence = 0, subscription, authTimer, destroyed = false
  const cacheKey = id => `perkify.cloud.v1.${id}`
  const canWrite = computed(() => !enabled || Boolean(session.value && online.value && fresh.value && !loading.value && !saving.value))

  function cache(wallet, id) {
    try { localStorage.setItem(cacheKey(id), JSON.stringify(wallet)); cacheWarning.value = '' }
    catch { cacheWarning.value = 'Your wallet is saved online, but this browser could not keep an offline copy.' }
  }
  function accept(wallet, id) {
    if (!validData(wallet)) throw new Error('The database returned an incomplete wallet. Check that both SQL migrations are installed.')
    data.value = wallet
    loaded.value = true
    fresh.value = true
    lastSynced.value = new Date()
    cache(wallet, id)
  }
  async function refresh() {
    if (!enabled || !session.value || saving.value) return false
    const id = session.value.user.id, stamp = generation, sequence = ++loadSequence
    if (!online.value) { fresh.value = false; return false }
    loading.value = true; error.value = ''
    try {
      const wallet = await walletRepository.getWallet()
      if (stamp !== generation || sequence !== loadSequence || destroyed) return false
      accept(wallet, id)
      return true
    } catch (e) {
      if (stamp === generation && sequence === loadSequence) { error.value = cloudError(e); fresh.value = false }
      return false
    } finally { if (stamp === generation && sequence === loadSequence) loading.value = false }
  }
  async function save(action) {
    if (!canWrite.value) { error.value = 'Reconnect and refresh your wallet before saving changes.'; return false }
    const id = session.value.user.id, stamp = generation
    saving.value = true; error.value = ''
    try {
      const wallet = await action(walletRepository)
      if (stamp !== generation || destroyed) return false
      accept(wallet, id)
      return true
    } catch (e) {
      if (stamp === generation) {
        error.value = cloudError(e)
        // Never replay a possibly committed write automatically. Require a
        // fresh read before the user can initiate another action.
        if (e?.committed || !e?.code || e.code === '40001') {
          fresh.value = false
          error.value += ' Refresh your wallet before making another change.'
        }
      }
      return false
    } finally { if (stamp === generation) saving.value = false }
  }
  function authChanged(event, next) {
    if (destroyed) return
    if (event === 'PASSWORD_RECOVERY') recovery.value = true
    const oldId = session.value?.user.id, nextId = next?.user.id
    session.value = next; authReady.value = true
    if (oldId !== nextId || !nextId) {
      generation++; loadSequence++
      data.value = emptyWallet(); loaded.value = false; fresh.value = false
      loading.value = false; saving.value = false; error.value = ''; lastSynced.value = null
      if (oldId) { try { localStorage.removeItem(cacheKey(oldId)) } catch {} }
      if (!nextId) { recovery.value = false; return }
      try {
        const cached = JSON.parse(localStorage.getItem(cacheKey(nextId)))
        if (validData(cached)) { data.value = cached; loaded.value = true }
      } catch {}
      // Leave the auth callback before calling another Supabase method.
      clearTimeout(authTimer)
      authTimer = setTimeout(() => refresh(), 0)
    }
  }
  async function signOut() {
    if (saving.value) return
    const { error: failure } = await getSupabase().auth.signOut({ scope: 'local' })
    if (failure) { error.value = cloudError(failure); return false }
    return true
  }
  function connectionChanged() {
    online.value = navigator.onLine
    if (!online.value) fresh.value = false
    else refresh()
  }
  onMounted(() => {
    if (!enabled) return
    try { subscription = getSupabase().auth.onAuthStateChange(authChanged).data.subscription }
    catch (e) { error.value = cloudError(e); authReady.value = true }
    window.addEventListener('online', connectionChanged)
    window.addEventListener('offline', connectionChanged)
  })
  onUnmounted(() => {
    destroyed = true; generation++; clearTimeout(authTimer); subscription?.unsubscribe()
    window.removeEventListener('online', connectionChanged)
    window.removeEventListener('offline', connectionChanged)
  })
  return { enabled, session, authReady, recovery, loading, saving, loaded, fresh, online, error, cacheWarning, lastSynced, canWrite, refresh, save, signOut }
}
