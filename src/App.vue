<script setup>
import { computed, ref, watch, nextTick, onUnmounted } from 'vue'
import Icon from './Icon.vue'
import PwaPanel from './PwaPanel.vue'
import AuthScreen from './AuthScreen.vue'
import { isSupabaseConfigured } from './lib/supabase'
import { useCloudWallet, emptyWallet } from './lib/useCloudWallet'
import { useExchangeRates } from './lib/exchangeRates'
import { STORAGE_KEY, seedData, daysUntil, validData, CURRENCIES } from './data'

const cloudEnabled = isSupabaseConfigured
let initial = cloudEnabled ? emptyWallet() : seedData(), initialError = ''
let previousWallet = null
try {
  const saved = localStorage.getItem(STORAGE_KEY)
  if (saved) {
    const parsed = JSON.parse(saved)
    if (validData(parsed)) { previousWallet = parsed; if (!cloudEnabled) initial = parsed }
    else if (!cloudEnabled) throw new Error()
  } else if (!cloudEnabled) localStorage.setItem(STORAGE_KEY, JSON.stringify(initial))
} catch { if (!cloudEnabled) initialError = 'Saved data could not be loaded. Sample data is shown.' }
const data = ref(initial), storageError = ref(initialError)
const cloud = useCloudWallet(data)
const { session, authReady, recovery, loading, saving, loaded, online, fresh, error: syncError, cacheWarning, canWrite, lastSynced } = cloud
const profileDraft = ref({ ...data.value.settings })
const profileDirty = ref(false)
watch(() => data.value.settings, settings => {
  if (!profileDirty.value) profileDraft.value = { ...settings }
}, { deep: true })
function editProfile() {
  if (cloudEnabled) profileDirty.value = true
  else data.value.settings = { ...profileDraft.value }
}
watch(data, value => {
  if (cloudEnabled) return
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify(value)); storageError.value = '' }
  catch { storageError.value = 'Browser storage is unavailable or full. Export a backup to keep your changes.' }
}, { deep: true })
const page = ref('Overview'), query = ref(''), category = ref('All perks'), voucherFilter = ref('Available'), sort = ref('Recently added')
const mobileNav = ref(false), modal = ref(null), form = ref({}), formError = ref(''), toast = ref(''), dialog = ref(null), fileInput = ref(null)
const mobileMedia = window.matchMedia('(max-width: 760px)')
const isMobile = ref(mobileMedia.matches)
function onViewportChange(event) { isMobile.value = event.matches; if (!event.matches) mobileNav.value = false }
mobileMedia.addEventListener('change', onViewportChange)
let toastTimer, previousFocus
const nav = [['Overview', 'LayoutDashboard'], ['My wallet', 'Wallet'], ['Vouchers', 'Ticket'], ['Points', 'Gem'], ['Stamps', 'Stamp'], ['Activity', 'Clock3']]
const categories = ['All perks', 'Food & drink', 'Shopping', 'Travel', 'Lifestyle', 'Other']
const currencies = CURRENCIES
const colors = ['green', 'dark', 'red', 'blue', 'orange', 'lime', 'purple']
const nf = new Intl.NumberFormat('en')
const money = (value, currency = data.value.settings.currency) => new Intl.NumberFormat('en-MY', { style: 'currency', currency, maximumFractionDigits: 2 }).format(value)
const { error: ratesError, convert: convertRate } = useExchangeRates()
const convert = (value, from) => convertRate(value, from, data.value.settings.currency)
const iconFor = item => item.category === 'Food & drink' ? 'Coffee' : item.category === 'Travel' ? 'Plane' : item.category === 'Shopping' ? 'ShoppingBag' : 'Gift'
const isExpired = item => item.expiry && daysUntil(item.expiry) < 0
const milestoneAt = (card, n) => card.milestones.find(m => m.stamps === n)
const nextMilestone = card => card.milestones.find(m => !card.claimed.includes(m.stamps))
const milestoneReward = (card, stamps) => card?.milestones?.find(m => m.stamps === stamps)?.reward || 'your reward'
const availableVouchers = computed(() => data.value.vouchers.filter(v => !v.redeemed && !isExpired(v)))
const activeCards = computed(() => data.value.cards.filter(c => !isExpired(c)))
const estimatedPoints = computed(() => activeCards.value.reduce((sum, c) => sum + convert(c.value, c.currency), 0))
const voucherValue = computed(() => availableVouchers.value.reduce((sum, v) => sum + convert(v.value, v.currency), 0))
const totalValue = computed(() => estimatedPoints.value + voucherValue.value)
const expiring = computed(() => [...data.value.cards.map(x => ({ ...x, type: 'card' })), ...availableVouchers.value.map(x => ({ ...x, type: 'voucher' })), ...data.value.stampCards.map(x => ({ ...x, type: 'stamp' }))].filter(x => x.expiry && daysUntil(x.expiry) >= 0 && daysUntil(x.expiry) <= 30).sort((a, b) => a.expiry.localeCompare(b.expiry)))
const matches = item => `${item.name} ${item.brand || ''} ${item.category}`.toLowerCase().includes(query.value.toLowerCase().trim()) && (category.value === 'All perks' || item.category === category.value)
const filteredCards = computed(() => {
  const result = data.value.cards.filter(matches)
  if (sort.value === 'Name A–Z') result.sort((a, b) => a.name.localeCompare(b.name))
  if (sort.value === 'Expiring soon') result.sort((a, b) => (a.expiry || '9999').localeCompare(b.expiry || '9999'))
  return result
})
const filteredVouchers = computed(() => data.value.vouchers.filter(v => matches(v) && (voucherFilter.value === 'Available' ? !v.redeemed && !isExpired(v) : voucherFilter.value === 'Redeemed' ? v.redeemed : !v.redeemed && isExpired(v))))
const filteredStampCards = computed(() => {
  const result = data.value.stampCards.filter(matches)
  if (sort.value === 'Name A–Z') result.sort((a, b) => a.name.localeCompare(b.name))
  return result
})
const readyStampCards = computed(() => data.value.stampCards.filter(s => s.stamps >= s.target))
const filteredActivity = computed(() => data.value.activity.filter(a => `${a.name} ${a.detail}`.toLowerCase().includes(query.value.toLowerCase().trim())))
const heading = computed(() => ({ Overview: `A little more rewarding, ${data.value.settings.name || 'friend'}.`, 'My wallet': 'Good things in your wallet.', Vouchers: 'Little treats. Real savings.', Points: 'Every point has potential.', Stamps: 'Every visit, a step closer.', Activity: 'Your perks, in motion.', Settings: 'Make Perkify yours.' })[page.value])
const subheading = computed(() => ({ Overview: 'All your perks in one place. Let’s make the most of them.', 'My wallet': 'Your memberships, balances, and benefits. Beautifully together.', Vouchers: 'Keep your next good deal close, and its expiry closer.', Points: 'Track each rewards program and put your points to work.', Stamps: 'Tap a card each visit. Redeem once it’s full.', Activity: 'A simple history of what you’ve earned, added, and redeemed.', Settings: 'A few preferences for your everyday rewards companion.' })[page.value])
function go(target) { page.value = target; query.value = ''; category.value = 'All perks'; mobileNav.value = false }
function notify(message) { toast.value = message; clearTimeout(toastTimer); toastTimer = setTimeout(() => toast.value = '', 4000) }
function log(item, detail, amount = 0, unit = '', kind = 'add') {
  data.value.activity.unshift({ id: crypto.randomUUID(), name: item.brand || item.name, detail, amount, unit, kind, color: item.color || 'orange', currency: item.currency || data.value.settings.currency, date: new Date().toISOString() })
  data.value.activity = data.value.activity.slice(0, 2000)
}
function open(type, item) {
  if (saving.value) return
  if (cloudEnabled && ['choose','card','voucher','stamp','points','redeem','delete','clear','import'].includes(type) && !canWrite.value) {
    notify('Reconnect and refresh your wallet before making changes.'); return
  }
  if (!modal.value) previousFocus = document.activeElement
  formError.value = ''
  if (type === 'card') form.value = item ? { ...item, currency: item.currency || data.value.settings.currency } : { name: '', category: 'Food & drink', points: 0, unit: 'Points', value: 0, currency: data.value.settings.currency, expiry: '', member: '', color: 'green', note: '' }
  else if (type === 'voucher') form.value = item ? { ...item, currency: item.currency || data.value.settings.currency } : { name: '', brand: '', category: 'Shopping', value: 0, currency: data.value.settings.currency, expiry: '', code: '', color: 'orange', note: '', redeemed: false }
  else if (type === 'stamp') form.value = item ? { ...item, milestones: item.milestones.map(m => ({ ...m })), claimed: [...item.claimed] } : { name: '', category: 'Food & drink', milestones: [{ stamps: 9, reward: '' }], expiry: '', color: 'orange', note: '' }
  else if (type === 'points') form.value = { ...item, operation: 'earn', amount: '', estimatedValue: '', requestId: crypto.randomUUID() }
  else form.value = item ? { ...item } : {}
  modal.value = type
  nextTick(() => dialog.value?.querySelector('input, button, select')?.focus())
}
function close() { if (saving.value) return; modal.value = null; nextTick(() => previousFocus?.focus()) }
watch(modal, value => { document.body.style.overflow = value ? 'hidden' : '' })
function trapFocus(event) {
  if (event.key === 'Escape') { close(); return }
  if (event.key !== 'Tab') return
  const elements = [...dialog.value.querySelectorAll('button, input, select, textarea, a[href]')].filter(el => !el.disabled && el.offsetParent !== null)
  const first = elements[0], last = elements.at(-1)
  if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus() }
  else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus() }
}
async function saveItem() {
  if (saving.value) return
  const item = { ...form.value, name: form.value.name.trim() }
  if (!item.name || (modal.value === 'voucher' && !item.brand.trim())) { formError.value = 'Please complete all required names.'; return }
  item.value = Number(item.value)
  if (!Number.isFinite(item.value) || item.value < 0) { formError.value = 'Enter a valid non-negative value.'; return }
  if (modal.value === 'card') {
    item.points = Number(item.points); item.unit = item.unit.trim() || 'Points'
    if (!Number.isFinite(item.points) || item.points < 0) { formError.value = 'Enter a valid non-negative balance.'; return }
  }
  if (cloudEnabled) {
    const kind = modal.value
    await saveCloud(repo => kind === 'card' ? repo.saveCard(item) : repo.saveVoucher(item), item.id ? 'Your perk has been updated.' : 'Your new perk is saved to your account.')
    return
  }
  const list = modal.value === 'card' ? data.value.cards : data.value.vouchers
  const index = list.findIndex(x => x.id === item.id)
  if (index >= 0) list[index] = item
  else { item.id = crypto.randomUUID(); list.unshift(item); log(item, modal.value === 'card' ? 'Membership added' : 'Voucher added', item.value, 'money') }
  notify(index >= 0 ? 'Your perk has been updated.' : 'A new perk, safely tucked away.'); close()
}
async function updatePoints() {
  if (saving.value) return
  const card = data.value.cards.find(c => c.id === form.value.id), amount = Number(form.value.amount)
  if (!Number.isFinite(amount) || amount <= 0) { formError.value = 'Enter an amount greater than zero.'; return }
  const redeem = form.value.operation === 'redeem'
  if (redeem && amount > card.points) { formError.value = 'You don’t have enough points for that redemption.'; return }
  const value = form.value.estimatedValue === '' ? null : Number(form.value.estimatedValue)
  if (value !== null && (!Number.isFinite(value) || value < 0)) { formError.value = 'Enter a valid estimated balance value.'; return }
  if (cloudEnabled) {
    await saveCloud(repo => repo.updatePoints({ cardId: card.id, amount, kind: redeem ? 'redeem' : 'earn', requestId: form.value.requestId, estimatedValue: value }), 'Points balance saved to your account.')
    return
  }
  const ratio = card.points ? card.value / card.points : 0
  card.points = Math.round((card.points + amount * (redeem ? -1 : 1)) * 100) / 100
  card.value = value ?? Math.round(card.points * ratio * 100) / 100
  log(card, redeem ? 'Points redeemed' : 'Points earned', amount, card.unit, redeem ? 'redeem' : 'earn')
  notify('Points balance updated.'); close()
}
async function redeemVoucher() {
  if (saving.value) return
  const voucher = data.value.vouchers.find(v => v.id === form.value.id)
  if (!voucher || voucher.redeemed || isExpired(voucher)) return
  if (cloudEnabled) { await saveCloud(repo => repo.redeemVoucher(voucher.id), 'Voucher marked as redeemed.'); return }
  voucher.redeemed = true; log(voucher, 'Voucher redeemed', voucher.value, 'money', 'redeem')
  notify('Voucher marked as redeemed. Nice saving!'); close()
}
async function stampAction(action, message) {
  const ok = await cloud.save(action)
  if (ok) { if (message) notify(message) } else notify(syncError.value)
}
async function addStamp(card) {
  if (saving.value || card.stamps >= card.target) return
  if (cloudEnabled) { await stampAction(repo => repo.addStamp(card.id)); return }
  card.stamps++
  log(card, 'Stamp added', card.stamps, 'stamp', 'earn')
}
async function removeStamp(card) {
  if (saving.value || card.stamps <= 0) return
  if (cloudEnabled) { await stampAction(repo => repo.removeStamp(card.id)); return }
  card.stamps--
}
function tapStamp(card, n) {
  const milestone = milestoneAt(card, n)
  if (milestone && n <= card.stamps && !card.claimed.includes(n)) { open('redeem', { ...card, type: 'stamp', claimStamps: n }); return }
  if (n === card.stamps) removeStamp(card)
  else if (n === card.stamps + 1) addStamp(card)
}
// Claims a milestone reward. Reaching the final one (stamps = target)
// resets progress and counts as a full completion; earlier ones don't.
async function claimMilestoneCore(card, stamps) {
  if (saving.value) return
  const milestone = milestoneAt(card, stamps)
  if (!milestone || stamps > card.stamps || card.claimed.includes(stamps)) return
  if (cloudEnabled) { await stampAction(repo => repo.claimMilestone(card.id, stamps), `${milestone.reward || 'Reward'} claimed!`); return }
  card.claimed.push(stamps)
  log(card, 'Reward redeemed', stamps, 'stamp', 'redeem')
  if (stamps === card.target) { card.stamps = 0; card.claimed = []; card.completions = (card.completions || 0) + 1 }
  notify(`${milestone.reward || 'Reward'} claimed!`)
}
async function redeemStampFromModal() {
  const card = data.value.stampCards.find(s => s.id === form.value.id)
  if (card) await claimMilestoneCore(card, form.value.claimStamps)
  close()
}
async function saveStampItem() {
  if (saving.value) return
  const item = { ...form.value, name: form.value.name.trim() }
  if (!item.name) { formError.value = 'Please enter a name.'; return }
  const milestones = item.milestones.map(m => ({ stamps: Number(m.stamps), reward: (m.reward || '').trim() }))
  if (milestones.some(m => !Number.isInteger(m.stamps) || m.stamps < 1 || m.stamps > 100)) { formError.value = 'Each reward needs a whole stamp count between 1 and 100.'; return }
  if (new Set(milestones.map(m => m.stamps)).size !== milestones.length) { formError.value = 'Rewards must use different stamp counts.'; return }
  milestones.sort((a, b) => a.stamps - b.stamps)
  item.milestones = milestones
  item.target = milestones.at(-1).stamps
  if (cloudEnabled) {
    await saveCloud(repo => repo.saveStampCard(item), item.id ? 'Your stamp card has been updated.' : 'Your new stamp card is saved to your account.')
    return
  }
  const list = data.value.stampCards
  const index = list.findIndex(x => x.id === item.id)
  if (index >= 0) {
    item.stamps = Math.min(list[index].stamps, item.target)
    item.claimed = list[index].claimed.filter(c => milestones.some(m => m.stamps === c))
    item.completions = list[index].completions
    list[index] = item
  } else { item.id = crypto.randomUUID(); item.stamps = 0; item.claimed = []; item.completions = 0; list.unshift(item); log(item, 'Stamp card added', 0, 'stamp') }
  notify(index >= 0 ? 'Your stamp card has been updated.' : 'A new stamp card, ready to fill.'); close()
}
async function deleteItem() { if (cloudEnabled) { const item = { ...form.value }; await saveCloud(repo => repo.deletePerk(item.type, item), 'Perk removed from your wallet.'); return } const key = form.value.type === 'card' ? 'cards' : form.value.type === 'voucher' ? 'vouchers' : 'stampCards'; data.value[key] = data.value[key].filter(x => x.id !== form.value.id); notify('Perk removed from your wallet.'); close() }
async function copy(code) { try { await navigator.clipboard.writeText(code); notify('Voucher code copied.') } catch { notify('Copy unavailable. Select the code and copy it manually.') } }
function exportData() {
  const url = URL.createObjectURL(new Blob([JSON.stringify(data.value, null, 2)], { type: 'application/json' }))
  const a = document.createElement('a'); a.href = url; a.download = `perkify-backup-${new Date().toISOString().slice(0, 10)}.json`; a.click()
  setTimeout(() => URL.revokeObjectURL(url), 1000); notify('Your wallet backup has been exported.')
}
async function importData(event) {
  const file = event.target.files?.[0]; if (!file) return
  try { if (file.size > 5000000) throw new Error(); const parsed = JSON.parse(await file.text()); if (!validData(parsed)) throw new Error(); open('import', { imported: parsed }) }
  catch { notify('That file isn’t a valid Perkify backup.') }
  event.target.value = ''
}
async function confirmImport() { if (cloudEnabled) { const wallet = form.value.imported; await saveCloud(repo => repo.replaceWallet(wallet), 'Your account wallet has been restored.'); return } data.value = form.value.imported; close(); notify('Your wallet has been restored.') }
async function clearWallet() { if (cloudEnabled) { await saveCloud(repo => repo.clearWallet(), 'Your account wallet is now empty.'); return } data.value = { settings: { ...data.value.settings }, cards: [], vouchers: [], stampCards: [], activity: [] }; close(); notify('Fresh start. Your wallet is ready for your own perks.') }
async function saveCloud(action, message) {
  formError.value = ''
  const user = session.value?.user.id
  const ok = await cloud.save(action)
  if (session.value?.user.id !== user) return
  if (ok) { close(); notify(message) }
  else formError.value = syncError.value
}
async function refreshWallet() {
  if (saving.value) return
  const hadModal = Boolean(modal.value)
  const ok = await cloud.refresh()
  if (ok && hadModal) { modal.value = null; notify('Wallet refreshed. Reopen your perk to edit its latest values.') }
}
async function saveProfile() {
  const settings = { ...profileDraft.value }
  if (await cloud.save(repo => repo.saveProfile(settings))) {
    profileDirty.value = false; profileDraft.value = { ...data.value.settings }; notify('Preferences saved to your account.')
  }
}
function cancelProfile() { profileDirty.value = false; profileDraft.value = { ...data.value.settings } }
function importPreviousWallet() { open('import', { imported: structuredClone(previousWallet) }) }
watch(() => session.value?.user.id, () => {
  modal.value = null; page.value = 'Overview'; query.value = ''; mobileNav.value = false
  profileDirty.value = false; profileDraft.value = { ...data.value.settings }; toast.value = ''
})
function refreshOnFocus() {
  if (cloudEnabled && document.visibilityState === 'visible' && !modal.value && !profileDirty.value && !saving.value && !loading.value) cloud.refresh()
}
document.addEventListener('visibilitychange', refreshOnFocus)
const expiryLabel = item => isExpired(item) ? 'Expired' : daysUntil(item.expiry) === 0 ? 'Expires today' : `In ${daysUntil(item.expiry)} days`
const shortDate = date => new Date(date).toLocaleDateString('en', { month: 'short', day: 'numeric' })
onUnmounted(() => { document.removeEventListener('visibilitychange', refreshOnFocus); clearTimeout(toastTimer); document.body.style.overflow = ''; mobileMedia.removeEventListener('change', onViewportChange) })
</script>

