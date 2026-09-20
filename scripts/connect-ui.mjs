import fs from 'node:fs'
let app=fs.readFileSync('src/App.vue','utf8')
app=app.replace("import PwaPanel from './PwaPanel.vue'", "import PwaPanel from './PwaPanel.vue'\nimport AuthScreen from './AuthScreen.vue'\nimport { isSupabaseConfigured } from './lib/supabase'\nimport { useCloudWallet, emptyWallet } from './lib/useCloudWallet'")
const start=app.indexOf('let initial = seedData()')
const end=app.indexOf("const page = ref('Overview')")
app=app.slice(0,start)+`const cloudEnabled = isSupabaseConfigured
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
`+app.slice(end)
app=app.replace("const money = value => new Intl.NumberFormat('en-MY', { style: 'currency', currency: data.value.settings.currency", "const money = (value, currency = data.value.settings.currency) => new Intl.NumberFormat('en-MY', { style: 'currency', currency")
app=app.replace("function open(type, item) {", `function open(type, item) {
  if (saving.value) return
  if (cloudEnabled && ['choose','card','voucher','points','redeem','delete','clear','import'].includes(type) && !canWrite.value) {
    notify('Reconnect and refresh your wallet before making changes.'); return
  }`)
app=app.replace("{ ...item, operation: 'earn', amount: '', estimatedValue: '' }", "{ ...item, operation: 'earn', amount: '', estimatedValue: '', requestId: crypto.randomUUID() }")
app=app.replace('function close() { modal.value = null;', 'function close() { if (saving.value) return; modal.value = null;')
app=app.replace('function saveItem() {', 'async function saveItem() {\n  if (saving.value) return')
app=app.replace("  const list = modal.value === 'card' ? data.value.cards : data.value.vouchers", `  if (cloudEnabled) {
    const kind = modal.value
    await saveCloud(repo => kind === 'card' ? repo.saveCard(item) : repo.saveVoucher(item), item.id ? 'Your perk has been updated.' : 'Your new perk is saved to your account.')
    return
  }
  const list = modal.value === 'card' ? data.value.cards : data.value.vouchers`)
app=app.replace('function updatePoints() {', 'async function updatePoints() {\n  if (saving.value) return')
app=app.replace('  const ratio = card.points ? card.value / card.points : 0', `  if (cloudEnabled) {
    await saveCloud(repo => repo.updatePoints({ cardId: card.id, amount, kind: redeem ? 'redeem' : 'earn', requestId: form.value.requestId, estimatedValue: value }), 'Points balance saved to your account.')
    return
  }
  const ratio = card.points ? card.value / card.points : 0`)
app=app.replace('function redeemVoucher() {', 'async function redeemVoucher() {\n  if (saving.value) return')
app=app.replace("  voucher.redeemed = true; log", "  if (cloudEnabled) { await saveCloud(repo => repo.redeemVoucher(voucher.id), 'Voucher marked as redeemed.'); return }\n  voucher.redeemed = true; log")
app=app.replace('function deleteItem() { const key', "async function deleteItem() { if (cloudEnabled) { const item = { ...form.value }; await saveCloud(repo => repo.deletePerk(item.type, item), 'Perk removed from your wallet.'); return } const key")
app=app.replace('function confirmImport() { data.value', "async function confirmImport() { if (cloudEnabled) { const wallet = form.value.imported; await saveCloud(repo => repo.replaceWallet(wallet), 'Your account wallet has been restored.'); return } data.value")
app=app.replace('function clearWallet() { data.value', "async function clearWallet() { if (cloudEnabled) { await saveCloud(repo => repo.clearWallet(), 'Your account wallet is now empty.'); return } data.value")
const insert=app.indexOf('const expiryLabel =')
app=app.slice(0,insert)+`async function saveCloud(action, message) {
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
`+app.slice(insert)
app=app.replace("onUnmounted(() => { clearTimeout(toastTimer);", "onUnmounted(() => { document.removeEventListener('visibilitychange', refreshOnFocus); clearTimeout(toastTimer);")
app=app.replace('  <div class="app-shell">', `  <div v-if="cloudEnabled && !authReady" class="cloud-loading"><span class="brand-mark">p<span>✦</span></span><h2>Opening your wallet...</h2></div>
  <AuthScreen v-else-if="cloudEnabled && (!session || recovery)" :recovery="recovery" @recovered="recovery = false" />
  <div v-else-if="cloudEnabled && !loaded" class="cloud-loading"><span class="brand-mark">p<span>✦</span></span><h2>{{ loading ? 'Loading your perks...' : 'Your wallet is not available yet.' }}</h2><p v-if="syncError" role="alert">{{ syncError }}</p><p v-else-if="!online">Connect to the internet to load your wallet on this device.</p><div><button class="button primary" :disabled="loading || !online" @click="refreshWallet">Try again</button><button class="button secondary" @click="cloud.signOut">Sign out</button></div></div>
  <div v-else class="app-shell">`)
