import { ref } from 'vue'

const CACHE_KEY = 'perkify.rates.v1'
const CACHE_TTL = 12 * 60 * 60 * 1000
const RATES_URL = 'https://open.er-api.com/v6/latest/USD'

const rates = ref(null)
const error = ref('')
let initialized = false

function loadCache() {
  try {
    const cached = JSON.parse(localStorage.getItem(CACHE_KEY))
    if (cached?.values) { rates.value = cached; return Date.now() - cached.fetchedAt < CACHE_TTL }
  } catch {}
  return false
}

async function fetchRates() {
  try {
    const response = await fetch(RATES_URL)
    if (!response.ok) throw new Error('Exchange rate request failed')
    const body = await response.json()
    if (!body.rates) throw new Error('Malformed exchange rate response')
    const snapshot = { values: body.rates, fetchedAt: Date.now() }
    rates.value = snapshot
    error.value = ''
    try { localStorage.setItem(CACHE_KEY, JSON.stringify(snapshot)) } catch {}
  } catch {
    if (!rates.value) error.value = 'Exchange rates unavailable. Showing amounts unconverted.'
  }
}

// Rates are relative to USD; converting A -> B goes through USD as a pivot.
export function useExchangeRates() {
  if (!initialized) { initialized = true; if (!loadCache()) fetchRates() }
  function convert(amount, from, to) {
    if (!Number.isFinite(amount) || from === to) return amount
    const values = rates.value?.values
    const rateFrom = values?.[from], rateTo = values?.[to]
    if (!rateFrom || !rateTo) return amount
    return (amount / rateFrom) * rateTo
  }
  return { rates, error, convert }
}
