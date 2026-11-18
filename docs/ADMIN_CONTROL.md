# Admin Control - Approval, Kill-Switch & Device Limit

Ruby Invoice has a **Super Admin master control** built on top of
`users/{userId}` documents in Cloud Firestore. This document explains the
data model and the exact console steps to approve, block, renew and
manage devices.

## The data model

When a shop owner registers (Mobile + Business Name + 4-digit PIN), the
app creates this document (the app writes it, you never create it by
hand):

```
users/{uid}
{
  businessName:      "Ruby Garments, Rajkot",
  phone:             "+919876543210",
  pinHash:           "<salted SHA-256 of the Quick PIN>",  // NEVER the plain PIN
  pinSalt:           "<random salt>",
  status:            "pending",      // "pending" | "active" | "blocked"
  expiryDate:        <Timestamp>,    // default = registration + 365 days
  maxDevices:        2,              // default 2
  registeredDevices: ["<device-id-1>"],
  createdAt:         <epoch ms>
}
```

## What the app enforces (automatically, on every launch AND every sync)

1. `status == "active"` - otherwise the app shows
   **"Account Pending Approval - Contact Admin"** (pending) or
   **"Access Locked by Admin"** (blocked).
2. `DateTime.now().isBefore(expiryDate)` - after expiry the app shows
   **"Subscription Expired"** and locks itself.
3. The phone's unique Device ID must be inside `registeredDevices`
   (maximum `maxDevices = 2`). A 3rd device gets
   **"Device Not Authorized"**.
4. A live Firestore listener + a check after every background sync
   means the kill-switch reacts **instantly**, even while the app is
   open. The rules file (`docs/firestore.rules`) additionally makes it
   impossible for a user to flip their own `status`/`expiryDate`.

## Daily admin tasks (Firebase Console, ~10 seconds each)

Open Firebase Console -> Firestore Database -> `users` collection and
click the user's document.

| Task | Edit |
| --- | --- |
| Approve a new user | `status`: `"pending"` -> `"active"` |
| Block a user (kill-switch) | `status`: `"active"` -> `"blocked"` |
| Renew / set subscription | `expiryDate`: set to the new date |
| Remove a device (free a slot) | edit `registeredDevices`, delete the old device-id string |

The app unlocks itself within seconds - no reinstall, no app update.

## One-time setup

1. **Finish the Firebase setup first** (`docs/FIREBASE_SETUP.md`):
   `flutterfire configure`, enable Phone sign-in, create Firestore.
   Until this is done, no UID exists anywhere.
2. **Register once in your own app**: open Ruby Invoice -> Register ->
   enter your mobile number -> verify the OTP -> business name + PIN.
   This creates your account in Firebase.
3. **Copy your UID**: Firebase Console -> **Authentication** -> **Users**
   tab -> find your phone number in the list -> copy the value in the
   **User UID** column (a long string like `xK9dQmT2SfYr5pAbC1vZ...`).
4. **Paste it into the rules**: Firebase Console -> **Firestore
   Database** -> **Rules** tab. In the pasted contents of
   `docs/firestore.rules`, replace the placeholder
   `PASTE_ADMIN_UID_HERE` with your UID so the line reads:
   `&& request.auth.uid == 'xK9dQmT2SfYr5pAbC1vZ...'` (keep the quotes).
   Click **Publish**.
5. **Approve yourself**: Firebase Console -> **Firestore Database** ->
   **users** collection -> open your document -> edit the `status` field
   from `"pending"` to `"active"` -> press Update. (Console edits always
   bypass security rules, so this works immediately.)

Notes:
- The UID in the rules lets an *admin-signed-in client* manage accounts.
  Approving / blocking from the Firebase Console itself always works,
  with or without the UID - the Console runs as a trusted admin.
- One UID per admin. To add a second admin later, extend `isAdmin()` to
  a list: `request.auth.uid in ['<uid-1>', '<uid-2>']`.
- If you register with a different number, that is a NEW UID - repeat
  steps 3-5 for it. To deploy rules via CLI instead:
  `firebase deploy --only firestore:rules`.

## Device IDs

Each device's ID is its Android ANDROID_ID (stable per app-signing key),
shown in **Menu -> Cloud Sync Status -> This device ID**. When a 2nd
phone signs in with the same mobile number, the app adds itself to
`registeredDevices` automatically as long as a slot is free
(`maxDevices` = 2). Two phones of the same shop therefore stay in sync
in real time via `shops/{uid}/...` with zero extra work.

## Offline behaviour

The last known account snapshot is cached on the phone, so offline
launches still enforce the last admin decision (blocked stays blocked).
If the network is away and the cache says "active", the shop can keep
billing offline - data syncs and any status change applies the moment
the device is back online.
