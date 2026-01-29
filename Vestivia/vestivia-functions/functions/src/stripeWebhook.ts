import { onRequest } from "firebase-functions/v2/https";
// functions/src/stripeWebhook.ts
import Stripe from "stripe";
import { defineSecret } from "firebase-functions/params";
import * as admin from "firebase-admin";

// Ensure Admin SDK initialized once
if (!admin.apps.length) admin.initializeApp();

const STRIPE_SECRET_KEY = defineSecret("STRIPE_SECRET_KEY");
const STRIPE_WEBHOOK_SECRET = defineSecret("STRIPE_WEBHOOK_SECRET");
const STRIPE_CLI_WEBHOOK_SECRET = defineSecret("STRIPE_CLI_WEBHOOK_SECRET");

// Helper: mark listing sold in Firestore (idempotent)
async function markListingSold(opts: {
  listingId: string;
  sellerId: string;
  buyerId?: string;
  paymentIntentId: string;
  amount: number; // cents
  currency: string;
}) {
  const { listingId, sellerId, buyerId, paymentIntentId, amount, currency } = opts;
  const db = admin.firestore();

  const sellerListingRef = db
    .collection("users")
    .doc(sellerId)
    .collection("listings")
    .doc(listingId);

  const mirrorRef = db.collection("all_listings").doc(listingId);

  await db.runTransaction(async (tx) => {
    const listingSnap = await tx.get(sellerListingRef);
    if (!listingSnap.exists) {
      // If the seller listing doc does not exist, bail but do not fail the webhook
      return;
    }

    const current = listingSnap.data() || {};
    if (current.status === "sold" || current.isAvailable === false) {
      // Already sold/updated in a prior delivery – idempotent exit
      return;
    }

    const update = {
      status: "sold",
      isAvailable: false,
      soldAt: admin.firestore.FieldValue.serverTimestamp(),
      soldTo: buyerId || null,
      orderPaymentIntentId: paymentIntentId,
      saleAmount: amount,
      saleCurrency: currency,
    } as Record<string, unknown>;

    tx.update(sellerListingRef, update);

    // Mirror (if present) – tolerate absence
    const mirrorSnap = await tx.get(mirrorRef);
    if (mirrorSnap.exists) {
      tx.update(mirrorRef, update);
    }

    // Minimal central order record (optional but useful for ops)
    const ordersRef = db.collection("orders").doc(paymentIntentId);
    tx.set(
      ordersRef,
      {
        paymentIntentId,
        listingId,
        sellerId,
        buyerId: buyerId || null,
        amount,
        currency,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        status: "paid",
        source: "stripe",
      },
      { merge: true }
    );

    // Per-user views (optional): buyer orders & seller sales
    if (buyerId) {
      const buyerOrderRef = db
        .collection("users")
        .doc(buyerId)
        .collection("orders")
        .doc(paymentIntentId);
      tx.set(
        buyerOrderRef,
        {
          listingId,
          paymentIntentId,
          amount,
          currency,
          status: "paid",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }

    const sellerSaleRef = db
      .collection("users")
      .doc(sellerId)
      .collection("sales")
      .doc(paymentIntentId);
    tx.set(
      sellerSaleRef,
      {
        listingId,
        paymentIntentId,
        amount,
        currency,
        status: "paid",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  });
}

export const stripeWebhook = onRequest({ region: "us-central1", invoker: "public", secrets: [STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, STRIPE_CLI_WEBHOOK_SECRET] }, async (req, res) => {
  const sig = req.headers["stripe-signature"] as string | undefined;
  if (!sig) {
    console.error("❌ Missing stripe-signature header");
    res.status(400).send("Missing stripe-signature header");
    return;
  }

  // Read Stripe secrets from injected Secret Manager values
  const secretKey = process.env.STRIPE_SECRET_KEY as string | undefined;
  const dashboardWebhookSecret = process.env.STRIPE_WEBHOOK_SECRET as string | undefined;
  const cliSecret = process.env.STRIPE_CLI_WEBHOOK_SECRET as string | undefined;

  const hasRawBody = typeof (req as any).rawBody !== "undefined" && (req as any).rawBody !== null;
  console.log("[STRIPE] env check", {
    hasSecretKey: !!secretKey,
    hasWebhookSecret: !!dashboardWebhookSecret,
    hasCliSecret: !!cliSecret,
    hasRawBody,
    contentType: req.headers["content-type"] || null,
  });

  if (!secretKey || !dashboardWebhookSecret) {
    console.error("❌ Missing Stripe config: ", {
      hasSecretKey: !!secretKey,
      hasWebhookSecret: !!dashboardWebhookSecret,
    });
    res.status(500).send("Server misconfigured: Stripe env not set");
    return;
  }

  // Initialize Stripe client per-request (safe if secrets missing during module load)
  const stripe = new Stripe(secretKey);

  // Normalize payload for Stripe signature verification
  const rb: any = (req as any).rawBody;
  const payload: Buffer = Buffer.isBuffer(rb)
    ? rb
    : typeof rb === "string"
    ? Buffer.from(rb)
    : Buffer.from(JSON.stringify(req.body ?? {}));

  // Detect environment properly
  const isProduction = process.env.GCLOUD_PROJECT?.includes('prod') ||
                       process.env.NODE_ENV === 'production';

  const webhookSecret = isProduction
    ? dashboardWebhookSecret  // Dashboard secret only in production
    : cliSecret || dashboardWebhookSecret;  // CLI secret in development, fallback to dashboard

  if (!webhookSecret) {
    console.error("❌ No webhook secret configured");
    res.status(500).send("Server misconfigured: no webhook secret");
    return;
  }

  let event: Stripe.Event;
  try {
    event = stripe.webhooks.constructEvent(payload, sig, webhookSecret);
    console.log("🔐 Webhook verified", { isProduction });
  } catch (err: any) {
    console.error("❌ Webhook verification failed:", err?.message);
    res.status(400).send(`Webhook Error: ${err?.message || "invalid signature"}`);
    return;
  }

  console.log("✅ Received event:", { type: event.type, id: event.id });

  // Handle different event types
  switch (event.type) {
    case "payment_intent.succeeded": {
      const pi = event.data.object as Stripe.PaymentIntent;
      console.log("💰 Payment succeeded:", { id: pi.id, amount: pi.amount, customer: pi.customer, metadata: pi.metadata });

      const listingId = (pi.metadata?.listingId as string) || "";
      const sellerId = (pi.metadata?.sellerId as string) || "";
      const buyerId = (pi.metadata?.buyerId as string) || undefined;

      if (listingId && sellerId) {
        await markListingSold({
          listingId,
          sellerId,
          buyerId,
          paymentIntentId: pi.id,
          amount: (pi.amount_received ?? pi.amount) as number,
          currency: pi.currency,
        });
      } else {
        console.warn("[stripeWebhook] payment_intent.succeeded missing listingId/sellerId in metadata");
      }
      break;
    }
    case "payment_intent.payment_failed": {
      const pi = event.data.object as Stripe.PaymentIntent;
      console.log("❌ Payment failed:", { id: pi.id, last_payment_error: (pi.last_payment_error?.message || null) });
      // TODO: mark order failed
      break;
    }
    case "payout.paid":
    case "payout.failed":
    case "payout.canceled": {
      const payout = event.data.object as Stripe.Payout;
      console.log(`📤 ${event.type}`, { id: payout.id, status: payout.status, amount: payout.amount, arrival_date: payout.arrival_date });
      // TODO: reflect payout status in Firestore for the seller account, if you track it
      break;
    }
    case "account.updated": {
      const acct = event.data.object as Stripe.Account;
      console.log("👤 account.updated", { id: acct.id, payouts_enabled: acct.payouts_enabled, charges_enabled: acct.charges_enabled });
      // TODO: mirror KYC status to Firestore (e.g., users/{uid}.kycStatus)
      break;
    }
    default:
      console.log("ℹ️ Unhandled event type:", event.type);
  }

  res.status(200).send("ok");
});