app=app.replace(' Saved on this device <Icon', " {{ cloudEnabled ? saving ? 'Saving to your account...' : fresh ? 'Saved to your account' : 'Viewing saved copy' : 'Saved on this device' }} <Icon")
app=app.replace('        <div v-if="storageError"', `        <div v-if="cloudEnabled && (syncError || cacheWarning || !online || loading || !fresh)" class="cloud-banner" role="status"><span>{{ syncError || cacheWarning || (!online ? 'Offline: viewing your last saved wallet. Reconnect to make changes.' : loading ? 'Refreshing your wallet...' : 'Refresh your wallet before making changes.') }}</span><button class="button secondary compact" :disabled="!online || loading || saving" @click="refreshWallet">Refresh wallet</button></div>
        <div v-if="storageError"`)
app=app.replace('Sample perks are for exploration.', "{{ cloudEnabled ? 'Your wallet is saved to your account.' : 'Sample perks are for exploration.' }}")
app=app.replaceAll("money(item.amount) : nf.format(item.amount)", "money(item.amount, item.currency || data.settings.currency) : nf.format(item.amount)")
const settingsStart=app.indexOf('        <template v-else-if="page === \'Settings\'">')
const settingsEnd=app.indexOf('</template>', settingsStart)+'</template>'.length
app=app.slice(0,settingsStart)+`        <template v-else-if="page === 'Settings'">
          <section v-if="cloudEnabled" class="settings-card account-card"><div><h2>Your Perkify account</h2><p>{{ session.user.email }}</p><small>{{ lastSynced ? 'Last refreshed ' + lastSynced.toLocaleTimeString() : 'Viewing your saved wallet' }}</small></div><div class="settings-actions"><button class="button secondary" :disabled="loading || saving || !online" @click="refreshWallet">Refresh wallet</button><button class="button secondary" :disabled="saving" @click="cloud.signOut">Sign out</button></div></section>
          <div class="settings-grid"><section class="settings-card"><h2>The personal touches</h2><p>{{ cloudEnabled ? 'Save your preferences to use them on every device.' : 'Preferences save automatically on this device.' }}</p><fieldset class="plain-fieldset" :disabled="cloudEnabled && !canWrite"><label>Your name<input v-model="profileDraft.name" @input="editProfile" maxlength="40" placeholder="What should we call you?" /></label><label>Display currency<select v-model="profileDraft.currency" @change="editProfile"><option value="MYR">MYR - Malaysian Ringgit</option><option value="USD">USD - US Dollar</option><option value="SGD">SGD - Singapore Dollar</option><option value="EUR">EUR - Euro</option><option value="GBP">GBP - British Pound</option></select></label><label v-if="cloudEnabled">Expiry timezone<input v-model="profileDraft.timezone" @input="editProfile" placeholder="Asia/Kuala_Lumpur" /></label><p class="field-hint">Changing currency changes the label only. Update your cash estimates to match; no currency conversion is applied.</p><div v-if="cloudEnabled" class="settings-actions profile-actions"><button class="button primary" :disabled="!profileDirty" @click="saveProfile">Save preferences</button><button v-if="profileDirty" class="button secondary" @click="cancelProfile">Cancel changes</button></div></fieldset></section>
          <section class="settings-card"><h2>A home for your data</h2><p>{{ cloudEnabled ? 'Your perks are saved in your account. Export a backup anytime, or restore one to replace this account wallet.' : 'Your wallet is stored only in this browser. Back it up to keep it safe or move it to another device.' }}</p><div class="settings-actions"><button class="button secondary" @click="exportData"><Icon name="Download" :size="17" />Export backup</button><button class="button secondary" :disabled="cloudEnabled && !canWrite" @click="fileInput.click()"><Icon name="Upload" :size="17" />Import backup</button><input ref="fileInput" type="file" accept=".json,application/json" class="sr-only" @change="importData" /></div><div v-if="cloudEnabled && previousWallet" class="legacy-import"><h3>Bring your previous wallet</h3><p>This browser has an older local wallet that may include sample perks. Review it before replacing your account wallet.</p><button class="button secondary" :disabled="!canWrite" @click="importPreviousWallet">Import previous browser wallet</button></div><hr /><h3>A fresh start</h3><p>{{ cloudEnabled ? 'Clear all cards, vouchers, and history from this account on every device. Your profile stays.' : 'The initial cards and vouchers are samples. Clear your wallet to start with your real perks.' }}</p><button class="button danger-outline" :disabled="cloudEnabled && !canWrite" @click="open('clear')"><Icon name="Trash2" :size="16" />Clear wallet</button></section></div>
          <div class="mvp-note"><span class="brand-mark small-mark">p<span>✦</span></span><div><strong>Perkify - Your everyday rewards companion</strong><p>Reward balances are updated manually. Your saved perks are available offline; account changes need an internet connection.</p></div></div>
        </template>`+app.slice(settingsEnd)
