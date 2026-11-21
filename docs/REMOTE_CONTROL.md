# Remote Control (WhatsApp-style, no-update changes)

The app watches one Firestore document: **`config/app`**. Edit it from the
Firebase Console on your phone and every installed app picks the change up
within seconds - no new APK needed.

## Create the document (one time)

Firebase Console -> Firestore Database -> Start collection:

- Collection ID: `config`
- Document ID: `app`
- Add fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `notice` | string | Yellow announcement banner on the Billing tab. Empty string = hidden. |
| `min_version` | string | Force-update gate. If the installed version is older, the app opens a non-dismissable update screen with background download + Install. Empty string = off. |
| `features` | map | Per-feature on/off switches. Any key not listed = ON. |
| `auto_approve` | boolean | When `true` (default, also when the doc/field is missing) new registrations activate themselves instantly - no admin step. Set `false` to make every new account wait for admin approval. |

## Feature keys

`inventory`, `ledger`, `reports`, `backup`

(Menu tiles / list entries are hidden when the key is `false`.)

## Examples

Hide Reports and Backup for everyone, show a notice:

```
notice:      "GST bill format is live! Update from Menu -> Check Updates."
min_version: ""
features:    { reports: false, backup: false }
```

Force everyone below v0.3.0 to update (the app downloads the APK in the
background and shows a single Install button):

```
min_version: "0.3.0"
```

Clear everything:

```
notice: "", min_version: "", features: {}
```

## Security

`docs/firestore.rules` includes a `config/{doc}` block: every client can
read (flags hold no private data, and they apply even before sign-in),
only the Admin UID can write. Publish the rules once after adding it.
The Firebase Console document editor always bypasses rules, so the admin
can edit `config/app` even from a fresh phone.

## Ruby Key panel - Remote Control card (the easy way)

You do NOT need the Firebase Console anymore. Open **Ruby Key**
(`https://ahemadjuneja-stack.github.io/rub-invoice/` on
your phone), log in with the admin Gmail and tap the **REMOTE CONTROL**
card. The form saves straight to `config/app` and every installed app
picks the change up within seconds:

| Control | What it does |
| --- | --- |
| Announcement banner | Yellow notice on the Billing tab. Empty = hidden. |
| Force-update gate (min version) | Phones older than this version MUST update - the app opens a non-dismissable update popup with background download. |
| Support WhatsApp number | 10 digits - the lock screens (blocked/expired/device limit) show a WhatsApp Support button instead of email. |
| Ledger / Inventory / Reports / Backup switches | Hide/show those menu tiles for everyone. |
| Auto-approve new shops | ON = new registrations start billing instantly; OFF = they wait for your approval. |

Saving works even when the document does not exist yet (it is created
with merge). The Firestore rules allow only the admin Gmail to write
`config/{doc}` - every other account can only read.

## New field: `support_mobile`

`support_mobile` (string, 10-digit Indian number, empty = off). The app
prefers the remote value over the compile-time constant; when empty the
lock screens keep showing the Gmail button.

## Update-check reliability (v0.2.18)

The in-app update check now falls back to the rate-limit-free
`releases.atom` feed + `expanded_assets` scrape when the GitHub REST
API is rate-limited (60 req/hour per IP), and every request has a
12-second timeout. If the system installer cannot open (missing
"Install unknown apps" permission - it resets after Clear Data), the
popup shows a one-permission guide plus a "Download in browser" escape.

## v0.4.0: LIVE UI CONTROL (`app_config/live_ui`)

The Ruby Key panel's **LIVE UI CONTROL** card writes the Firestore
document `app_config/live_ui`. Every installed phone listens to it
live (Firebase snapshots) and applies changes within seconds - no
APK, no Play Store, no update. The last-known document is cached in
SharedPreferences (`live_ui_cache_v1`) so offline starts keep the
same UI, and every field has a safe default.

| Field | Type | Default | Effect on the app |
|---|---|---|---|
| `maintenance_mode` | bool | false | Full-screen maintenance gate; the admin Gmail always passes. |
| `enable_bilty_upload` | bool | true | Billty (lorry receipt) photo capture on the delivery sheet. |
| `enable_gst_fields` | bool | true | Per-line GST inputs on purchase + purchase-return forms. |
| `enable_razorpay_banner` | bool | false | Online-payments offer banner on the home Billing tab (user can dismiss for the day). |
| `enable_pdf_share` | bool | true | Share-PDF buttons (bill view + ledger statement). |
| `banner.enabled/text/bg/fg` | map | off | Announcement banner at the top of the Billing tab, hex colours. |
| `primary_color` | string | - | Hex colour of the home + button (empty = theme red). |
| `primary_label` | string | '' | Label of the home button (empty = classic + icon FAB). |
| `shortcuts` | list | [] | Admin-defined menu cards: `{id,label,icon,color,action,visible}`. |

Shortcut `action` formats: `open:billing|customers|ledger|inventory|
purchases|returns|accounts|backup|sync|settings|pdfformat`,
`url:https://...`, `dial:number`, `none`.

Rules: `match /app_config/{docId}` - public read (no private data),
admin write only (same trust level as `config/{docId}`). A malformed
row, unknown icon or broken link can never break the app - the parser
skips bad rows and unknown actions fall back safely.
