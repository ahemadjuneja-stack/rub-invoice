# Key Rotation — Ruby Invoice (v0.4.3)

The release signing key was leaked: the old keystore binary AND its
plaintext passwords (`storePassword = "rubyinvoice"`, alias
`ruby_invoice`) were committed to this PUBLIC repository in 2024
(commit `eb139da`, removed in v0.4.1 but still reachable in history at
commit `83aea2c`). Anyone could have downloaded them, signed a malicious
"update" APK with the same signature, and pushed it to shops.

v0.4.3 rotates the key using Android's official APK Signature Scheme v3
**proof-of-rotation (lineage)** mechanism: the OLD key signs a one-time
permission slip ("I allow the NEW key to take over"), the permission is
committed as `android/lineage`, and every future APK is signed by the
NEW key. Android 9+ devices accept the rotated APK as a normal update
because the lineage proves the chain back to the original key. No
uninstall, no data loss, no Play Store involved.

## What was verified (sandbox, apksigner 0.9 / build-tools 34)

The released `v0.4.2` APK was re-signed with the rotation recipe and
verified at every API band:

| API band | Scheme | Signer | Result |
|---|---|---|---|
| 24-27 (Android 7-8) | v2 | OLD cert (`CN=Ruby Invoice...Surat`) | Verifies - update over old install OK |
| 28-32 (Android 9-12) | v3 + lineage | NEW cert (`CN=Ruby Invoice (rotated 2026)...Bhuj`) | Verifies - update over old install OK |
| 33+ (Android 13+) | v3 | NEW cert | Verifies - update over old install OK |

The delivered proof artifact:
`ruby-invoice-0.4.2-ROTATED-TEST.apk` (the real v0.4.2 APK, rotated
signature applied). Install it OVER your current 0.4.2 to prove the
update path before shipping v0.4.3:

```
adb install -r ruby-invoice-0.4.2-ROTATED-TEST.apk
```

`Success` without any uninstall prompt = lineage works on that device.

## Why `--rotation-min-sdk-version 28`

apksigner 0.9 defaults rotation to the v3.1 block (effective Android 13+)
- that would have left Android 9-12 trusting the leaked old key. The
recipe passes `--rotation-min-sdk-version 28`, so:

* API 24-27: v2 signature from the RETIRED old key (only place the old
  key still has any power - legacy band).
* API 28+: v3 signature from the NEW key only. The leaked old key can
  no longer produce installable updates for Android 9+.

Endgame: raise `minSdk` to 28 when the Android 7/8 fleet is gone - the
old key becomes fully dead.

## Owner setup — GitHub Secrets (one time, ~5 minutes)

The files were delivered in `download/keystore-rotation/`:

| File | What it is |
|---|---|
| `ruby-invoice-v2.keystore` | NEW keystore (PKCS12, RSA 2048, valid 30 years) - KEEP PRIVATE, back it up safely |
| `SECRETS-SETUP.txt` | the NEW keystore password + copy-paste commands - delete after setup |

Five repository secrets (GitHub -> Settings -> Secrets and variables ->
Actions -> New repository secret), with the `gh` CLI from the folder
holding the keystore:

```bash
# 1-4: the NEW (rotated) key - REQUIRED
gh secret set ANDROID_KEYSTORE_BASE64 < <(base64 -w0 ruby-invoice-v2.keystore)
gh secret set ANDROID_KEYSTORE_PASSWORD    # paste password from SECRETS-SETUP.txt
gh secret set ANDROID_KEY_ALIAS            # paste: ruby_invoice
gh secret set ANDROID_KEY_PASSWORD         # same as the store password (PKCS12)

# 5: the RETIRED old keystore - OPTIONAL, only for Android 7/8 updates
gh secret set ANDROID_OLD_KEYSTORE_BASE64 < <(base64 -w0 /tmp/old.keystore)
#   (/tmp/old.keystore = git show 83aea2cd82452b8a5a045a458ae5e5fe07c56785:android/app/ruby-invoice.keystore)
#   its password (rubyinvoice) is a public constant inside the workflow.
```

Secret 5 is OPTIONAL: without it CI still builds (warning), and the APK
is signed new-key-only — Android 9+ keeps updating via the lineage, but
Android 7/8 users would need ONE uninstall+reinstall (all data returns
from cloud sync + backup). With it, every band updates in place.

Then: push any commit -> the CI log must show
"Rotated keystore restored from GitHub Secrets" and the
`=== signature proof (CI log) ===` block with the NEW certificate DN
(`CN=Ruby Invoice (rotated 2026)`).

CI FAILS LOUDLY (`::error::`) if secret 1 is missing — there is no
git-history fallback anymore (removed in v0.4.3).

## Local development

```
cp ruby-invoice-v2.keystore android/app/   # untracked; *.keystore is gitignored
cat > android/key.properties <<EOF
storeFile=ruby-invoice-v2.keystore
storePassword=<from SECRETS-SETUP.txt>
keyAlias=ruby_invoice
keyPassword=<same>
EOF
```

`flutter build apk --release` then produces the gradle-signed APK; for a
distributable one, re-sign exactly like CI does (the two-signer recipe
above) or just install the CI artifact.

## Rotating AGAIN later (to a 3rd key)

```bash
apksigner rotate \
  --in android/lineage \
  --old-signer --ks ruby-invoice-v2.keystore --ks-key-alias ruby_invoice --ks-pass pass:<v2pass> \
  --new-signer --ks ruby-invoice-v3.keystore --ks-key-alias ruby_invoice --ks-pass pass:<v3pass> \
  --out android/lineage-new && mv android/lineage-new android/lineage
```

Commit the grown lineage, add a 6th/7th secret pair, extend the CI sign
step with one more `--next-signer`. The lineage file is public by
design (it ships inside every APK); only the keystores are secrets.

## Device-identity note

The app's device ID (`AccessService.deviceId`, access_service.dart) is
read from `Settings.Secure.ANDROID_ID` ONCE and then persisted in
SharedPreferences. A signing-key rotation changes the OS's ANDROID_ID,
but the app keeps using the value it already stored — so installed
devices keep their `registeredDevices` entry and the admin kill-switch
behaves exactly as before the rotation. Only after Clear Data /
reinstall does a fresh ANDROID_ID appear (and the existing
register / Device-Limit flow handles it).
