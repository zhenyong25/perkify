<script setup>
import { computed, ref } from 'vue'
import { getSupabase } from './lib/supabase'
import Icon from './Icon.vue'

const props = defineProps({ recovery: Boolean })
const emit = defineEmits(['recovered'])
const mode = ref('signin'), email = ref(''), password = ref(''), name = ref('')
const busy = ref(false), error = ref(''), message = ref('')
const title = computed(() => props.recovery ? 'A fresh start for your password.' : mode.value === 'signup' ? 'Your perks deserve a home.' : mode.value === 'reset' ? 'Let’s get you back in.' : 'Welcome to your little extras.')
function changeMode(value) { mode.value = value; error.value = ''; message.value = ''; password.value = '' }
async function submit() {
  if (busy.value) return
  busy.value = true; error.value = ''; message.value = ''
  try {
    const auth = getSupabase().auth
    let result
    if (props.recovery) {
      result = await auth.updateUser({ password: password.value })
      if (result.error) throw result.error
      password.value = ''; emit('recovered'); return
    }
    if (mode.value === 'reset') {
      result = await auth.resetPasswordForEmail(email.value.trim(), { redirectTo: window.location.origin })
      if (result.error) throw result.error
      message.value = 'If that email has an account, a password reset link is on its way.'
    } else if (mode.value === 'signup') {
      result = await auth.signUp({ email: email.value.trim(), password: password.value, options: { data: { name: name.value.trim() }, emailRedirectTo: window.location.origin } })
      if (result.error) throw result.error
      if (!result.data.session) { message.value = 'Check your email to confirm your account, then come back and sign in.'; password.value = '' }
    } else {
      result = await auth.signInWithPassword({ email: email.value.trim(), password: password.value })
      if (result.error) throw result.error
    }
  } catch (e) { error.value = e.message || 'We could not complete that request. Please try again.' }
  finally { busy.value = false }
}
</script>

<template>
  <div class="auth-screen">
    <section class="auth-story"><a class="brand" href="/" aria-label="Perkify home"><span class="brand-mark">p<span>✦</span></span>perkify<span class="brand-dot">.</span></a><div><span class="eyebrow">MAKE EVERY PERK COUNT</span><h1>Small perks.<br>Big possibilities.</h1><p>Your cards, vouchers, and points.<br>One wallet that comes with you.</p><div class="auth-perks"><Icon name="Wallet" :size="32" /><Icon name="Ticket" :size="32" /><Icon name="Gem" :size="32" /></div></div><small>Made for life’s little extras.</small></section>
    <section class="auth-form"><span class="modal-emblem"><Icon :name="recovery ? 'Settings' : 'Sparkles'" :size="26" /></span><h2>{{ title }}</h2><p>{{ recovery ? 'Choose a new password for your Perkify account.' : 'Sign in to keep your wallet saved and available across your devices.' }}</p>
      <form @submit.prevent="submit"><fieldset :disabled="busy">
        <label v-if="mode === 'signup' && !recovery">Your name<input v-model="name" autocomplete="name" maxlength="40" required placeholder="What should we call you?" /></label>
        <label v-if="!recovery">Email<input v-model="email" type="email" autocomplete="email" required placeholder="you@example.com" /></label>
        <label v-if="mode !== 'reset' || recovery">{{ recovery ? 'New password' : 'Password' }}<input v-model="password" type="password" :autocomplete="mode === 'signup' || recovery ? 'new-password' : 'current-password'" required :minlength="mode === 'signup' || recovery ? 8 : 1" :placeholder="mode === 'signup' || recovery ? 'At least 8 characters' : 'Your password'" /></label>
        <p v-if="error" class="form-error" role="alert">{{ error }}</p><p v-if="message" class="auth-message" role="status">{{ message }}</p>
        <button type="submit" class="button primary">{{ busy ? 'Please wait…' : recovery ? 'Save new password' : mode === 'signup' ? 'Create account' : mode === 'reset' ? 'Send reset link' : 'Sign in' }}<Icon name="ArrowRight" :size="17" /></button>
        <template v-if="!recovery"><button v-if="mode === 'signin'" type="button" class="text-button" @click="changeMode('reset')">Forgot password?</button><p class="auth-switch">{{ mode === 'signin' ? 'New to Perkify?' : 'Already have an account?' }} <button type="button" @click="changeMode(mode === 'signin' ? 'signup' : 'signin')">{{ mode === 'signin' ? 'Create an account' : 'Sign in' }}</button></p></template>
      </fieldset></form>
    </section>
  </div>
</template>

<style scoped>
.auth-screen{min-height:100dvh;display:grid;grid-template-columns:1fr 1fr;background:#fafaf6}.auth-story{background:#e9eddf;padding:55px 65px;display:flex;flex-direction:column;justify-content:space-between;gap:60px}.auth-story h1{font-size:52px;line-height:1.2;letter-spacing:-2px;color:#37513a;margin:20px 0}.auth-story p{color:#7b8c6b;font-size:16px}.auth-story small{color:#8b977e}.auth-perks{display:flex;gap:20px;margin-top:35px;color:#829a69}.auth-form{align-self:center;max-width:470px;width:100%;padding:40px;margin:auto}.auth-form h2{font-size:28px;line-height:1.4;letter-spacing:-1px}.auth-form>p{font-size:13px;color:#87937c;margin:14px 0 28px}.auth-form fieldset{padding:0;border:0;min-width:0}.auth-form .button{width:100%;margin-top:22px;font-size:13px}.auth-form label{font-size:12px}.auth-form input{padding:13px}.auth-form .text-button{margin-top:18px;font-size:12px}.auth-message{font-size:12px;background:#edf1e6;padding:13px;border-radius:8px;color:#617b4e}.auth-switch{font-size:12px;margin-top:25px;color:#8c9581}.auth-switch button{color:#d16c4c;padding:0;font-weight:600}@media(max-width:760px){.auth-screen{grid-template-columns:1fr}.auth-story{padding:25px 30px;gap:0}.auth-story>div,.auth-story>small{display:none}.auth-form{padding:35px 28px}.auth-form h2{font-size:25px}}
</style>
