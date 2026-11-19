# Ruby Key - Admin Panel (PWA)

Dark, mobile-first admin panel for **Ruby Invoice**. Installable from
mobile Chrome via **Add to Home Screen** (full-screen, standalone).

Uses the SAME Firebase project as the Android app (`ruby-invoice-c17bd`)
and the SAME app logo. It reads/manages ONLY the `users` and
`subscriptions` collections - shop invoices, ledger and bilty photos
(`shops/{uid}/**`) are never shown here.

## Features

- **Login:** Continue with Google ONLY - any Gmail other than the
  admin whitelist is signed out instantly with "Unauthorized Access"
  (UI check + Firestore rules double-enforcement).
- **Live overview cards:** Total Users, Active Trials, Paid Subs,
  Expired, Blocked - updated in REAL TIME (Firestore snapshots).
- **User list** with search by shop name / owner / mobile / city / email.
- **Per-user controls:**
  - View full shop details (address, GST, trial dates, validity).
  - Devices `n/2` with model names + Remove single device / Reset all.
  - **Block / Unblock** - instant real-time kill switch.
  - **Extend Validity:** +30 days, +1 year, or a custom date. Writes
    `plan: paid`, `status: active`, `subscriptionEndDate` and adds a
    row to `subscriptions` (Razorpay-ready schema).
  - **WhatsApp & Call** buttons next to the mobile number.

## One-time setup

1. **Register a Web app in Firebase**
   Console -> Project settings -> General -> Your apps -> **Web** `</>`
   -> nickname "Ruby Key" -> copy the `appId` into
   `firebase-config.js` (`PASTE_WEB_APP_ID_HERE`).
2. **Enable Google sign-in** (already needed by the Android app):
   Authentication -> Sign-in method -> Google -> Enable.
3. **Add the admin domain to Firebase Auth:**
   Authentication -> Settings -> **Authorized domains** -> add the
   domain where this PWA is hosted, e.g.
   `ahemadjuneja-stack.github.io`.
4. **Deploy to GitHub Pages (automatic):** the workflow
   `.github/workflows/admin-pages.yml` publishes this folder on every
   push to `main`. Enable it once:
   Repo **Settings -> Pages -> Source: GitHub Actions**, then open
   `https://ahemadjuneja-stack.github.io/rub-invoice/`.
5. **Deploy the security rules** (`docs/FIREBASE_SETUP.md`): the
   `users` / `subscriptions` / admin-email rules make sure ONLY the
   admin Gmail can list and manage accounts, even if someone copies
   the panel.
6. **Install on your phone:** open the URL in Chrome ->
   menu -> **Add to Home screen** -> "Ruby Key".

## Files

| File | Purpose |
| --- | --- |
| `index.html` | App shell (login / unauthorized / dashboard views) |
| `app.js` | All admin logic (login gate, live list, actions) |
| `styles.css` | Dark Ruby-branded theme |
| `firebase-config.js` | Firebase web config + admin email whitelist |
| `manifest.json` | PWA manifest (icon, standalone, colors) |
| `sw.js` | Service worker (offline shell cache) |
| `icons/` | App logo 192/512 |
