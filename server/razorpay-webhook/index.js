// =====================================================================
// Ruby Invoice - Razorpay payment verification webhook (SERVER-SIDE)
//
// SECURITY CONTRACT (v0.2.21):
//   * The Android app can NEVER set users/{uid}.subscriptionEndDate,
//     plan or status - the Firestore rules only allow the Admin Gmail
//     and this server (Admin SDK bypasses rules) to write them.
//   * This function is the ONLY automated writer. It verifies the
//     Razorpay HMAC SHA-256 signature of the RAW request body before
//     trusting anything. A client cannot forge it without the webhook
//     secret, which lives ONLY in this function's secret store.
//   * Amounts are re-verified against the plan price; a captured
//     payment below the plan price is recorded but flagged in logs.
//
// Deploy (see README.md in this folder):
//   firebase functions:secrets:set RAZORPAY_WEBHOOK_SECRET
//   firebase deploy --only functions
// =====================================================================

const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const crypto = require("crypto");
const admin = require("firebase-admin");

admin.initializeApp();

const RAZORPAY_WEBHOOK_SECRET = defineSecret("RAZORPAY_WEBHOOK_SECRET");

// planId -> extension days + price (paise). Keep in sync with the Ruby
// Key / billing page; edit here, never in a client.
const PLANS = {
  monthly: { days: 30, amountPaise: 9900 },
  yearly: { days: 365, amountPaise: 79900 },
};

/**
 * Razorpay webhook - verifies HMAC SHA-256 signature on the raw body:
 *   expected = HMAC_SHA256(webhook_secret, raw_body)
 *   header   = x-razorpay-signature
 * Handles `payment.captured` (and `order.paid`) events: extends the
 * shop's subscriptionEndDate by the plan length and writes the
 * subscriptions/{id} ledger row (same schema as the Ruby Key manual
 * extension, note: "razorpay").
 */
exports.razorpayWebhook = onRequest(
  { secrets: [RAZORPAY_WEBHOOK_SECRET], region: "asia-south1" },
  async (req, res) => {
    if (req.method !== "POST") {
      return res.status(405).send("POST only");
    }

    // ---- 1. verify the signature over the RAW body (never re-serialized) --
    const signature = req.get("x-razorpay-signature");
    const secret = process.env.RAZORPAY_WEBHOOK_SECRET;
    if (!secret) {
      console.error("RAZORPAY_WEBHOOK_SECRET is not configured");
      return res.status(500).send("server misconfigured");
    }
    const expected = crypto
      .createHmac("sha256", secret)
      .update(req.rawBody)
      .digest("hex");
    const a = Buffer.from(signature || "", "utf8");
    const b = Buffer.from(expected, "utf8");
    if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
      console.warn("rejected: bad signature");
      return res.status(401).send("invalid signature");
    }

    // ---- 2. parse + validate the event -----------------------------------
    const event = req.body;
    const type = event && event.event;
    if (type !== "payment.captured" && type !== "order.paid") {
      return res.status(200).send("ignored: " + type);
    }
    const payment =
      (event.payload && event.payload.payment && event.payload.payment.entity) ||
      {};
    const notes = payment.notes || {};
    const userId = String(notes.userId || notes.uid || "");
    const planId = String(notes.planId || "monthly").toLowerCase();
    const plan = PLANS[planId];
    if (!userId || !plan) {
      console.warn("valid signature but missing routing notes", { userId, planId });
      return res.status(200).send("missing routing notes");
    }
    if (Number(payment.amount) < plan.amountPaise) {
      console.warn("underpaid payment - ledger row still written", {
        amount: payment.amount,
        planId,
      });
    }

    // ---- 3. server-side account update (Admin SDK - bypasses rules) ------
    const db = admin.firestore();
    const userRef = db.collection("users").doc(userId);
    const subRef = db.collection("subscriptions").doc();

    const result = await db.runTransaction(async (txn) => {
      const snap = await txn.get(userRef);
      if (!snap.exists) throw new Error("unknown user " + userId);
      const data = snap.data() || {};
      const now = Date.now();
      // extend from the CURRENT validity if it is still in the future
      const curEnd = data.subscriptionEndDate
        ? data.subscriptionEndDate.toMillis
          ? data.subscriptionEndDate.toMillis()
          : Number(data.subscriptionEndDate) || 0
        : 0;
      const base = Math.max(curEnd, now);
      const newEnd = new Date(base + plan.days * 86400000);

      txn.update(userRef, {
        status: "active",
        plan: "paid",
        subscriptionEndDate: admin.firestore.Timestamp.fromDate(newEnd),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      txn.set(subRef, {
        userId,
        planId,
        amount: payment.amount,
        currency: payment.currency || "INR",
        razorpayOrderId: payment.order_id || "",
        razorpayPaymentId: payment.id || "",
        status: "active",
        validUntil: admin.firestore.Timestamp.fromDate(newEnd),
        note: "razorpay webhook (HMAC verified)",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return { validUntil: newEnd.toISOString() };
    });

    console.log("subscription extended", { userId, planId, ...result });
    return res.status(200).json({ ok: true, ...result });
  }
);
