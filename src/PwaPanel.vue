<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { useRegisterSW } from 'virtual:pwa-register/vue'
import Icon from './Icon.vue'

defineProps({ showInstall: Boolean, busy: Boolean, cloud: Boolean })
const isProduction = import.meta.env.PROD
const installPrompt = ref(null)
const installing = ref(false)
const installedMedia = window.matchMedia('(display-mode: standalone)')
const installed = ref(installedMedia.matches || navigator.standalone === true)
const online = ref(navigator.onLine)
const error = ref('')
const installMessage = ref('')
const offlineAvailable = ref(false)
const updateDismissed = ref(false)
const ios = /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)
let registration
const { needRefresh, updateServiceWorker } = useRegisterSW({
  immediate: true,
  onOfflineReady() { offlineAvailable.value = true },
  onRegisteredSW(_url, value) {
    registration = value
    if (value?.active) offlineAvailable.value = true
  },
  onRegisterError() { error.value = 'Offline setup could not finish. Reconnect and reload to try again.' },
})

function capturePrompt(event) { event.preventDefault(); installPrompt.value = event }
function installedApp() { installed.value = true; installPrompt.value = null; installMessage.value = '' }
function modeChanged(event) { installed.value = event.matches || navigator.standalone === true }
function connectionChanged() { online.value = navigator.onLine; if (online.value) checkUpdate() }
function checkUpdate() {
  if (document.visibilityState === 'visible' && navigator.onLine) registration?.update().catch(() => {})
}
async function install() {
  const prompt = installPrompt.value
  if (!prompt || installing.value) return
  installing.value = true
  try {
    await prompt.prompt()
    const { outcome } = await prompt.userChoice
    installMessage.value = outcome === 'accepted' ? 'Installation requested. Your browser will finish adding Perkify.' : 'You can install later from your browser’s menu.'
  } catch { installMessage.value = 'Open your browser’s menu and choose Install app or Add to Home Screen.' }
  finally { installPrompt.value = null; installing.value = false }
}
async function update() {
  try { await updateServiceWorker(true) }
  catch { error.value = 'The update could not be applied. Reconnect and try again.' }
}
onMounted(() => {
  window.addEventListener('beforeinstallprompt', capturePrompt)
  window.addEventListener('appinstalled', installedApp)
  window.addEventListener('online', connectionChanged)
  window.addEventListener('offline', connectionChanged)
  document.addEventListener('visibilitychange', checkUpdate)
  installedMedia.addEventListener('change', modeChanged)
})
onUnmounted(() => {
  window.removeEventListener('beforeinstallprompt', capturePrompt)
  window.removeEventListener('appinstalled', installedApp)
  window.removeEventListener('online', connectionChanged)
  window.removeEventListener('offline', connectionChanged)
  document.removeEventListener('visibilitychange', checkUpdate)
  installedMedia.removeEventListener('change', modeChanged)
})
</script>

<template>
  <section v-if="showInstall" class="settings-card pwa-settings" aria-labelledby="install-heading">
    <span class="modal-emblem"><Icon name="Download" :size="25" /></span>
    <h2 id="install-heading">Your perks, one tap away.</h2>
    <p v-if="installed">Perkify is running as an app. Your wallet is right at home.</p>
    <p v-else>Put Perkify on your home screen and open your wallet even without a connection, after your first online visit.</p>
    <button v-if="!installed && installPrompt" class="button primary" :disabled="installing" @click="install"><Icon name="Plus" :size="17" />{{ installing ? 'Opening installer…' : 'Install Perkify' }}</button>
    <div v-if="!installed" class="install-instructions">
      <template v-if="ios"><strong>On iPhone or iPad</strong><p>Open this site in Safari, tap Share, then choose <b>Add to Home Screen</b> and tap Add.</p></template>
      <template v-else><strong>From your browser</strong><p>Open the browser menu and choose <b>Install Perkify</b>, <b>Install app</b>, or <b>Add to Home Screen</b>. On desktop, you can also use the install icon in the address bar when available.</p></template>
    </div>
    <p v-if="installMessage" class="field-hint" role="status">{{ installMessage }}</p>
    <p class="pwa-status"><Icon :name="offlineAvailable ? 'CheckCheck' : 'Clock3'" :size="16" />{{ offlineAvailable ? 'Ready to open offline on this device' : 'Offline access becomes available after the installed app finishes loading online.' }}</p>
    <p v-if="!isProduction" class="field-hint">Installation is enabled in the production preview or a deployed HTTPS site.</p>
    <p v-if="error" class="form-error" role="alert">{{ error }}</p>
    <button v-if="needRefresh" class="button secondary" :disabled="busy" @click="update">Update Perkify</button>
  </section>
  <div v-if="!online" class="offline-indicator" role="status">You’re offline. {{ cloud ? 'Your saved wallet is available to view. Reconnect to save changes.' : 'Your wallet still saves on this device.' }}</div>
  <div v-if="needRefresh && !updateDismissed && !busy" class="pwa-update" role="status">
    <div><strong>A fresh Perkify is ready.</strong><p>Reload to get the latest version. Saved perks stay safe.</p></div>
    <button class="button primary compact" @click="update">Update now</button>
    <button class="icon-button" aria-label="Update later" @click="updateDismissed = true"><Icon name="X" :size="17" /></button>
  </div>
</template>

<style scoped>
.pwa-settings{margin-top:24px}.pwa-settings>.modal-emblem{margin-bottom:12px}.pwa-settings>p{max-width:620px}.install-instructions{background:#f3f4ec;border-radius:8px;padding:16px 18px;max-width:650px;margin-top:20px}.install-instructions strong{font-size:12px}.install-instructions p{font-size:12px;color:#7a856e;margin-top:6px}.pwa-status{display:flex;align-items:center;gap:8px;font-size:11px!important}.offline-indicator{position:fixed;bottom:12px;left:50%;transform:translateX(-50%);max-width:calc(100% - 32px);padding:10px 16px;border:1px solid #dbdfcb;border-radius:8px;background:#f2f3e9;color:#697356;font-size:11px;z-index:40;text-align:center}.pwa-update{position:fixed;bottom:24px;right:24px;display:flex;align-items:center;gap:15px;max-width:calc(100% - 32px);padding:18px;background:#fff;border:1px solid #dfe2d4;border-radius:12px;box-shadow:0 7px 30px #26321b20;z-index:45}.pwa-update strong{font-size:12px}.pwa-update p{font-size:10px;color:#8a927e;margin-top:4px}@media(max-width:500px){.pwa-update{bottom:16px;right:16px;gap:8px;flex-wrap:wrap}.pwa-update>div{width:100%}.pwa-settings{padding:22px}}
</style>
