import { chromium } from '@playwright/test'
import assert from 'node:assert/strict'
import { mkdir } from 'node:fs/promises'
await mkdir('artifacts', { recursive: true })

const browser = await chromium.launch({ headless: true, channel: process.env.PLAYWRIGHT_CHANNEL || undefined })
const origin = 'http://127.0.0.1:4173'
try {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 } })
  const page = await context.newPage()
  const errors = []
  page.on('pageerror', e => errors.push(e.message))
  await page.goto(origin)
  await page.getByRole('heading', { name: 'A little more rewarding, Alex.' }).waitFor()
  const manifest = await (await context.request.get(`${origin}/manifest.webmanifest`)).json()
  assert.equal(manifest.short_name, 'Perkify')
  assert.equal(manifest.display, 'standalone')
  assert.equal(manifest.start_url, '/')
  for (const icon of manifest.icons) {
    const response = await context.request.get(origin + icon.src)
    assert.equal(response.status(), 200)
    const png = await response.body()
    assert.equal(png.readUInt32BE(16), Number(icon.sizes.split('x')[0]))
    assert.equal(png.readUInt32BE(20), Number(icon.sizes.split('x')[1]))
  }
  assert.ok(manifest.icons.some(icon => icon.purpose === 'maskable'))
  assert.equal(await page.locator('link[rel="apple-touch-icon"]').getAttribute('href'), '/icons/apple-touch-icon.png')
  const cdp = await context.newCDPSession(page)
  const manifestResult = await cdp.send('Page.getAppManifest')
  assert.deepEqual(manifestResult.errors, [])
  // Detach the extra CDP session before Playwright emulates offline mode.
  await cdp.detach()
  await page.evaluate(() => navigator.serviceWorker.ready.then(() => true))
  await page.reload()
  await page.waitForFunction(() => !!navigator.serviceWorker.controller)
  await page.getByRole('button', { name: 'Open navigation' }).click()
  await page.getByRole('button', { name: 'Settings', exact: true }).click()
  await page.getByText('Ready to open offline on this device').waitFor()

  // Test the install affordance without attempting to automate the OS installer.
  await page.evaluate(() => {
    const event = new Event('beforeinstallprompt', { cancelable: true })
    event.prompt = async () => {}
    event.userChoice = Promise.resolve({ outcome: 'dismissed' })
    window.dispatchEvent(event)
  })
  await page.getByRole('button', { name: 'Install Perkify', exact: true }).click()
  await page.getByText('You can install later from your browser’s menu.').waitFor()
  await page.evaluate(() => window.dispatchEvent(new Event('appinstalled')))
  await page.getByText('Perkify is running as an app. Your wallet is right at home.').waitFor()

  // Reload and mutate real local data with networking completely disabled.
  await context.setOffline(true)
  await page.reload()
  await page.getByRole('heading', { name: 'A little more rewarding, Alex.' }).waitFor()
  await page.locator('.offline-indicator').waitFor({timeout:5000})
  await page.getByRole('button', { name: 'Add a perk', exact: true }).click()
  await page.getByRole('button', { name: 'Rewards card Memberships' }).click()
  const dialog = page.getByRole('dialog')
  await dialog.getByLabel('Program name').fill('Offline Rewards')
  await dialog.getByLabel('Points balance').fill('42')
  await dialog.getByRole('button', { name: 'Add to my wallet' }).click()
  await page.reload()
  assert.equal(await page.evaluate(() => JSON.parse(localStorage.getItem('perkify.wallet.v1')).cards.find(c => c.name === 'Offline Rewards').points), 42)
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true)
  // Cached app assets never include auth or database responses.
  const cached = await page.evaluate(async () => {
    const result = []
    for (const key of await caches.keys()) for (const r of await (await caches.open(key)).keys()) result.push(r.url)
    return result
  })
  assert.ok(cached.some(url => url.includes('.woff2')))
  assert.ok(cached.every(url => url.startsWith(origin)))
  assert.ok(cached.every(url => !url.includes('/auth/') && !url.includes('/rest/')))
  assert.deepEqual(errors, [])
  await context.setOffline(false)
  await page.getByRole('button', { name: 'Open navigation' }).click()
  await page.getByRole('button', { name: 'Settings', exact: true }).click()
  await page.screenshot({ path: 'artifacts/pwa-settings.png', fullPage: true, animations: 'disabled' })

  const iphone = await browser.newContext({ viewport: { width: 390, height: 844 }, userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1' })
  const ios = await iphone.newPage()
  await ios.goto(origin)
  await ios.getByRole('button', { name: 'Open navigation' }).click()
  await ios.getByRole('button', { name: 'Settings', exact: true }).click()
  await ios.getByText('On iPhone or iPad', { exact: true }).waitFor()
  await ios.getByText('Open this site in Safari, tap Share, then choose', { exact: false }).waitFor()
  console.log('PASS: manifest, PNG icon dimensions, Apple icon, service worker control, offline reload and edits, cached fonts, install prompt fallback, installed state, iPhone instructions, mobile layout, and no browser errors.')
} finally { await browser.close() }
