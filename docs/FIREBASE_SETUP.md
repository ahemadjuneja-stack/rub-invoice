# Firebase Setup (login, sync, bilty photos, Ruby Key admin)

Ruby Invoice is **offline-first**: it works 100% without Firebase.
Completing this setup switches on:

1. **Google login** (Continue with Google, no SMS/OTP anywhere)
2. **Cloud sync** of customers, bills, ledger, inventory + **photos**
3. **The 7-day trial / subscription access system**
4. **Ruby Key** - the web admin panel (block / extend / reset devices)

> The Firebase project `ruby-invoice-c17bd` is ALREADY created and the
> Android app already ships with `google-services.json`. The steps below
> only add what is new in v0.2.16.

## 1. Paste the new security rules (REQUIRED)

The rules moved to the repo ROOT and now protect the new features:

* [`firestore.rules`](../firestore.rules) - users / shops / subscriptions
* [`storage.rules`](../storage.rules) - photos with a 300 KB upload cap

**Firestore:** console -> Firestore Database -> **Rules** -> paste the
full contents of `firestore.rules` -> **Publish**.

**Storage:** you must enable Storage first (console -> **Storage** ->
Get started -> production mode, region `asia-south1`). Then Storage ->
**Rules** -> paste `storage.rules` -> **Publish**.

The admin is whitelisted by Gmail (`Ahemadjuneja@gmail.com`) inside the
rules themselves - no UID pasting needed. To change the admin Gmail
later, edit the email in both rule files.

## 2. Google sign-in check (one time)

1. Authentication -> **Sign-in method** -> **Google** must be **Enabled**.
2. Project settings -> General -> Your apps -> Android app ->
   the release **SHA-1 / SHA-256** fingerprints are added (already done
   if Google login worked before).

## 3. How login works now (v0.2.16)

```
Login screen (logo + Continue with Google)
   -> users/{uid} exists?  -> straight into the app (PIN -> Home)
   -> users/{uid} MISSING? -> Business Registration screen
        Shop name*, Owner name*, Mobile (10 digits)*,
        Email (read-only from Google), City*, Address*, GST (optional)
        + 4-digit Quick PIN
   -> account created: status "active", plan "trial",
      trialStartDate: now, trialEndDate: now + 7 days,
      maxDevices: 2, activeDevices: [this phone]
   -> straight to the dashboard - NO waiting screen
```

The live `users/{uid}` listener locks the app INSTANTLY when the Admin
blocks the account ("Account Suspended" + WhatsApp/Email support
button), when validity passes ("Subscription Expired" + Renew button),
or when a 3rd device signs in ("Device Limit Reached" - the owner can
remove one of the old devices right on that screen).

## 4. Cloud sync + bilty photos

* Data: `shops/{uid}/customers|products|bills|payments|purchases|bill_dispatch`
  - SQLite is the source of truth; push every 2 minutes + on every save;
  pull with last-write-wins merge; deletes are tombstones.
* **Photos** (billty receipts, payment proofs, purchase bills):
  `shops/{uid}/photos/{table}_{rowId}.jpg` in Firebase Storage,
  **compressed to <= 300 KB on the phone before upload** (the Storage
  rules reject anything bigger). The other device downloads any photo
  it is missing automatically.
* **45-day billty rule:** billty photos delete themselves after 45 days
  on every device, and expired cloud copies are cleaned from Storage on
  the next sync of any device. Payment proofs / purchase photos have no
  expiry.

## 5. Ruby Key - admin panel (web PWA)

Lives in [`/ruby-key-admin`](../ruby-key-admin/README.md). Setup:

1. **Register a Web app**: Project settings -> Your apps -> **Web** `</>`
   -> nickname `Ruby Key` -> copy `appId` into
   `ruby-key-admin/firebase-config.js` (replace `PASTE_WEB_APP_ID_HERE`).
2. **Authorized domains**: Authentication -> Settings -> Authorized
   domains -> add `ahemadjuneja-stack.github.io`.
3. **Publish the panel**: repo **Settings -> Pages** -> Source:
   **GitHub Actions**. The workflow `admin-pages.yml` deploys
   `ruby-key-admin/` on every push to main. Open:
   `https://ahemadjuneja-stack.github.io/rub-invoice/`
4. Chrome on your phone -> open the URL -> menu -> **Add to Home
   screen** -> install as "Ruby Key".

What it does: live cards (Total / Trials / Paid / Expired / Blocked),
search, per-user Block-Unblock (instant kill switch), Extend validity
(+30 days / +1 year / custom date - writes `subscriptionEndDate` and a
`subscriptions` row), device list with model names + reset, WhatsApp /
Call buttons.

## 6. subscriptions schema (Razorpay-ready)

```
subscriptions/{autoId} {
  userId:            "<users/{uid}>",
  shopName:          "...",
  planId:            "monthly" | "yearly" | "manual",
  amount:            9900,            // paise
  currency:          "INR",
  razorpayOrderId:   "order_...",     // filled by the webhook later
  razorpayPaymentId: "pay_...",
  status:            "active" | "expired" | "failed",
  validUntil:        <Timestamp>,
  note:              "...",
  createdAt:         <serverTimestamp>
}
```

A Razorpay webhook (later) can create the same documents with the
Admin SDK - no migration needed; the app only ever reads
`subscriptionEndDate` on the user document.

## 7. Verify

1. Open the app -> login screen -> Continue with Google -> register ->
   straight to billing. 2nd phone: same Gmail -> same data.
2. Block yourself from Ruby Key -> the phone locks within seconds;
   Unblock -> it unlocks itself.
3. Take a billty photo on phone A -> it appears on phone B after sync.
