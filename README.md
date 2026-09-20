# Perkify

A Vue 3 + Vite progressive web app for keeping membership cards, reward balances, and vouchers in one place, with Supabase/PostgreSQL database migrations ready for backend integration.

## Run locally

Requires Node.js 22.13+.

```sh
npm install
npm run dev
```

On Windows PowerShell with script execution disabled, use `npm.cmd` instead of `npm`.

```sh
npm run build
npm run preview
```

## Included

- Dashboard with estimated perk value and upcoming expiries.
- Add, edit, remove, search, and categorize rewards cards and vouchers.
- Separate points balances for each program; record earnings and redemptions with activity history.
- Copy voucher codes and mark vouchers redeemed; expired and redeemed vouchers have separate views.
- Browser localStorage persistence, JSON backup export and validated import.
- Profile name and display currency preferences (MYR by default).
- Responsive layouts, keyboard-accessible dialogs, and empty states.
- Installable PWA with home-screen icons, offline app loading, bundled fonts, and user-controlled updates.
- Database migrations, transactional functions, per-user access policies, and an optional Supabase client repository; see [database setup](database/README.md).

Sample cards, vouchers, and activity appear on first launch. Clear the wallet in Settings to start with your own data. Sample vouchers are not real offers. Values are manual estimates; changing the display currency does not convert existing values. Updating points proportionally adjusts the cash estimate unless a new estimate is entered.

This first version tracks data manually. There is no account, backend, bank integration, live rewards synchronization, or background notification service. Expiry reminders appear inside the app for the next 30 days. Card expiry applies to the whole tracked balance; separate expiry batches are not yet supported. Browser data is specific to the browser and origin, so export a backup before changing devices or clearing browser data. The latest 2,000 activity records are retained.

## Source

- `src/App.vue` — screens, dialogs, state, and user flows.
- `src/data.js` — sample data, date helpers, and backup validation.
- `src/Icon.vue` — Lucide icons.
- `src/style.css` — theme and responsive styling.

Fonts and icons are bundled and precached for offline use. The current UI keeps wallet data in the browser; the database repository is supplied separately and does not silently upload or synchronize data.

## Add to your home screen

Build and preview the production app:

```sh
npm run build
npm run preview -- --port 4173 --strictPort
```

Open `http://localhost:4173` on this computer to test the PWA. Service workers are disabled in the development server to avoid stale development assets. For installation on a phone, deploy the `dist/` directory to a static host with **HTTPS** and open that deployed URL on the phone. A laptop's `localhost` URL is not reachable from a phone, and a plain HTTP LAN address does not provide normal PWA installation/offline support.

- **Android / supported desktop browsers:** Settings in Perkify shows an Install Perkify button when the browser provides an install prompt. Alternatively use the browser's Install app / Add to Home Screen menu item.
- **iPhone / iPad:** Open in Safari, tap Share, choose Add to Home Screen, then Add. Perkify also shows these instructions in Settings.
- Visit online first and wait for Settings to show that offline access is ready. The app shell, fonts, and icons are cached; wallet edits continue saving locally when offline. Browser storage may still be cleared or evicted, so retain exported backups.
- New deployments offer an Update now prompt instead of reloading an open form. Dismissed updates remain available in Settings. Updates are checked when returning to the app or reconnecting.

The manifest assumes deployment at the domain root (`/`). `public/_headers` supplies cache headers for Netlify/Cloudflare Pages; configure equivalent rules on other hosts, especially no-cache for `sw.js` and HTML. Serve `manifest.webmanifest` as `application/manifest+json`, serve JavaScript with a JavaScript content type, and route app navigation to `index.html` if adding client-side paths. Do not route API/auth requests to the app shell. Database/auth responses are never cached by the service worker.

See [browser installation guidance](https://web.dev/learn/pwa/installation) and [Vite PWA update handling](https://vite-pwa-org.netlify.app/guide/prompt-for-update).

## Browser checks

With the dev server running on `http://127.0.0.1:5173`, run in a second terminal:

```sh
npx playwright install chromium
npm test
```

The checks run in an isolated browser profile and cover card CRUD, refresh persistence, point calculations and overdraft prevention, voucher redemption, activity, backup restore, invalid imports, expiry rules, and mobile overflow. Screenshots are saved to `artifacts/`. Set `PLAYWRIGHT_CHANNEL=chrome` to use an installed Chrome browser instead of Playwright Chromium.

With the production preview running on port 4173, use `npm run test:pwa` to check the manifest, icon dimensions, offline reload/edits, cached fonts, installation UI, and iPhone guidance. `npm run test:db` runs the SQL checks without any database credentials or external server. `npm run icons` regenerates home-screen PNGs from the existing Perkify vector mark.
