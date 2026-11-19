# Ruby Invoice

Fast, offline-first billing app for Android - built like **Miracle**, in
**Ruby red (#9B111E) + white + black**. Every amount is stored and
calculated in integer paise via the `decimal` package, so the ledger is
mathematically exact - **0% rounding or floating-point error**.

| | |
|---|---|
| Home (Billing tab) | Today + Yesterday bills with day totals, red `+` FAB |
| Customer search | Name / city / phone - type "Rajkot", see every Rajkot customer; add new customers on the spot |
| Billing | 3-slim-column row: **Product (3) \| Qty (1) \| Price (1)**. Type "S" -> instant suggestions. Selecting auto-fills saved qty & price and jumps focus to Qty; "Done" adds the row and resets to Product. Numeric keypad on Qty/Price, normal keyboard on names. Credit/Udhar vs Cash/Jama one-tap toggle, bold **SAVE & PRINT / PDF** |
| Inventory | Item Master (name, unit, default qty, sale price, opening/current stock, low-stock badge); stock auto-deducts on billing |
| Ledger | Full jama/udhar account per customer with running balance. **FIFO settlement**: Receive Payment (Jama) settles the OLDEST bills first and every bill shows SETTLED / PARTIAL - DUE / UNPAID - exactly, paisa by paisa |
| Reports | Calendar Year, **Financial Year (Apr-Mar)** and single Month filters; monthly bars + daily drill-down, customer-wise and item-wise purchases for any period |
| Bill PDF | 80mm thermal receipt **and** A5 letterhead (switch in Bill Format); share straight to WhatsApp; rupee-safe bundled fonts |
| Admin control | Ruby Key web admin panel + Firestore rules: approval (`pending -> active`), kill-switch (`blocked`), 7-day trial / `subscriptionEndDate`, max **2 devices** per account with device IDs + model names. Locks instantly, even mid-session |
| Auth | **Google login only** (no SMS/OTP): logo + Continue with Google -> account check -> Business Registration (shop, owner, 10-digit mobile, city, address, GST) -> 7-day trial -> Quick PIN. Lock screens offer WhatsApp/Email support, renew contact and self-serve device removal |
| Sync | 100% offline-first (SQLite source of truth); with Firebase, two phones of the same shop stay identical (last-write-wins, tombstone deletes, `persistenceEnabled: true`) **including photos**: bilty / payment-proof / purchase-bill images sync via Cloud Storage, compressed to <= 300 KB client-side; billty photos honour the 45-day auto-delete rule everywhere |
| Cloud Sync Status | "All Data Synced" / "Offline Mode - Pending Sync" screen with pending count, last sync, device slots and SYNC NOW |
| Backup | One-tap JSON export / restore (share to Drive/WhatsApp) |
| Updates | GitHub Releases CI pipeline + in-app "Check Updates"; Shorebird OTA docs included |

## Quick start (one time)

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install).

```bash
bash tool/bootstrap.sh     # generates android/, applies config, icons, deps
flutter run
```

Then for login + sync + photos + admin panel: [docs/FIREBASE_SETUP.md](docs/FIREBASE_SETUP.md)
and [docs/ADMIN_CONTROL.md](docs/ADMIN_CONTROL.md).
For pushing to GitHub: [docs/PUSH_GUIDE.md](docs/PUSH_GUIDE.md).
For OTA pipelines: [docs/OTA_UPDATES.md](docs/OTA_UPDATES.md).

## Ruby Key - admin panel (web PWA)

`ruby-key-admin/` is the separate dark-mode admin panel (same logo,
installable via Chrome "Add to Home screen"):

* Login with the owner's Gmail ONLY (`Ahemadjuneja@gmail.com` whitelist -
  enforced in the UI **and** in `firestore.rules`); anyone else sees
  **Unauthorized Access** and is signed out.
* Live cards: Total Users / Active Trials / Paid Subs / Expired / Blocked.
* Search by shop, owner, mobile, city or email; per-user details with
  devices `n/2` + model names, **Block / Unblock** (instant kill switch),
  **Extend Validity** (+30 days / +1 year / custom date - writes the
  Razorpay-ready `subscriptions` ledger), **Reset Devices**, and direct
  **WhatsApp / Call** buttons.
* Reads/manages ONLY `users` + `subscriptions` - never the private
  `shops/{uid}` billing data.

Deployed automatically to GitHub Pages by
[.github/workflows/admin-pages.yml](.github/workflows/admin-pages.yml)
(setup steps in the [admin README](ruby-key-admin/README.md)).

## Project structure

```
lib/
  main.dart                 entry: offline DB first, optional Firebase (persistence on)
  app.dart                  theme + AuthGate
  core/                     theme (Ruby palette), money & date formatters
  models/
    models.dart             Customer / Product / Bill / BillItem / Payment
    settlement.dart         FIFO bill settlement engine (pure functions)
  data/
    db.dart                 SQLite schema (uuid PKs, tombstones, dirty flags)
    repo.dart               all queries + ledger math (integer paise only)
  services/
    access_service.dart     Google account / 7-day trial / kill-switch / 2-device limit
    sync_service.dart       Firestore push/pull sync engine
    photo_sync_service.dart bilty/proof/purchase photos -> Cloud Storage (<= 300 KB, 45-day billty rule)
    pin_service.dart        salted SHA-256 Quick PIN (cross-device)
    pdf_service.dart        80mm + A5 bill PDFs
    backup_service.dart     JSON export/restore
    update_service.dart     GitHub Releases update check
  screens/
    auth/                   login (Continue with Google), business registration, legal pages, access gate, PIN lock
    lock/                   Pending Approval + Access Locked (WhatsApp support, renew, device removal)
    home/                   bills home + menu grid
    customer/               search + add/edit
    billing/                3-column smart billing screen
    bills/                  bill detail / share / delete
    ledger/                 jama/udhar account + FIFO status chips
    inventory/              product list + form
    reports/                year / FY / month reports
    sync/                   Cloud Sync Status screen
    settings/               shop profile + bill format, business profile, subscription
    backup/                 backup & restore screen
  widgets/                  shared widgets (SyncChip, dialogs, headers)
test/                       30 tests: money math, FIFO settlement, access rules
.github/workflows/          android.yml (APK + releases), admin-pages.yml (Ruby Key site)
tool/                       bootstrap.sh, apply_android_config.sh
docs/                       Firebase / admin / OTA / push guides
firestore.rules             strict per-user rules + admin Gmail whitelist
storage.rules               photo rules (owner-only, 300 KB image cap)
ruby-key-admin/             Ruby Key admin PWA (dark, installable, separate from app data)
assets/icon/                app icon (R mark + RUBY INVOICE), adaptive foreground
assets/fonts/               DejaVu (rupee sign prints correctly in PDFs)
```

## The "zero mistakes" rules

* Amounts are integer **paise** end to end; text->paise and qty x rate
  conversions run through the **`decimal` package** - never `double`
  arithmetic.
* Line amount = `round(qty x rate)` with exact decimals, total = sum of
  line amounts.
* Ledger balance = opening + sum(bills) - sum(payments); every row shows
  its running balance so any bill or payment is auditable line by line.
* FIFO settlement is computed from the books, never stored, so it can
  never drift: `sum(payments) == allocated + advance` (tested).
* Day/month/FY grouping uses local day keys (`2026-11-19`), never UTC,
  so "today" is always your shop's today.

## Roadmap (next iterations)

- GST-ready totals (DB columns already reserved)
- Bluetooth thermal printer direct print
- Bill editing/discount UI, item notes
- Multi-shop support under one login
