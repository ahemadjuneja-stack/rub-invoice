# Ruby Invoice

Fast, offline-first billing app for Android - built like **Miracle**, in
**Ruby red (#9B111E) + white + black**. Every amount is stored and
calculated in integer paise, so the ledger is mathematically exact.

| | |
|---|---|
| Home | Today + Yesterday bills with day totals, red `+` FAB |
| Customer search | Name / city / phone - type "Rajkot", see every Rajkot customer; add new customers on the spot |
| Billing | 3-slim-column row: **Product \| Qty \| Price**. Type "S" -> instant suggestions. Selecting auto-fills saved qty & price; you can still edit. Numeric keyboard on Qty/Price, normal keyboard on names |
| Inventory | Save products once (name, unit, default qty, price, optional stock tracking + low-stock badge); stock auto-deducts on billing |
| Ledger | Full jama/udhar account per customer: opening balance + every bill (+) and payment (-) with running balance; payments by cash/UPI/bank; "Received now" at billing time |
| Reports | Month-wise sales bars, customer-wise year & all-time totals ("saal me kitna maal liya"), top-selling items |
| Bill PDF | 80mm thermal receipt **and** A5 letterhead (switch in Bill Format); rupee-safe bundled fonts |
| Auth | Mobile + OTP registration (when Firebase is configured) and a 4-digit PIN app lock |
| Sync | 100% offline; when Firebase is configured, two phones with the same number always see the same data (last-write-wins, tombstone deletes) |
| Backup | One-tap JSON export / restore (share to Drive/WhatsApp) |
| Updates | GitHub Releases CI pipeline + in-app "Check Updates"; Shorebird OTA docs included |

## Quick start (one time)

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install).

```bash
bash tool/bootstrap.sh     # generates android/, applies config, icons, deps
flutter run
```

Then for sync + OTP: [docs/FIREBASE_SETUP.md](docs/FIREBASE_SETUP.md).
For pushing to GitHub: [docs/PUSH_GUIDE.md](docs/PUSH_GUIDE.md).
For OTA pipelines: [docs/OTA_UPDATES.md](docs/OTA_UPDATES.md).

## Project structure

```
lib/
  main.dart                 entry: offline DB first, optional Firebase
  app.dart                  theme + AuthGate
  core/                     theme (Ruby palette), money & date formatters
  data/
    db.dart                 SQLite schema (uuid PKs, tombstones, dirty flags)
    models.dart             Customer / Product / Bill / BillItem / Payment
    repo.dart               all queries + ledger math (integer paise only)
  services/
    sync_service.dart       Firestore push/pull sync engine
    pin_service.dart        salted SHA-256 PIN
    pdf_service.dart        80mm + A5 bill PDFs
    backup_service.dart     JSON export/restore
    update_service.dart     GitHub Releases update check
  features/
    auth/                   registration (OTP+PIN) + lock screen
    home/                   bills home + menu grid
    customer/               search + add/edit
    billing/                3-column smart billing screen
    bills/                  bill detail / share / delete
    ledger/                 jama/udhar account + payments
    inventory/              product list + form
    reports/                monthly / customers / top items
    settings/               shop profile + bill format
    backup/                 backup & restore screen
.github/workflows/android.yml   analyze + APK artifact + Release on tags
tool/                           bootstrap.sh, apply_android_config.sh
docs/                           Firebase, OTA, push guides + Firestore rules
assets/icon/                    app icon (R mark + RUBI), adaptive foreground
assets/fonts/                   DejaVu (rupee sign prints correctly in PDFs)
```

## The "zero mistakes" rules

* Amounts are integer **paise** end to end - never `double` arithmetic.
* Line amount = `round(qty x rate)`, total = sum of line amounts.
* Ledger balance = opening + sum(bills) - sum(payments); every row shows
  its running balance so any bill or payment is auditable line by line.
* Day/month grouping uses a local-day key (`2026-11-19`), never UTC, so
  "today" is always your shop's today.

## Roadmap (next iterations)

- GST-ready totals (DB columns already reserved)
- Bluetooth thermal printer direct print
- Bill editing/discount UI, item notes
- Multi-shop support under one login