app=app.replace(':busy="!!modal"', ':busy="!!modal || saving" :cloud="cloudEnabled"')
// Disable the full dialog while a write is in progress; all error types remain visible.
app=app.replace('<button class="modal-close icon-button"', '<button :disabled="saving" class="modal-close icon-button"')
app=app.replace('      <template v-if="modal === \'choose\'">', '      <p v-if="cloudEnabled && formError" class="form-error" role="alert">{{ formError }}</p><p v-if="saving" role="status" class="field-hint">Saving your changes...</p><fieldset class="plain-fieldset" :disabled="cloudEnabled && !canWrite">\n      <template v-if="modal === \'choose\'">')
app=app.replace('    </section></div></Teleport>', '    </fieldset></section></div></Teleport>')
app=app.replaceAll('v-if="formError" class="form-error"', 'v-if="formError && !cloudEnabled" class="form-error"')
app=app.replace('  </div>\n</template>', '  </div>\n  <PwaPanel v-if="cloudEnabled && (!authReady || !session || recovery || !loaded)" :show-install="false" :cloud="true" :busy="true" />\n</template>')
fs.writeFileSync('src/App.vue',app)
let pwa=fs.readFileSync('src/PwaPanel.vue','utf8')
pwa=pwa.replace('showInstall: Boolean, busy: Boolean', 'showInstall: Boolean, busy: Boolean, cloud: Boolean')
pwa=pwa.replace('Your wallet still saves on this device.', "{{ cloud ? 'Your saved wallet is available to view. Reconnect to save changes.' : 'Your wallet still saves on this device.' }}")
fs.writeFileSync('src/PwaPanel.vue',pwa)
fs.appendFileSync('src/style.css', '\n.plain-fieldset{border:0;padding:0;margin:0;min-width:0}.plain-fieldset:disabled{opacity:.65}.cloud-loading{min-height:100dvh;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:22px;padding:30px;text-align:center}.cloud-loading>p{max-width:650px;color:#8b795f}.cloud-loading>div{display:flex;gap:12px}.cloud-banner{display:flex;align-items:center;justify-content:space-between;gap:15px;background:#f1f0e4;border:1px solid #e0dfc7;border-radius:9px;padding:14px 18px;margin-bottom:22px;font-size:12px;color:#82744f}.account-card{display:flex;align-items:center;justify-content:space-between;gap:20px;margin-bottom:24px}.account-card p{font-size:13px;margin-top:10px;color:#78856b}.account-card small{font-size:10px;display:block;margin-top:6px;color:#9ca38f}.legacy-import{padding-top:25px}.legacy-import p{font-size:12px;color:#8c9580;margin:10px 0 15px}.profile-actions{margin-top:22px}@media(max-width:500px){.cloud-banner,.account-card{align-items:flex-start;flex-direction:column}}\n')