<template>
  <div v-if="cloudEnabled && !authReady" class="cloud-loading"><span class="brand-mark">p<span>✦</span></span><h2>Opening your wallet...</h2></div>
  <AuthScreen v-else-if="cloudEnabled && (!session || recovery)" :recovery="recovery" @recovered="recovery = false" />
  <div v-else-if="cloudEnabled && !loaded" class="cloud-loading"><span class="brand-mark">p<span>✦</span></span><h2>{{ loading ? 'Loading your perks...' : 'Your wallet is not available yet.' }}</h2><p v-if="syncError" role="alert">{{ syncError }}</p><p v-else-if="!online">Connect to the internet to load your wallet on this device.</p><div><button class="button primary" :disabled="loading || !online" @click="refreshWallet">Try again</button><button class="button secondary" @click="cloud.signOut">Sign out</button></div></div>
  <div v-else class="app-shell">
    <div v-if="mobileNav" class="nav-scrim" @click="mobileNav = false"></div>
    <aside class="sidebar" :class="{ 'is-open': mobileNav }" :inert="isMobile && !mobileNav" @keydown.esc="mobileNav = false">
      <a class="brand" href="#" @click.prevent="go('Overview')"><span class="brand-mark">p<span>✦</span></span>perkify<span class="brand-dot">.</span></a>
      <div class="workspace"><span class="workspace-avatar">{{ (data.settings.name || 'P')[0].toUpperCase() }}</span><div><strong>Personal space</strong><small>Your everyday, upgraded</small></div><Icon name="ChevronDown" :size="15" /></div>
      <div class="nav-label">YOUR PERKS</div>
      <nav aria-label="Main navigation"><button v-for="[label, icon] in nav" :key="label" :class="['nav-item', { active: page === label }]" @click="go(label)"><Icon :name="icon" :size="19" /><span>{{ label }}</span><span v-if="label === 'Vouchers' && availableVouchers.length" class="nav-count">{{ availableVouchers.length }}</span><span v-if="label === 'Stamps' && readyStampCards.length" class="nav-count">{{ readyStampCards.length }}</span><span v-if="page === label" class="active-dot"></span></button></nav>
      <div class="sidebar-bottom"><div class="sidebar-tip"><span class="tip-icon"><Icon name="Sparkles" /></span><h3>Small perks.<br>Big possibilities.</h3><p>That coffee, that getaway, that little treat. It all adds up.</p><button @click="open('choose')">Add your next perk <Icon name="ArrowUpRight" :size="16" /></button></div><button :class="['nav-item', { active: page === 'Settings' }]" @click="go('Settings')"><Icon name="Settings" :size="19" />Settings</button><button class="local-status" @click="go('Settings')"><span></span> {{ cloudEnabled ? saving ? 'Saving to your account...' : fresh ? 'Saved to your account' : 'Viewing saved copy' : 'Saved on this device' }} <Icon name="CircleHelp" :size="14" /></button></div>
    </aside>
    <div class="main-shell">
      <header class="topbar"><div class="breadcrumb"><button class="mobile-menu icon-button" aria-label="Open navigation" @click="mobileNav = true"><Icon name="Menu" /></button><span>My workspace</span><Icon name="ChevronRight" :size="14" /><strong>{{ page }}</strong></div><div class="topbar-right"><span class="today">{{ new Date().toLocaleDateString('en', { weekday: 'short', month: 'short', day: 'numeric' }) }}</span><button class="notification icon-button" aria-label="View expiry reminders" @click="open('reminders')"><Icon name="Bell" :size="19" /><i v-if="expiring.length"></i></button><button class="user-avatar" aria-label="Open profile settings" @click="go('Settings')">{{ (data.settings.name || 'P').slice(0, 1).toUpperCase() }}</button></div></header>
      <main>
        <div v-if="cloudEnabled && (syncError || cacheWarning || !online || loading || !fresh)" class="cloud-banner" role="status"><span>{{ syncError || cacheWarning || (!online ? 'Offline: viewing your last saved wallet. Reconnect to make changes.' : loading ? 'Refreshing your wallet...' : 'Refresh your wallet before making changes.') }}</span><button class="button secondary compact" :disabled="!online || loading || saving" @click="refreshWallet">Refresh wallet</button></div>
        <div v-if="storageError" class="storage-warning" role="alert">{{ storageError }}</div>
        <section class="page-heading"><div><div class="eyebrow"><span></span> YOUR EVERYDAY ADVANTAGE</div><h1>{{ heading }}</h1><p>{{ subheading }}</p></div><button v-if="page !== 'Settings' && page !== 'Activity'" class="button primary" @click="open(page === 'Vouchers' ? 'voucher' : page === 'Points' ? 'card' : page === 'Stamps' ? 'stamp' : 'choose')"><Icon name="Plus" :size="18" />Add a perk</button></section>
        <template v-if="page === 'Overview'">
          <section class="stats-grid" aria-label="Wallet summary">
            <div class="stat-card main-stat"><div class="stat-top"><span>Total perk value</span><span class="stat-icon"><Icon name="Sparkles" :size="19" /></span></div><strong>{{ money(totalValue) }}</strong><div class="stat-caption"><span class="tiny-spark">✦</span> {{ ratesError || 'A little extra, already yours.' }}</div><span class="stat-decoration">✳</span></div>
            <button class="stat-card" @click="go('Points')"><div class="stat-top"><span>Points value</span><span class="stat-icon lavender"><Icon name="Gem" :size="19" /></span></div><strong>{{ money(estimatedPoints) }}</strong><div class="stat-caption"><span>{{ activeCards.length }} rewards programs</span><Icon name="ArrowUpRight" :size="16" /></div></button>
            <button class="stat-card" @click="go('Vouchers')"><div class="stat-top"><span>Available vouchers</span><span class="stat-icon peach"><Icon name="Ticket" :size="19" /></span></div><strong>{{ availableVouchers.length.toString().padStart(2, '0') }}<small>{{ money(voucherValue) }} in savings</small></strong><div class="stat-caption"><span>Ready when you are</span><Icon name="ArrowUpRight" :size="16" /></div></button>
            <button class="stat-card" @click="open('reminders')"><div class="stat-top"><span>Expiring soon</span><span class="stat-icon sand"><Icon name="Clock3" :size="19" /></span></div><strong>{{ expiring.length.toString().padStart(2, '0') }}<small>perks to use</small></strong><div class="stat-caption"><span class="orange-text">Within the next 30 days</span><Icon name="ArrowUpRight" :size="16" /></div></button>
          </section>
          <div class="overview-columns"><div class="overview-main">
            <section><div class="section-heading"><div><h2>Your wallet <span class="count-pill">{{ data.cards.length }}</span></h2><p>Good things come to those who keep track.</p></div><button class="text-button" @click="go('My wallet')">View all <Icon name="ArrowRight" :size="16" /></button></div>
              <div class="wallet-grid"><button v-for="card in data.cards.slice(0, 3)" :key="card.id" :class="['reward-card', card.color]" @click="open('detail', { ...card, type: 'card' })"><div class="card-header"><span class="card-logo"><Icon :name="iconFor(card)" :size="22" /></span><Icon name="ArrowUpRight" :size="18" /></div><div class="card-name">{{ card.name }}</div><div class="card-membership">{{ card.category }} · Membership</div><div class="card-balance">{{ nf.format(card.points) }} <span>{{ card.unit }}</span></div><div class="card-footer"><span>•••• {{ card.member.slice(-4) || '—' }}</span><span>perkify ✦</span></div></button></div>
              <button class="add-card-row" @click="open('card')"><span><Icon name="Plus" :size="16" /></span>A new membership? Give it a home.<strong>Add a card <Icon name="ArrowRight" :size="15" /></strong></button>
            </section>
            <section><div class="section-heading"><div><h2>A treat waiting for you</h2><p>Your next excuse to save a little.</p></div><button class="text-button" @click="go('Vouchers')">All vouchers <Icon name="ArrowRight" :size="16" /></button></div><div class="voucher-preview-grid"><button v-for="voucher in availableVouchers.slice(0, 2)" :key="voucher.id" class="voucher-preview" @click="open('detail', { ...voucher, type: 'voucher' })"><span :class="['merchant-icon', voucher.color]"><Icon :name="iconFor(voucher)" :size="22" /></span><span class="voucher-preview-info"><small>{{ voucher.brand }}</small><strong>{{ money(voucher.value, voucher.currency) }} voucher</strong><span>{{ voucher.expiry ? `Valid until ${shortDate(voucher.expiry + 'T00:00:00')}` : 'No expiry date' }}</span></span><Icon name="ChevronRight" :size="17" /></button></div><div v-if="!availableVouchers.length" class="empty-inline">No vouchers yet. Add one to start saving.</div></section>
            <section><div class="section-heading"><div><h2>A little progress, lately</h2><p>Every earned point is a small win.</p></div><button class="text-button" @click="go('Activity')">View activity <Icon name="ArrowRight" :size="16" /></button></div><div class="activity-list"><div v-for="item in data.activity.slice(0, 3)" :key="item.id" class="activity-row"><span :class="['activity-icon', item.color]"><Icon :name="item.kind === 'redeem' ? 'ArrowUpRight' : 'ArrowDownLeft'" :size="18" /></span><div class="activity-description"><strong>{{ item.name }}</strong><span>{{ item.detail }} <b>·</b> {{ shortDate(item.date) }}</span></div><strong :class="['activity-amount', { earned: item.kind === 'earn' }]">{{ item.kind === 'earn' ? '+' : item.kind === 'redeem' ? '−' : '' }}{{ item.unit === 'money' ? money(convert(item.amount, item.currency || data.settings.currency)) : nf.format(item.amount) }} <small v-if="item.unit !== 'money'">{{ item.unit }}</small></strong></div><div v-if="!data.activity.length" class="empty-inline">Your perk story starts here. Add a card or voucher to begin.</div></div></section>
          </div><aside class="overview-aside"><section class="expiry-panel"><div class="expiry-heading"><span class="clock-badge"><Icon name="Clock3" :size="19" /></span><h2>Use it, don’t lose it</h2></div><p>Good perks deserve to be enjoyed.</p><div class="expiry-list"><button v-for="item in expiring.slice(0, 3)" :key="item.id" class="expiry-item" @click="open('detail', item)"><div class="expiry-item-top"><span :class="['merchant-icon small', item.color]"><Icon :name="iconFor(item)" :size="17" /></span><span>{{ item.brand || item.name }}</span></div><strong>{{ item.type === 'card' ? `${nf.format(item.points)} ${item.unit}` : item.type === 'voucher' ? `${money(item.value, item.currency)} voucher` : `${item.stamps}/${item.target} stamps` }}</strong><div class="expiry-item-bottom"><span :class="['expiry-tag', { urgent: daysUntil(item.expiry) <= 7 }]">{{ expiryLabel(item) }}</span><Icon name="ArrowUpRight" :size="17" /></div></button><div v-if="!expiring.length" class="expiry-empty"><Icon name="CheckCheck" :size="32" /><strong>You’re all caught up.</strong><span>No perks expiring in the next 30 days.</span></div></div><button v-if="expiring.length" class="reminders-button" @click="open('reminders')">See all reminders <Icon name="ArrowRight" :size="16" /></button></section><section class="little-things"><div class="decorative-flower" aria-hidden="true">✳</div><span class="eyebrow">THE PERKIFY PHILOSOPHY</span><h2>Life’s better with<br>a few extra perks.</h2><p>Less forgotten points.<br>More little moments of joy.</p><span class="handwritten">Make every perk count.</span></section></aside></div>
          <p class="estimate-note">Values are your own estimates. Points stay separate by program. {{ cloudEnabled ? 'Your wallet is saved to your account.' : 'Sample perks are for exploration.' }}</p>
        </template>
        <template v-else-if="['My wallet', 'Vouchers', 'Points', 'Stamps'].includes(page)">
          <div class="collection-toolbar"><label class="search-field"><Icon name="Search" :size="18" /><input v-model="query" placeholder="Search your perks…" aria-label="Search perks" /></label><select v-model="sort" v-if="page !== 'Vouchers'" aria-label="Sort memberships"><option>Recently added</option><option>Name A–Z</option><option>Expiring soon</option></select><div v-else class="segmented"><button v-for="status in ['Available', 'Redeemed', 'Expired']" :key="status" :class="{ selected: voucherFilter === status }" @click="voucherFilter = status">{{ status }}</button></div></div>
          <div class="category-tabs"><button v-for="cat in categories" :key="cat" :class="{ selected: category === cat }" @click="category = cat">{{ cat }}</button></div>
          <div v-if="page === 'My wallet'" class="full-wallet-grid"><div v-for="card in filteredCards" :key="card.id" class="wallet-item"><button :class="['reward-card', card.color]" @click="open('detail', { ...card, type: 'card' })"><div class="card-header"><span class="card-logo"><Icon :name="iconFor(card)" :size="25" /></span><Icon name="ArrowUpRight" :size="19" /></div><div class="card-name">{{ card.name }}</div><div class="card-membership">{{ card.category }} · Membership</div><div class="card-balance">{{ nf.format(card.points) }} <span>{{ card.unit }}</span></div><div class="card-footer"><span>•••• {{ card.member.slice(-4) || '—' }}</span><span>perkify ✦</span></div></button><div class="wallet-item-meta"><span>{{ card.expiry ? `${isExpired(card) ? 'Expired' : 'Expires'} ${shortDate(card.expiry + 'T00:00:00')}` : 'No expiry date' }}</span><button class="text-button" @click="open('points', card)">Update points <Icon name="Plus" :size="14" /></button></div></div><button class="new-card-tile" @click="open('card')"><Icon name="Plus" :size="28" /><strong>Room for another perk</strong><span>Add a rewards card</span></button></div>
          <div v-if="page === 'Points'" class="points-table-wrap"><table class="points-table"><thead><tr><th>Rewards program</th><th>Balance</th><th>Estimated value</th><th>Expiry</th><th><span class="sr-only">Actions</span></th></tr></thead><tbody><tr v-for="card in filteredCards" :key="card.id"><td><span :class="['merchant-icon', card.color]"><Icon :name="iconFor(card)" /></span><strong>{{ card.name }}</strong></td><td><strong>{{ nf.format(card.points) }}</strong> <small>{{ card.unit }}</small></td><td>{{ money(card.value, card.currency) }}</td><td><span :class="{ 'orange-text': isExpired(card) }">{{ card.expiry ? `${isExpired(card) ? 'Expired · ' : ''}${shortDate(card.expiry + 'T00:00:00')}` : 'No expiry' }}</span></td><td><button class="button secondary compact" @click="open('points', card)">Update <Icon name="Plus" :size="15" /></button></td></tr></tbody></table><div v-if="!filteredCards.length" class="empty-state"><Icon name="Gem" :size="35" /><h2>No programs found</h2><p>Add a membership or adjust your filters.</p><button class="button primary" @click="open('card')">Add a card</button></div></div>
          <div v-if="page === 'Vouchers'" class="full-voucher-grid"><article v-for="voucher in filteredVouchers" :key="voucher.id" :class="['voucher-tile', { used: voucher.redeemed || isExpired(voucher) }]"><div class="voucher-tile-top"><span :class="['merchant-icon', voucher.color]"><Icon :name="iconFor(voucher)" :size="24" /></span><div><strong>{{ voucher.brand }}</strong><span>{{ voucher.category }}</span></div></div><div class="voucher-tile-value">{{ money(voucher.value, voucher.currency) }}<span>OFF</span></div><h3>{{ voucher.name }}</h3><div class="ticket-divider"></div><div class="voucher-tile-bottom"><span :class="['expiry-tag', { urgent: !voucher.redeemed && voucher.expiry && daysUntil(voucher.expiry) <= 7 }]">{{ voucher.redeemed ? 'Redeemed' : voucher.expiry ? expiryLabel(voucher) : 'No expiry' }}</span><button class="text-button" @click="open('detail', { ...voucher, type: 'voucher' })">{{ voucher.redeemed || isExpired(voucher) ? 'View details' : 'Use voucher' }}<Icon name="ArrowRight" :size="16" /></button></div></article><div v-if="!filteredVouchers.length" class="empty-state"><Icon name="Ticket" :size="35" /><h2>No {{ voucherFilter.toLowerCase() }} vouchers here</h2><p>{{ query || category !== 'All perks' ? 'Try a different search or category.' : 'Add your vouchers and keep your next saving close.' }}</p><button class="button primary" @click="open('voucher')">Add a voucher</button></div></div>
          <div v-if="page === 'Stamps'" class="full-wallet-grid"><div v-for="card in filteredStampCards" :key="card.id" class="wallet-item"><article :class="['reward-card stamp-card', card.color]"><div class="card-header"><span class="card-logo"><Icon :name="iconFor(card)" :size="25" /></span><button class="icon-button" aria-label="View stamp card details" @click="open('detail', { ...card, type: 'stamp' })"><Icon name="ArrowUpRight" :size="19" /></button></div><div class="card-name">{{ card.name }}</div><div class="card-membership">{{ card.category }} · Loyalty card</div><div class="stamp-row" role="group" aria-label="Stamps"><button v-for="n in card.target" :key="n" type="button" :class="['stamp-dot', { filled: n <= card.stamps, milestone: milestoneAt(card, n), claimed: milestoneAt(card, n) && card.claimed.includes(n), claimable: milestoneAt(card, n) && n <= card.stamps && !card.claimed.includes(n) }]" :disabled="cloudEnabled && !canWrite" :title="milestoneAt(card, n) ? `${milestoneAt(card, n).reward || 'Reward'} at ${n} stamps${card.claimed.includes(n) ? ' · Claimed' : n <= card.stamps ? ' · Tap to claim' : ''}` : undefined" :aria-label="milestoneAt(card, n) ? `${milestoneAt(card, n).reward || 'Reward'} at ${n} stamps` : n === card.stamps ? 'Remove last stamp' : n === card.stamps + 1 ? 'Add a stamp' : `Stamp ${n}`" @click="tapStamp(card, n)"><Icon v-if="milestoneAt(card, n)" name="Gift" :size="12" /><Icon v-else-if="n <= card.stamps" name="Check" :size="11" /></button></div><div class="card-footer"><span>{{ card.stamps }}/{{ card.target }} stamps</span><span v-if="card.expiry">{{ isExpired(card) ? 'Expired' : `Until ${shortDate(card.expiry + 'T00:00:00')}` }}</span><span v-else>{{ card.completions ? `${card.completions}× redeemed` : 'perkify ✦' }}</span></div></article><div class="wallet-item-meta"><span>{{ nextMilestone(card) ? `${nextMilestone(card).reward || 'Reward'} at ${nextMilestone(card).stamps}` : 'All rewards claimed' }}</span><button v-if="nextMilestone(card) && card.stamps >= nextMilestone(card).stamps" class="text-button" @click="open('redeem', { ...card, type: 'stamp', claimStamps: nextMilestone(card).stamps })">Claim <Icon name="Check" :size="14" /></button><button v-else class="text-button" @click="open('detail', { ...card, type: 'stamp' })">Details <Icon name="ArrowRight" :size="14" /></button></div></div><button class="new-card-tile" @click="open('stamp')"><Icon name="Plus" :size="28" /><strong>Track another loyalty card</strong><span>Add a stamp card</span></button></div>
          <p v-if="page === 'Points'" class="estimate-note">Point balances are tracked separately. Cash values are manual estimates, not live conversion rates.</p>
        </template>
        <template v-else-if="page === 'Activity'"><div class="collection-toolbar"><label class="search-field"><Icon name="Search" :size="18" /><input v-model="query" placeholder="Search your activity…" aria-label="Search activity" /></label><span class="muted">{{ filteredActivity.length }} updates</span></div><div class="activity-list full-activity"><div v-for="item in filteredActivity" :key="item.id" class="activity-row"><span :class="['activity-icon', item.color]"><Icon :name="item.kind === 'redeem' ? 'ArrowUpRight' : 'ArrowDownLeft'" /></span><div class="activity-description"><strong>{{ item.name }}</strong><span>{{ item.detail }} <b>·</b> {{ new Date(item.date).toLocaleDateString('en', { year: 'numeric', month: 'short', day: 'numeric' }) }}</span></div><strong :class="['activity-amount', { earned: item.kind === 'earn' }]">{{ item.kind === 'earn' ? '+' : item.kind === 'redeem' ? '−' : '' }}{{ item.unit === 'money' ? money(convert(item.amount, item.currency || data.settings.currency)) : nf.format(item.amount) }} <small v-if="item.unit !== 'money'">{{ item.unit }}</small></strong></div><div v-if="!filteredActivity.length" class="empty-state"><Icon name="Clock3" :size="35" /><h2>A fresh page</h2><p>Your activity will appear here as you add and use perks.</p></div></div></template>
        <template v-else-if="page === 'Settings'">
          <section v-if="cloudEnabled" class="settings-card account-card"><div><h2>Your Perkify account</h2><p>{{ session.user.email }}</p><small>{{ lastSynced ? 'Last refreshed ' + lastSynced.toLocaleTimeString() : 'Viewing your saved wallet' }}</small></div><div class="settings-actions"><button class="button secondary" :disabled="loading || saving || !online" @click="refreshWallet">Refresh wallet</button><button class="button secondary" :disabled="saving" @click="cloud.signOut">Sign out</button></div></section>
          <div class="settings-grid"><section class="settings-card"><h2>The personal touches</h2><p>{{ cloudEnabled ? 'Save your preferences to use them on every device.' : 'Preferences save automatically on this device.' }}</p><fieldset class="plain-fieldset" :disabled="cloudEnabled && !canWrite"><label>Your name<input v-model="profileDraft.name" @input="editProfile" maxlength="40" placeholder="What should we call you?" /></label><label>Display currency<select v-model="profileDraft.currency" @change="editProfile"><option v-for="c in currencies" :key="c.code" :value="c.code">{{ c.code }} - {{ c.name }}</option></select></label><label v-if="cloudEnabled">Expiry timezone<input v-model="profileDraft.timezone" @input="editProfile" placeholder="Asia/Kuala_Lumpur" /></label><p class="field-hint">Changing currency changes the label only. Update your cash estimates to match; no currency conversion is applied.</p><div v-if="cloudEnabled" class="settings-actions profile-actions"><button class="button primary" :disabled="!profileDirty" @click="saveProfile">Save preferences</button><button v-if="profileDirty" class="button secondary" @click="cancelProfile">Cancel changes</button></div></fieldset></section>
          <section class="settings-card"><h2>A home for your data</h2><p>{{ cloudEnabled ? 'Your perks are saved in your account. Export a backup anytime, or restore one to replace this account wallet.' : 'Your wallet is stored only in this browser. Back it up to keep it safe or move it to another device.' }}</p><div class="settings-actions"><button class="button secondary" @click="exportData"><Icon name="Download" :size="17" />Export backup</button><button class="button secondary" :disabled="cloudEnabled && !canWrite" @click="fileInput.click()"><Icon name="Upload" :size="17" />Import backup</button><input ref="fileInput" type="file" accept=".json,application/json" class="sr-only" @change="importData" /></div><div v-if="cloudEnabled && previousWallet" class="legacy-import"><h3>Bring your previous wallet</h3><p>This browser has an older local wallet that may include sample perks. Review it before replacing your account wallet.</p><button class="button secondary" :disabled="!canWrite" @click="importPreviousWallet">Import previous browser wallet</button></div><hr /><h3>A fresh start</h3><p>{{ cloudEnabled ? 'Clear all cards, vouchers, and history from this account on every device. Your profile stays.' : 'The initial cards and vouchers are samples. Clear your wallet to start with your real perks.' }}</p><button class="button danger-outline" :disabled="cloudEnabled && !canWrite" @click="open('clear')"><Icon name="Trash2" :size="16" />Clear wallet</button></section></div>
          <div class="mvp-note"><span class="brand-mark small-mark">p<span>✦</span></span><div><strong>Perkify - Your everyday rewards companion</strong><p>Reward balances are updated manually. Your saved perks are available offline; account changes need an internet connection.</p></div></div>
        </template>
        <PwaPanel :show-install="page === 'Settings'" :busy="!!modal || saving" :cloud="cloudEnabled" />
        <footer><span>Made for life’s little extras.</span><span>perkify <span class="orange-text">✦</span></span></footer>
      </main>
    </div>
    <Transition name="toast"><div v-if="toast" class="toast-message" role="status"><span><Icon name="Check" :size="16" /></span>{{ toast }}<button class="icon-button" aria-label="Dismiss notification" @click="toast = ''"><Icon name="X" :size="16" /></button></div></Transition>
    <Teleport to="body"><div v-if="modal" class="modal-backdrop" @click.self="close"><section ref="dialog" class="modal" role="dialog" aria-modal="true" aria-labelledby="modal-title" @keydown="trapFocus"><button :disabled="saving" class="modal-close icon-button" aria-label="Close dialog" @click="close"><Icon name="X" /></button>
      <p v-if="cloudEnabled && formError" class="form-error" role="alert">{{ formError }}</p><p v-if="saving" role="status" class="field-hint">Saving your changes...</p><fieldset class="plain-fieldset" :disabled="cloudEnabled && !canWrite">
      <template v-if="modal === 'choose'"><span class="modal-emblem"><Icon name="Sparkles" :size="25" /></span><h2 id="modal-title">Make room for a little more.</h2><p>What would you like to add to your wallet?</p><button class="choose-option" @click="open('card')"><span class="stat-icon lavender"><Icon name="CreditCard" :size="24" /></span><span><strong>Rewards card</strong><small>Memberships, loyalty points, and stars.</small></span><Icon name="ChevronRight" /></button><button class="choose-option" @click="open('voucher')"><span class="stat-icon peach"><Icon name="Ticket" :size="24" /></span><span><strong>Voucher or coupon</strong><small>Discounts, gift vouchers, and little treats.</small></span><Icon name="ChevronRight" /></button><button class="choose-option" @click="open('stamp')"><span class="stat-icon sand"><Icon name="Stamp" :size="24" /></span><span><strong>Stamp card</strong><small>Loyalty punches toward your next reward.</small></span><Icon name="ChevronRight" /></button></template>
      <template v-else-if="modal === 'card' || modal === 'voucher'"><span class="eyebrow">A LITTLE EXTRA FOR YOUR WALLET</span><h2 id="modal-title">{{ form.id ? 'Edit your' : 'Add a' }} {{ modal === 'card' ? 'rewards card' : 'voucher' }}</h2><p>{{ modal === 'card' ? 'Give those points a place to call home.' : 'Keep a good deal from getting away.' }}</p><form @submit.prevent="saveItem"><label>{{ modal === 'card' ? 'Program name' : 'Voucher title' }}<input v-model="form.name" required maxlength="80" :placeholder="modal === 'card' ? 'e.g. Starbucks Rewards' : 'e.g. RM15 off your next order'" /></label><label v-if="modal === 'voucher'">Brand or store<input v-model="form.brand" required maxlength="60" placeholder="e.g. Shopee" /></label><div class="form-row"><label>Category<select v-model="form.category"><option v-for="cat in categories.slice(1)" :key="cat">{{ cat }}</option></select></label><label>{{ modal === 'card' ? 'Points expiry' : 'Expiry date' }} <span class="optional">(optional)</span><input v-model="form.expiry" type="date" max="9999-12-31" /></label></div><div v-if="modal === 'card'" class="form-row"><label>Points balance<input v-model="form.points" type="number" min="0" max="999999999999" step="0.01" required /></label><label>Point name<input v-model="form.unit" maxlength="25" placeholder="Points, Stars, Miles…" /></label></div><div class="form-row"><label>{{ modal === 'card' ? 'Estimated cash value' : 'Voucher value' }}<div class="value-currency-field"><select v-model="form.currency" :aria-label="`${modal === 'card' ? 'Estimated cash value' : 'Voucher value'} currency`"><option v-for="c in currencies" :key="c.code" :value="c.code">{{ c.code }}</option></select><input v-model="form.value" type="number" min="0" max="999999999999" step="0.01" required :aria-label="modal === 'card' ? 'Estimated cash value' : 'Voucher value'" /></div></label><label>{{ modal === 'card' ? 'Member number' : 'Voucher code' }} <span class="optional">(optional)</span><input v-if="modal === 'card'" v-model="form.member" maxlength="60" placeholder="Membership ID" /><input v-else v-model="form.code" maxlength="100" placeholder="e.g. SAVE15" /></label></div><label>Notes <span class="optional">(optional)</span><textarea v-model="form.note" rows="2" maxlength="1000" placeholder="Terms, benefits, or a reminder to yourself…"></textarea></label><fieldset class="color-field"><legend>Pick a color</legend><button v-for="color in colors" :key="color" type="button" :class="['color-swatch', color]" :aria-label="color" :aria-pressed="form.color === color" @click="form.color = color"><Icon v-if="form.color === color" name="Check" :size="18" /></button></fieldset><p v-if="formError && !cloudEnabled" class="form-error" role="alert">{{ formError }}</p><div class="modal-actions"><button type="button" class="button secondary" @click="close">Cancel</button><button type="submit" class="button primary"><Icon name="Check" :size="17" />{{ form.id ? 'Save changes' : 'Add to my wallet' }}</button></div></form></template>
      <template v-else-if="modal === 'stamp'"><span class="eyebrow">A LITTLE EXTRA FOR YOUR WALLET</span><h2 id="modal-title">{{ form.id ? 'Edit your' : 'Add a' }} stamp card</h2><p>Track loyalty punches toward your rewards.</p><form @submit.prevent="saveStampItem"><label>Card name<input v-model="form.name" required maxlength="80" placeholder="e.g. Local Cafe Loyalty Card" /></label><div class="form-row"><label>Category<select v-model="form.category"><option v-for="cat in categories.slice(1)" :key="cat">{{ cat }}</option></select></label><label>Expiry date <span class="optional">(optional)</span><input v-model="form.expiry" type="date" max="9999-12-31" /></label></div><fieldset class="milestones-field"><legend>Rewards <span class="optional">Set a reward at each stamp count. The highest count is your card's full length.</span></legend><div v-for="(m, i) in form.milestones" :key="i" class="milestone-input-row"><input v-model="m.stamps" type="number" min="1" max="100" step="1" required placeholder="Stamps" aria-label="Stamps needed for this reward" /><input v-model="m.reward" maxlength="200" placeholder="e.g. 1 free coffee" aria-label="Reward" /><button type="button" class="icon-button" aria-label="Remove this reward" :disabled="form.milestones.length <= 1" @click="form.milestones.splice(i, 1)"><Icon name="X" :size="16" /></button></div><button type="button" class="text-button add-milestone" @click="form.milestones.push({ stamps: '', reward: '' })"><Icon name="Plus" :size="14" />Add another reward</button></fieldset><label>Notes <span class="optional">(optional)</span><textarea v-model="form.note" rows="2" maxlength="1000" placeholder="Terms, benefits, or a reminder to yourself…"></textarea></label><fieldset class="color-field"><legend>Pick a color</legend><button v-for="color in colors" :key="color" type="button" :class="['color-swatch', color]" :aria-label="color" :aria-pressed="form.color === color" @click="form.color = color"><Icon v-if="form.color === color" name="Check" :size="18" /></button></fieldset><p v-if="formError && !cloudEnabled" class="form-error" role="alert">{{ formError }}</p><div class="modal-actions"><button type="button" class="button secondary" @click="close">Cancel</button><button type="submit" class="button primary"><Icon name="Check" :size="17" />{{ form.id ? 'Save changes' : 'Add to my wallet' }}</button></div></form></template>
      <template v-else-if="modal === 'detail'"><span :class="['merchant-icon detail-icon', form.color]"><Icon :name="iconFor(form)" :size="28" /></span><span class="eyebrow">{{ form.type === 'card' ? form.category + ' · MEMBERSHIP' : form.type === 'voucher' ? form.brand + ' · VOUCHER' : form.category + ' · STAMP CARD' }}</span><h2 id="modal-title">{{ form.name }}</h2><div class="detail-balance">{{ form.type === 'card' ? nf.format(form.points) : form.type === 'voucher' ? money(form.value, form.currency) : `${form.stamps}/${form.target}` }} <span v-if="form.type === 'card'">{{ form.unit }}</span><span v-if="form.type === 'stamp'">stamps</span></div><p v-if="form.type === 'card'">Estimated value: {{ money(form.value, form.currency) }}</p><p class="detail-note">{{ form.note || 'A little extra, ready for your everyday.' }}</p><div class="detail-info" v-if="form.type !== 'stamp'"><span>{{ form.type === 'card' ? 'Membership number' : 'Status' }}</span><strong>{{ form.type === 'card' ? form.member || 'Not provided' : form.redeemed ? 'Redeemed' : isExpired(form) ? 'Expired' : 'Available' }}</strong></div><div class="detail-info"><span>Expiry</span><strong>{{ form.expiry ? new Date(form.expiry + 'T00:00:00').toLocaleDateString('en', { day: 'numeric', month: 'long', year: 'numeric' }) : 'No expiry date' }}</strong></div><div class="detail-info" v-if="form.type === 'stamp'"><span>Times redeemed</span><strong>{{ form.completions || 0 }}</strong></div><div v-if="form.type === 'voucher' && form.code" class="voucher-code"><code>{{ form.code }}</code><button class="icon-button" aria-label="Copy voucher code" @click="copy(form.code)"><Icon name="Copy" :size="18" /></button></div><p v-if="form.type === 'voucher' && !form.redeemed && !isExpired(form)" class="field-hint">Use this voucher with the merchant, then mark it redeemed here to update your tracker.</p><div v-if="form.type === 'stamp'" class="milestone-list"><div v-for="m in form.milestones" :key="m.stamps" :class="['milestone-row', { claimed: form.claimed.includes(m.stamps), ready: form.stamps >= m.stamps && !form.claimed.includes(m.stamps) }]"><span class="milestone-stamp">{{ m.stamps }}</span><span class="milestone-reward">{{ m.reward || 'Reward not set' }}</span><span class="milestone-status">{{ form.claimed.includes(m.stamps) ? 'Claimed' : form.stamps >= m.stamps ? 'Ready' : `${m.stamps - form.stamps} to go` }}</span><button v-if="form.stamps >= m.stamps && !form.claimed.includes(m.stamps)" class="text-button" @click="open('redeem', { ...form, claimStamps: m.stamps })">Claim</button></div></div><div class="detail-primary"><button v-if="form.type === 'card'" class="button primary" @click="open('points', form)"><Icon name="Plus" :size="17" />Update points</button><button v-else-if="form.type === 'voucher' && !form.redeemed && !isExpired(form)" class="button primary" @click="open('redeem', form)"><Icon name="Check" :size="17" />Mark as redeemed</button></div><div class="detail-actions"><button class="text-button" @click="open(form.type, form)"><Icon name="Pencil" :size="16" />Edit details</button><button class="text-button delete-button" @click="open('delete', form)"><Icon name="Trash2" :size="16" />Remove perk</button></div></template>
      <template v-else-if="modal === 'points'"><span class="modal-emblem"><Icon name="Gem" :size="25" /></span><h2 id="modal-title">A little balance update.</h2><p>{{ form.name }} · {{ nf.format(form.points) }} {{ form.unit }} available</p><form @submit.prevent="updatePoints"><div class="segmented wide"><button type="button" :class="{ selected: form.operation === 'earn' }" @click="form.operation = 'earn'">Earn points</button><button type="button" :class="{ selected: form.operation === 'redeem' }" @click="form.operation = 'redeem'">Redeem points</button></div><label>{{ form.unit }} to {{ form.operation }}<input v-model="form.amount" type="number" min="0.01" max="999999999999" step="0.01" required placeholder="0" /></label><label>New estimated cash value ({{ form.currency }}) <span class="optional">(optional)</span><input v-model="form.estimatedValue" type="number" min="0" max="999999999999" step="0.01" placeholder="Automatically proportional to your balance" /></label><p class="field-hint">Leave the value blank to keep your existing estimate per point. This records a manual update to your tracker.</p><p v-if="formError && !cloudEnabled" class="form-error" role="alert">{{ formError }}</p><div class="modal-actions"><button type="button" class="button secondary" @click="close">Cancel</button><button class="button primary" type="submit">Update balance</button></div></form></template>
      <template v-else-if="modal === 'reminders'"><span class="modal-emblem"><Icon name="Clock3" :size="25" /></span><h2 id="modal-title">Enjoy them while they’re here.</h2><p>Cards, vouchers, and stamp cards expiring in the next 30 days. Reminders appear here when you open Perkify.</p><button v-for="item in expiring" :key="item.id" class="reminder-row" @click="open('detail', item)"><span :class="['merchant-icon', item.color]"><Icon :name="iconFor(item)" /></span><span><strong>{{ item.brand || item.name }}</strong><small>{{ item.type === 'card' ? `${nf.format(item.points)} ${item.unit}` : item.type === 'voucher' ? `${money(item.value, item.currency)} voucher` : `${item.stamps}/${item.target} stamps` }}</small></span><span :class="['expiry-tag', { urgent: daysUntil(item.expiry) <= 7 }]">{{ expiryLabel(item) }}</span><Icon name="ChevronRight" :size="16" /></button><div v-if="!expiring.length" class="empty-state"><Icon name="CheckCheck" :size="35" /><h3>Nothing to rush for.</h3><p>No perks are expiring in the next 30 days.</p></div></template>
      <template v-else-if="['delete', 'clear', 'import', 'redeem'].includes(modal)"><span class="modal-emblem"><Icon :name="modal === 'redeem' ? 'Ticket' : modal === 'import' ? 'Upload' : 'Trash2'" :size="25" /></span><h2 id="modal-title">{{ modal === 'delete' ? 'Remove this perk?' : modal === 'clear' ? 'A fresh start for your wallet?' : modal === 'import' ? 'Restore this wallet?' : form.type === 'stamp' ? 'Ready to redeem?' : 'Already enjoyed this perk?' }}</h2><p>{{ modal === 'delete' ? `Remove ${form.name} from your wallet? Your past activity will remain.` : modal === 'clear' ? 'This removes all cards, vouchers, stamp cards, and activity, including sample data. Export a backup first if you want to keep anything.' : modal === 'import' ? `Replace your wallet with ${form.imported.cards.length} cards, ${form.imported.vouchers.length} vouchers, and ${form.imported.stampCards?.length || 0} stamp cards from this backup? This also replaces your settings and activity.` : form.type === 'stamp' ? `Redeem "${milestoneReward(form, form.claimStamps)}" from ${form.name}? ${form.claimStamps === form.target ? 'This resets its stamps to 0.' : 'Your progress continues toward the next reward.'}` : `Mark this ${money(form.value, form.currency)} ${form.brand} voucher as used? It will move to your redeemed vouchers.` }}</p><div class="modal-actions"><button class="button secondary" @click="close">Cancel</button><button :class="['button', modal === 'delete' || modal === 'clear' ? 'danger' : 'primary']" @click="modal === 'delete' ? deleteItem() : modal === 'clear' ? clearWallet() : modal === 'import' ? confirmImport() : form.type === 'stamp' ? redeemStampFromModal() : redeemVoucher()">{{ modal === 'delete' ? 'Remove perk' : modal === 'clear' ? 'Clear wallet' : modal === 'import' ? 'Restore backup' : 'Yes, redeem it' }}</button></div></template>
    </fieldset></section></div></Teleport>
  </div>
  <PwaPanel v-if="cloudEnabled && (!authReady || !session || recovery || !loaded)" :show-install="false" :cloud="true" :busy="true" />
</template>
