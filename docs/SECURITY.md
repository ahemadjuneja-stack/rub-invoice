# Ruby Invoice - Security Audit & Hardening (v0.2.21)

Senior mobile + Firebase security pass over the **Ruby Invoice** Android
app and the **Ruby Key** admin PWA. UI, colours and layouts are
**unchanged** - every control below is rules / build / service layer.

## 1. BOLA / IDOR - server-side row-level security (`firestore.rules` v3)

| Threat | Control |
| --- | --- |
| Cross-account data access | `shops/{uid}/**` read+write requires `request.auth.uid == uid` - strict single-owner isolation, even the admin has no rule path into shop data. |
| Blocked account keeps syncing | `canUseCloud()` denies ALL shop reads+writes when `users/{uid}.status == "blocked"`. |
| Expired subscription keeps syncing | `isExpired()` mirrors the app's `effectiveExpiry` (subscriptionEndDate ?? legacy expiryDate; trialEndDate is ignored since v0.3.0) against `request.time`; expired accounts lose all cloud access server-side. |
| Client edits protected fields | Owner update paths use strict `affectedKeys().hasOnly([...])` whitelists - `status`, `plan`, `maxDevices`, `trialEndDate`, `subscriptionEndDate`, `expiryDate`, `trialStartDate`, `role`, `email` are admin-only (whitelisted Gmail: `Ahemadjuneja@gmail.com`). |
| 3rd device self-registers | Device list updates are append-or-remove only and capped: `registeredDevices.size() <= resource.data.maxDevices` enforced BY THE RULES, so a 3rd device's registration write is rejected server-side. |
| Registration abuse | `users/{uid}` create requires the doc's `email` to match the signed-in Google identity, `plan in ["free", "trial"]` (trial kept for legacy app versions), `maxDevices == 2`, `status in [pending, active]` (active only while `config/app.auto_approve`), no `role` field can be injected. |
| Paid-plan self-activation | `subscriptions/**` create/update/delete is admin-only. The Razorpay webhook (below) is the only automated writer. |

Deploy: Firebase Console -> Firestore Database -> Rules -> paste
`firestore.rules` -> Publish (or `firebase deploy --only firestore:rules`).
`docs/firestore.rules` is kept in sync with the root file.

## 2. Strict upload validation (`storage.rules` v2)

* `shops/{uid}/**` and `users/{uid}/bilty/{fileName}`:
  owner-only uploads, `request.resource.contentType.matches('image/.*')`,
  hard cap **< 2 MB** per file (the app itself compresses photos to
  <= 300 KB client-side). Admin: read + delete for support only.
* Everything else: denied by default.

Deploy: Firebase Console -> Storage -> Rules (or
`firebase deploy --only storage`).

## 3. Input sanitization (XSS defence in depth)

* New `lib/core/sanitize.dart`: strips `<`/`>`, control chars, collapses
  whitespace, caps length; `Sanitize.multiline` keeps address line breaks.
* Wired at the single write choke point `lib/data/repo.dart`
  (customers, products, bills + note, dispatch note, payments,
  purchases, shop profile) and in the registration screen before the
  Firestore account write. The Ruby Key PWA already escapes all user
  fields on output (`esc()`), and now also ships a strict CSP.

## 4. Secrets & local-storage trust

* Secrets scan: only the PUBLIC Firebase web/app config exists in the
  repo (`ruby-key-admin/firebase-config.js`, `google-services.json`) -
  that is safe by design. **No** Razorpay key secrets, service-account
  files or admin credentials anywhere in app/PWA code.
* Trust model: neither SharedPreferences (app) nor localStorage (PWA)
  ever decides subscription validity. The app re-reads
  `users/{uid}` on every launch (live snapshot listener), every sync
  tick (`verifyOnce`) and after every admin kill-switch change; the
  local cache is splash-failsafe only and always superseded by the live
  verdict (see `AccessService._evaluateFromCache`). The PWA has zero
  localStorage security state - documented in `app.js`.
* Known accepted trade-off: the release keystore is committed so CI and
  local builds keep the same signing key (stable Google sign-in
  fingerprints). Move it to CI secrets if the repo is ever shared.

## 5. Firebase App Check (ready)

* `main.dart` activates App Check: **Play Integrity** in release,
  **debug** provider in dev. Failures never block boot.
* Console enforcement is intentionally left OFF for now: start in
  *monitor* mode (App Check -> Metrics), verify real devices pass, then
  flip "Enforce" for Firestore + Storage. Play Integrity scores
  sideloaded APKs conservatively - confirm in monitor mode first
  (this app ships via GitHub Releases, not the Play Store).

## 6. Production hygiene

* All 30 debug logs moved to `lib/core/app_log.dart` (`appLog`) -
  `kDebugMode` is a compile-time constant, so release builds print
  NOTHING to Logcat (customer names, phones and sync errors can no
  longer leak).
* Android: `minifyEnabled` + `shrinkResources` + R8 obfuscation with
  safe keep-rules (`android/app/proguard-rules.pro` covers Flutter,
  Firebase/Play Services, gRPC/protobuf, sqflite). CI uploads
  `mapping.txt` with the build for crash symbolication.
