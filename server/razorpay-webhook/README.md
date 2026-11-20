# Razorpay Webhook - Server-Side Payment Verification

Isolated backend component. **Nothing here ever ships inside the APK** -
the Android app and the Ruby Key PWA never see, hold or compute the
webhook secret.

## Why this exists

With the v0.2.21 Firestore rules, `users/{uid}.status`, `.plan`,
`.subscriptionEndDate`, `.maxDevices`, `.trialEndDate` and
`.expiryDate` can be written ONLY by:

1. the whitelisted Admin Gmail (Ruby Key panel / Firebase console), and
2. this Cloud Function (the Admin SDK bypasses security rules, and its
   credentials live server-side only).

A client can never self-activate a paid plan. The only automated writer
is this webhook, and it accepts a Razorpay event **only** when the
`x-razorpay-signature` header equals
`HMAC_SHA256(RAZORPAY_WEBHOOK_SECRET, raw_body)`.

## Setup (one time)

```bash
cd server/razorpay-webhook
npm install

# store the secret (never in git, never in the app):
firebase functions:secrets:set RAZORPAY_WEBHOOK_SECRET
# paste the same value into Razorpay Dashboard -> Settings -> Webhooks

npm run deploy
```

## Wire up Razorpay

1. Razorpay Dashboard -> Settings -> Webhooks -> **Add New Webhook**
2. URL: `https://razorpaywebhook-<hash>-<region>.cloudfunctions.net/razorpayWebhook`
   (printed by `npm run deploy`)
3. Secret: the SAME value as `RAZORPAY_WEBHOOK_SECRET`
4. Active events: `payment.captured`, `order.paid`
5. When creating orders in the (future) billing page, attach routing
   notes: `{ userId: "<users/{uid} doc id>", planId: "monthly" | "yearly" }`.

## What it does on a verified `payment.captured`

* extends `users/{uid}.subscriptionEndDate` from the current validity
  (stacking on top of remaining days) and sets `status: "active"`,
  `plan: "paid"`;
* writes the `subscriptions/{id}` ledger row with the Razorpay order /
  payment ids (audit trail, same schema as Ruby Key's manual extension);
* rejects any request whose signature does not verify (HTTP 401).

## Plan catalogue

`PLANS` in `index.js` (monthly = 30 days, yearly = 365 days, prices in
paise). Change prices HERE - never in a client: a client-side price can
be tampered with, this one cannot.
