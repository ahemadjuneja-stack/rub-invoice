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

1. Get your admin UID: Firebase Console -> Authentication -> Users ->
   copy the UID of your own (admin) account.
2. Open `docs/firestore.rules`, replace `PASTE_ADMIN_UID_HERE` with that
   UID, and publish the rules (Console -> Firestore -> Rules).
3. Deploy the same file with the CLI if you prefer:
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
