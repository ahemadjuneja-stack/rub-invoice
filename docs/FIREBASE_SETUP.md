# Firebase Setup (sync + Google login)

Ruby Invoice is **offline-first**: it works 100% without Firebase. Completing
this setup switches on (a) Google (Gmail) sign-in registration and (b)
automatic sync, so the same Google account used on two devices sees the same
data.

> Login is **Google-based, no SMS**. Phone/OTP login was removed because
> SMS delivery in India is unreliable (delays, carrier filtering, daily
> quota). Google sign-in is instant and free.

> **LOGIN IS CURRENTLY DISABLED** during the build phase:
> `lib/app.dart` has `kLoginEnabled = false`, which opens the app straight
> to the HomeScreen (no sign-in, no PIN, no admin gate). To re-enable the
> full login flow later, set that constant back to `true` - no other code
> change is needed. This document describes the Google sign-in setup to
> complete when login comes back.

## 1. Create the Firebase project

1. Go to <https://console.firebase.google.com> and click **Add project**.
2. Name it e.g. `ruby-invoice` and continue (Analytics optional).

## 2. Install the FlutterFire CLI (one time)

```bash
dart pub global activate flutterfire_cli
```

## 3. Link the app and generate real config

From the `ruby_invoice` project folder:

```bash
flutterfire configure
```

- Select the `ruby-invoice` project.
- Select platforms: **android** (add ios/web later if you want).
- The CLI writes **`lib/firebase_options.dart`** with your real keys and
  registers the Android app (package id: `com.rubyinvoice.ruby_invoice`).
  This replaces the stub file in the repo - nothing else to change.

Commit the new `lib/firebase_options.dart` and push. The app now detects
"Firebase configured" on next launch.

## 4. Enable Google sign-in (no SMS anywhere)

1. Firebase console -> **Authentication** -> **Sign-in method** ->
   **Add a new provider** -> **Google** -> **Enable** -> choose your own
   Gmail as the project support email -> **Save**.
2. Add the app fingerprints (REQUIRED for Google sign-in):
   Project settings (gear) -> **General** -> **Your apps** -> the Android
   app (`com.rubyinvoice.ruby_invoice`) -> **Add fingerprint** -> paste
   the release **SHA-1**, save; again with the **SHA-256**.
3. On the same page click **Download google-services.json** and commit
   the refreshed file to `android/app/google-services.json` in the repo
   (GitHub web: `android/app` folder -> Add file -> Upload files ->
   commit). The refreshed file contains the OAuth client Google sign-in
   needs - without it sign-in fails with error code 10.

## 5. Create the Firestore database

Firebase console -> **Firestore Database** -> **Create database** ->
production mode -> pick a region close to you (e.g. `asia-south1`).

Then open the **Rules** tab and paste the contents of
[`docs/firestore.rules`](firestore.rules):

```
match /shops/{shopId}/{document=**} {
  allow read, write: if request.auth != null
                     && request.auth.uid == shopId;
}
```

This guarantees every shop can only ever touch its own data.

## 6. How sync works (design notes)

Data model - one document tree per shop:

```
shops/{uid}/customers/{uuid}
shops/{uid}/products/{uuid}
shops/{uid}/bills/{uuid}          <- items embedded as `items: []`
shops/{uid}/payments/{uuid}
```

* **Offline-first**: SQLite is the source of truth; the app never blocks
  on the network.
* **Push**: rows flagged `dirty = 1` are batch-written to Firestore
  (up to 400 ops per batch) and the flag clears on success.
* **Pull**: every 2 minutes, on connectivity regain, after login and
  after every save, rows with `updated_at > last_sync_ms` are fetched.
* **Last-write-wins**: a remote row is applied only when its
  `updated_at` is strictly newer than the local one, so the same bill
  edited on two devices converges to the newest version.
* **Deletes** are tombstones (`is_deleted = 1`), so deletions propagate.
* **Two devices, one shop**: sign in with the SAME Google account on
  both phones -> same Firebase uid -> same `shops/{uid}` tree -> both
  apps always show the same data.

## 7. Verify

1. `flutter run` on device A -> register with Gmail, set PIN.
2. Install on device B -> register with the SAME Google account.
3. Make a bill on A -> within a few seconds it appears on B.