* PWA: strict CSP (no inline scripts - SW registration moved into
  `app.js`; all endpoints pinned to Google/Firebase origins) +
  `referrer: no-referrer`.

## 7. Razorpay webhook readiness (`server/razorpay-webhook/`)

* Isolated Cloud Function verifying `x-razorpay-signature` =
  `HMAC_SHA256(RAZORPAY_WEBHOOK_SECRET, raw_body)` (timing-safe
  compare) before extending `subscriptionEndDate`, setting
  `plan: "paid"` and writing the `subscriptions` ledger row.
* The secret lives ONLY in the function's secret store
  (`firebase functions:secrets:set`) - never in the app, never in git.
* Plan catalogue + prices live server-side (`PLANS` in `index.js`).
  Setup steps: `server/razorpay-webhook/README.md`.

## Honest limitation (device identity)

Firestore rules cannot see WHICH physical device made a request - the
2-device limit is enforced server-side at registration
(`registeredDevices` growth capped by rules) and at runtime by the app's
live access check (an unregistered 3rd device is locked within seconds
of signing in). Binding the device identity into the token itself
requires custom claims minted by a server (the Razorpay function is the
future home for that). App Check + the rules above close the
script/bot/replay surface meanwhile.

## 8. Signing keys - ROTATED, history fallback REMOVED (v0.4.3)

The old keystore + passwords WERE public in git history (commit
`83aea2c`), so v0.4.3 **rotated** to a new key with Android v3
proof-of-rotation (lineage `android/lineage`, committed - public by
design). Every API band was verified in sandbox (see
`docs/KEY_ROTATION.md`):

* API 24-27: v2 by the RETIRED old key (optional 5th secret) -
  Android 7/8 keep in-place updates.
* API 28+: v3 by the NEW key only - the leaked old key is dead there.

How signing works now:

* **Locally** - keep `ruby-invoice-v2.keystore` + `android/key.properties`
  on disk (both gitignored).
* **CI** - 5 GitHub Actions Secrets (4 required, 1 optional):
  | Secret | Value |
  |---|---|
  | `ANDROID_KEYSTORE_BASE64` | base64 of the NEW keystore (required) |
  | `ANDROID_KEYSTORE_PASSWORD` | new keystore password (required) |
  | `ANDROID_KEY_ALIAS` | `ruby_invoice` (required) |
  | `ANDROID_KEY_PASSWORD` | same as store password, PKCS12 (required) |
  | `ANDROID_OLD_KEYSTORE_BASE64` | old keystore binary (optional, Android 7/8 band) |
* **NO git-history fallback** - CI exits `::error::` when the required
  secrets are missing. Full steps: `docs/KEY_ROTATION.md`.

### Owner actions (one time, ~5 minutes)

DONE as v0.4.3 - the rotation itself is complete. What remains is the
one-time GitHub Secrets setup (new keystore delivered in
`download/keystore-rotation/`): see the "Owner setup" section of
`docs/KEY_ROTATION.md`. Then confirm the CI log prints the NEW
certificate DN (`CN=Ruby Invoice (rotated 2026)`) in the signature
proof block.

### mapping.txt

R8 obfuscates the Java/Kotlin glue; every CI build archives
`build/app/outputs/mapping/**/mapping.txt` as the `mapping-txt`
artifact. Keep it for every release: Crashlytics uses it to de-obfuscate
native stack traces. (Flutter Dart errors carry readable Dart symbols -
no mapping needed there.)

## Keystore off the repo (v0.4.1, SUPERSEDED by the v0.4.3 rotation)

HISTORY of the old guidance - kept for the audit trail. The current,
authoritative setup is section 8 above + `docs/KEY_ROTATION.md`.

Until v0.4.0 the release signing key WAS committed
(`android/app/ruby-invoice.keystore`, passwords inside
`android/app/build.gradle.kts`). Anyone with repository access could
sign an APK that Android would accept as a legitimate update for every
existing install. v0.4.1 removed it; v0.4.3 ROTATED to a new key via
v3 lineage and deleted the interim git-history fallback.

(The old passwords were `rubyinvoice` / alias `ruby_invoice` - they
were public in old commits, which is exactly why the key had to be
rotated, not just removed.)

### Rotating the key (DONE in v0.4.3)

The key was rotated with apksigner lineage (old -> new, effective from
API 28) - see `docs/KEY_ROTATION.md` for the recipe, the verified API
bands and the re-rotation procedure for a future 3rd key.

### Purging the history (optional, destructive)

The old keystore binary stays reachable in git history until rewritten.
Since v0.4.3 the old key is worthless on API 28+ (lineage rotation) and
CI no longer reads history - a purge is pure hygiene for the Android 7/8
band:

```
pip install git-filter-repo
git clone --mirror git@github.com:ahemadjuneja-stack/rub-invoice.git
cd rub-invoice.git
git filter-repo --path android/app/ruby-invoice.keystore --invert-paths
git push --force --all && git push --force --tags
```

Set the 5 secrets FIRST, coordinate every clone, and remember old
clones keep the blob locally.
