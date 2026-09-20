// Rasterize Perkify's existing vector mark at the sizes required by home screens.
import { chromium } from '@playwright/test'
import { mkdir } from 'node:fs/promises'

await mkdir('public/icons', { recursive: true })
const browser = await chromium.launch({ channel: process.env.PLAYWRIGHT_CHANNEL || undefined })
try {
  const page = await browser.newPage()
  for (const [name, size, maskable] of [['icon-192', 192, false], ['icon-512', 512, false], ['maskable-512', 512, true], ['apple-touch-icon', 180, true]]) {
    await page.setViewportSize({ width: size, height: size })
    await page.setContent(`<html><body style="margin:0"><svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 40 40"><rect width="40" height="40" rx="${maskable ? 0 : 10}" fill="#ef6844"/><path d="M12 29V11h10a6 6 0 0 1 0 12h-5v6zm5-11h5a1 1 0 0 0 0-2h-5z" fill="white"/></svg></body></html>`)
    await page.screenshot({ path: `public/icons/${name}.png`, omitBackground: true })
  }
} finally { await browser.close() }
console.log('Generated 192px, 512px, maskable, and Apple touch icons.')
