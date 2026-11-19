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
| Admin control | Super Admin master switch in Firestore: approval (`pending -> active`), kill-switch (`blocked`), subscription `expiryDate`, max **2 devices** per account with unique Device IDs. Locks instantly, even mid-session |
| Auth | Mobile + OTP registration (Firebase mode) + Business Name + 4-digit Quick PIN; the PIN syncs to the 2nd device |
| Sync | 100% offline-first (SQLite source of truth); with Firebase, two phones of the same shop stay identical (last-write-wins, tombstone deletes, `persistenceEnabled: true`) |
| Cloud Sync Status | "All Data Synced" / "Offline Mode - Pending Sync" screen with pending count, last sync, device slots and SYNC NOW |
| Backup | One-tap JSON export / restore (share to Drive/WhatsApp) |
| Updates | GitHub Releases CI pipeline + in-app "Check Updates"; Shorebird OTA docs included |

## Quick start (one time)

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install).

```bash
bash tool/bootstrap.sh     # generates android/, applies config, icons, deps
flutter run
```

Then for sync + OTP + admin control: [docs/FIREBASE_SETUP.md](docs/FIREBASE_SETUP.md)
and [docs/ADMIN_CONTROL.md](docs/ADMIN_CONTROL.md).
For pushing to GitHub: [docs/PUSH_GUIDE.md](docs/PUSH_GUIDE.md).
For OTA pipelines: [docs/OTA_UPDATES.md](docs/OTA_UPDATES.md).

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
    access_service.dart     admin approval / kill-switch / device limit
    sync_service.dart       Firestore push/pull sync engine
    pin_service.dart        salted SHA-256 Quick PIN (cross-device)
    pdf_service.dart        80mm + A5 bill PDFs
    backup_service.dart     JSON export/restore
    update_service.dart     GitHub Releases update check
  screens/
    auth/                   registration (mobile + business + OTP + PIN), access gate, PIN lock
    lock/                   Pending Approval + Access Locked screens
    home/                   bills home + menu grid
    customer/               search + add/edit
    billing/                3-column smart billing screen
    bills/                  bill detail / share / delete
    ledger/                 jama/udhar account + FIFO status chips
    inventory/              product list + form
    reports/                year / FY / month reports
    sync/                   Cloud Sync Status screen
    settings/               shop profile + bill format
    backup/                 backup & restore screen
  widgets/                  shared widgets (SyncChip, dialogs, headers)
test/                       30 tests: money math, FIFO settlement, access rules
.github/workflows/android.yml   analyze + APK artifact + Release on tags
tool/                       bootstrap.sh, apply_android_config.sh
docs/                       Firebase, ADMIN_CONTROL, OTA, push guides + Firestore rules
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
