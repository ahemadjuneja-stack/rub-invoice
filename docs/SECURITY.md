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

## 8. Signing keys are NOT in the repo (v0.4.1)

`android/app/ruby-invoice.keystore` and the hard-coded
`storePassword/keyPassword` were REMOVED from the repository
(`git rm --cached`; `.gitignore` covers `*.keystore`, `*.jks`,
`android/key.properties`).

How signing works now:

* **Locally** - keep `android/app/ruby-invoice.keystore` on disk (it is
  untracked) and `android/key.properties` (gitignored) with:
  `storeFile / storePassword / keyAlias / keyPassword`.
* **CI** - the workflow restores the keystore from GitHub Actions
  Secrets before `flutter build apk`:
  | Secret | Value |
  |---|---|
  | `ANDROID_KEYSTORE_BASE64` | `base64 -w0 ruby-invoice.keystore` output |
  | `ANDROID_KEYSTORE_PASSWORD` | keystore password |
  | `ANDROID_KEY_ALIAS` | `ruby_invoice` |
  | `ANDROID_KEY_PASSWORD` | key password |
* **Interim fallback** - until the secrets are set once, CI extracts
  the same keystore + values from git history (commit `9454a36`) so
  every APK stays update-compatible with current installs. The workflow
  prints a warning while this fallback is active.

### Owner actions (one time, ~3 minutes)

1. `base64 -w0 android/app/ruby-invoice.keystore` -> paste into
   Settings -> Secrets and variables -> Actions as
   `ANDROID_KEYSTORE_BASE64`; add the other three secrets.
2. Push any commit -> confirm the build log says
   "Signing with the keystore from GitHub Secrets".
3. **Rotate the key later** (recommended, plan it): the old password
   was public in git history, so the safest endgame is a NEW keystore +
   a versioned migration note (users reinstall once - data returns
   from cloud sync + JSON backup). History rewriting
   (`git filter-repo`) is optional and breaks the interim fallback.

### mapping.txt

R8 obfuscates the Java/Kotlin glue; every CI build archives
`build/app/outputs/mapping/**/mapping.txt` as the `mapping-txt`
artifact. Keep it for every release: Crashlytics uses it to de-obfuscate
native stack traces. (Flutter Dart errors carry readable Dart symbols -
no mapping needed there.)

## Keystore off the repo (v0.4.1, setup guide)

Until v0.4.0 the release signing key WAS committed
(`android/app/ruby-invoice.keystore`, passwords inside
`android/app/build.gradle.kts`). Anyone with repository access could
sign an APK that Android would accept as a legitimate update for every
existing install. v0.4.1 removes it:

- `android/app/ruby-invoice.keystore` is untracked; `.gitignore`
  covers `*.keystore`, `*.jks` and `android/key.properties`.
- `android/app/build.gradle.kts` reads signing values from
  `android/key.properties` (gitignored). If that file is missing the
  release build falls back to the DEBUG key and prints a loud warning:
  such an APK installs fresh but CANNOT update an existing signed
  install - do not distribute it.
- CI writes `key.properties` from the 4 GitHub Actions secrets and
  decodes the keystore binary. While the secrets are not set yet, CI
  restores the SAME key + values from the last historical commit that
  contained them (interim fallback, emits a `::warning::`) so every
  APK stays update-compatible.

### One-time setup (the owner, 2 minutes)

Local machine, repo root:

```
base64 -w0 android/app/ruby-invoice.keystore > /tmp/ks.b64
cat android/app/build.gradle.kts | grep -E 'storePassword|keyPassword|keyAlias' || true
```

(The old passwords were `rubyinvoice` / alias `ruby_invoice` - they
were public in old commits, which is exactly why the binary itself had
to leave the repo.)

GitHub -> this repo -> Settings -> Secrets and variables -> Actions ->
New repository secret, four entries:

| Secret name | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | full contents of `/tmp/ks.b64` (one long line) |
| `ANDROID_KEYSTORE_PASSWORD` | the keystore password (storePassword) |
| `ANDROID_KEY_ALIAS` | the key alias |
| `ANDROID_KEY_PASSWORD` | the key password (keyPassword) |

(With the `gh` CLI:
`gh secret set ANDROID_KEYSTORE_BASE64 < /tmp/ks.b64` etc.)
Delete `/tmp/ks.b64` afterwards.

### Rotating the key (recommended, scheduled)

The old password values were public in git history, so the honest
posture is: keep using the old key ONLY while it is required for
update compatibility, and plan a rotation (new keystore + new
certificate) for the moment you can coordinate a fresh install for
every shop - rotation breaks the in-place upgrade path, so schedule it
consciously.

### Purging the history (optional, destructive)

The keystore binary stays reachable in git history until rewritten:

```
pip install git-filter-repo
git clone --mirror git@github.com:ahemadjuneja-stack/rub-invoice.git
cd rub-invoice.git
git filter-repo --path android/app/ruby-invoice.keystore --invert-paths
git push --force --all && git push --force --tags
```

Set the 4 secrets FIRST (the interim fallback stops working after a
history rewrite), coordinate every clone, and remember old clones keep
the blob locally.
