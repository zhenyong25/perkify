export const STORAGE_KEY = 'perkify.wallet.v1'

export const CURRENCIES = [
  { code: 'MYR', name: 'Malaysian Ringgit' },
  { code: 'USD', name: 'US Dollar' },
  { code: 'SGD', name: 'Singapore Dollar' },
  { code: 'EUR', name: 'Euro' },
  { code: 'GBP', name: 'British Pound' },
  { code: 'AUD', name: 'Australian Dollar' },
  { code: 'CAD', name: 'Canadian Dollar' },
  { code: 'NZD', name: 'New Zealand Dollar' },
  { code: 'CHF', name: 'Swiss Franc' },
  { code: 'JPY', name: 'Japanese Yen' },
  { code: 'CNY', name: 'Chinese Yuan' },
  { code: 'HKD', name: 'Hong Kong Dollar' },
  { code: 'TWD', name: 'Taiwan Dollar' },
  { code: 'KRW', name: 'South Korean Won' },
  { code: 'INR', name: 'Indian Rupee' },
  { code: 'IDR', name: 'Indonesian Rupiah' },
  { code: 'THB', name: 'Thai Baht' },
  { code: 'PHP', name: 'Philippine Peso' },
  { code: 'VND', name: 'Vietnamese Dong' },
  { code: 'AED', name: 'UAE Dirham' },
]
export const CURRENCY_CODES = new Set(CURRENCIES.map(c => c.code))

export function dateIn(days) {
  const d = new Date()
  d.setDate(d.getDate() + days)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

export function seedData() {
  return {
    settings: { name: 'Alex', currency: 'MYR' },
    cards: [
      { id: 'c1', name: 'Starbucks Rewards', category: 'Food & drink', points: 245, unit: 'Stars', value: 24.5, currency: 'MYR', expiry: dateIn(6), member: '6080 1294', color: 'green', note: 'A little coffee, a lot of possibilities.' },
      { id: 'c2', name: 'Sephora Beauty Pass', category: 'Shopping', points: 1250, unit: 'Points', value: 62.5, currency: 'MYR', expiry: dateIn(120), member: '8001 4582', color: 'dark', note: 'Something beautiful is waiting.' },
      { id: 'c3', name: 'AirAsia rewards', category: 'Travel', points: 8400, unit: 'Points', value: 84, currency: 'MYR', expiry: dateIn(60), member: '1058 7239', color: 'red', note: 'Your next adventure starts here.' },
      { id: 'c4', name: 'IKEA Family', category: 'Lifestyle', points: 320, unit: 'Points', value: 16, currency: 'MYR', expiry: '', member: '6275 9081', color: 'blue', note: 'Make yourself at home.' },
    ],
    vouchers: [
      { id: 'v1', name: 'Your next coffee, on us', brand: 'Starbucks', category: 'Food & drink', value: 18, currency: 'MYR', code: 'COFFEEONUS', expiry: dateIn(3), color: 'green', redeemed: false, note: 'One complimentary handcrafted drink. Sample voucher.' },
      { id: 'v2', name: 'A little treat for your cart', brand: 'Shopee', category: 'Shopping', value: 15, currency: 'MYR', code: 'PERKIFY15', expiry: dateIn(8), color: 'orange', redeemed: false, note: 'RM15 off your next purchase. Sample voucher.' },
      { id: 'v3', name: 'Take the scenic route', brand: 'Grab', category: 'Travel', value: 10, currency: 'MYR', code: 'LETSGO10', expiry: dateIn(24), color: 'lime', redeemed: false, note: 'RM10 off your next ride. Sample voucher.' },
    ],
    stampCards: [
      { id: 's1', name: 'Local Cafe Loyalty Card', category: 'Food & drink', target: 15, stamps: 6, milestones: [{ stamps: 5, reward: 'Free drink' }, { stamps: 10, reward: 'Free pastry' }, { stamps: 15, reward: 'Free meal' }], claimed: [5], completions: 1, color: 'orange', expiry: dateIn(45), note: 'One stamp per visit.' },
    ],
    activity: [
      { id: 'a1', name: 'Starbucks Rewards', detail: 'Points earned', amount: 45, unit: 'Stars', kind: 'earn', color: 'green', date: new Date().toISOString() },
      { id: 'a2', name: 'Sephora Beauty Pass', detail: 'Points earned', amount: 250, unit: 'Points', kind: 'earn', color: 'dark', date: new Date(Date.now() - 86400000).toISOString() },
      { id: 'a3', name: 'Grab', detail: 'Voucher added', amount: 10, unit: 'money', kind: 'add', color: 'lime', date: new Date(Date.now() - 172800000).toISOString() },
    ],
  }
}

export function daysUntil(date) {
  if (!date) return null
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  return Math.round((new Date(`${date}T00:00:00`) - today) / 86400000)
}

export function validData(data) {
  const text = x => typeof x === 'string' && x.length <= 5000
  const num = x => typeof x === 'number' && Number.isFinite(x) && x >= 0
  const date = x => x === '' || (text(x) && /^\d{4}-\d{2}-\d{2}$/.test(x) && !Number.isNaN(Date.parse(x)) && new Date(x).toISOString().slice(0, 10) === x)
  const colors = ['green', 'dark', 'red', 'blue', 'orange', 'lime', 'purple']
  return !!data && CURRENCY_CODES.has(data.settings?.currency) && text(data.settings?.name)
    && Array.isArray(data.cards) && data.cards.length <= 1000 && data.cards.every(c => text(c.id) && text(c.name) && text(c.category) && num(c.points) && num(c.value) && CURRENCY_CODES.has(c.currency) && text(c.unit) && date(c.expiry) && text(c.member) && text(c.note) && colors.includes(c.color))
    && Array.isArray(data.vouchers) && data.vouchers.length <= 1000 && data.vouchers.every(v => text(v.id) && text(v.name) && text(v.brand) && text(v.category) && num(v.value) && CURRENCY_CODES.has(v.currency) && text(v.code) && date(v.expiry) && typeof v.redeemed === 'boolean' && text(v.note) && colors.includes(v.color))
    && Array.isArray(data.stampCards) && data.stampCards.length <= 1000 && data.stampCards.every(s => text(s.id) && text(s.name) && text(s.category) && Number.isInteger(s.target) && s.target >= 1 && s.target <= 100 && Number.isInteger(s.stamps) && s.stamps >= 0 && s.stamps <= s.target
      && Array.isArray(s.milestones) && s.milestones.length >= 1 && s.milestones.length <= 20 && s.milestones.every(m => Number.isInteger(m.stamps) && m.stamps >= 1 && m.stamps <= 100 && text(m.reward)) && new Set(s.milestones.map(m => m.stamps)).size === s.milestones.length && Math.max(...s.milestones.map(m => m.stamps)) === s.target
      && Array.isArray(s.claimed) && s.claimed.every(c => s.milestones.some(m => m.stamps === c)) && date(s.expiry) && Number.isInteger(s.completions) && s.completions >= 0 && text(s.note) && colors.includes(s.color))
    && new Set([...data.cards, ...data.vouchers, ...data.stampCards].map(x => x.id)).size === data.cards.length + data.vouchers.length + data.stampCards.length
    && Array.isArray(data.activity) && data.activity.length <= 2000 && data.activity.every(a => text(a.id) && text(a.name) && text(a.detail) && num(a.amount) && text(a.unit) && ['add', 'earn', 'redeem'].includes(a.kind) && colors.includes(a.color) && text(a.date) && !Number.isNaN(Date.parse(a.date)))
}
