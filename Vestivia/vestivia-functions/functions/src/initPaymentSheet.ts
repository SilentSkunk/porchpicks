import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import Stripe from "stripe";
import * as admin from "firebase-admin";
import crypto from "crypto";

// Generate deterministic idempotency key to prevent duplicate PaymentIntents
function generateIdempotencyKey(uid: string, listingId: string, amount: number): string {
  return crypto
    .createHash("sha256")
    .update(`${uid}-${listingId}-${amount}`)
    .digest("hex")
    .slice(0, 32);
}

// Ensure Admin SDK initialized once
if (!admin.apps.length) admin.initializeApp();

const STRIPE_SECRET_KEY = defineSecret("STRIPE_SECRET_KEY");

// ⚠️ DEPRECATED FOR CHECKOUT
// This endpoint creates a non-tax-aware PaymentIntent.
// Use `initFlowController` for all customer checkout flows.
// --- initPaymentSheet (callable) ---
// Prepares PaymentSheet by creating/returning:
//  - Stripe Customer (re-used if exists)
//  - Ephemeral Key for the mobile SDK
//  - PaymentIntent client_secret for the provided amount
export const initPaymentSheet = onCall(
  { region: "us-central1", secrets: [STRIPE_SECRET_KEY] },
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }

    const stripe = new Stripe(STRIPE_SECRET_KEY.value());

    // Validate input
    const { amount, currency = "usd", shipping, listingId, sellerId } = (req.data ?? {}) as {
      amount?: number;
      currency?: string;
      listingId?: string;
      sellerId?: string;
      shipping?: {
        fullName?: string;
        address?: string;
        city?: string;
        country?: string;
        phone?: string;
      };
    };

    if (!Number.isInteger(amount) || (amount as number) <= 0) {
      throw new HttpsError("invalid-argument", "amount (in cents) is required and must be a positive integer.");
    }

    const buyerId = uid;

    // Get or create Stripe customer for this Firebase user
    const db = admin.firestore();
    const userRef = db.collection("users").doc(uid);
    const snap = await userRef.get();

    let customerId = snap.get("stripeCustomerId") as string | undefined;
    if (!customerId) {
      const userEmail = (snap.get("email") as string | undefined) ?? undefined;
      const userName =
        (snap.get("username") as string | undefined) ??
        (snap.get("displayName") as string | undefined) ??
        undefined;

      const customer = await stripe.customers.create({
        email: userEmail,
        name: userName,
        metadata: { uid },
      });
      customerId = customer.id;
      await userRef.set({ stripeCustomerId: customerId }, { merge: true });
    }

    // Check if customer already has a saved card to help the client show "remembered" state
    const pmList = await stripe.paymentMethods.list({
      customer: customerId,
      type: "card",
      limit: 1,
    });
    const hasSaved = pmList.data.length > 0;
    const savedSummary = hasSaved
      ? {
          brand: pmList.data[0].card?.brand || null,
          last4: pmList.data[0].card?.last4 || null,
          expMonth: pmList.data[0].card?.exp_month || null,
          expYear: pmList.data[0].card?.exp_year || null,
          paymentMethodId: pmList.data[0].id || null,
        }
      : null;

    // Create ephemeral key for the iOS SDK
    const ephemeralKey = await stripe.ephemeralKeys.create({
      customer: customerId,
    });

    // Build a Stripe-compliant Shipping object only when we have enough data.
    const shippingParams: Stripe.PaymentIntentCreateParams.Shipping | undefined = shipping
      ? {
          // Stripe's type expects `name` to be a string (not undefined).
          name: shipping.fullName || "Customer",
          // Optional
          phone: shipping.phone || undefined,
          // Address requires at least line1 and country.
          address: {
            line1: shipping.address || "Unknown",
            country: (shipping.country || "US").toUpperCase(),
            ...(shipping.city ? { city: shipping.city } : {}),
          },
        }
      : undefined;

    // Generate idempotency key to prevent duplicate PaymentIntents on retry
    const idempotencyKey = generateIdempotencyKey(uid, listingId || "checkout", amount as number);

    // Create PaymentIntent for the provided amount
    const paymentIntent = await stripe.paymentIntents.create(
      {
        amount: amount as number,
        currency,
        customer: customerId,
        automatic_payment_methods: { enabled: true },
        shipping: shippingParams,
        metadata: {
          ...(listingId ? { listingId } : {}),
          ...(sellerId ? { sellerId } : {}),
          buyerId, // always include buyer uid
        },
      },
      { idempotencyKey }
    );

    if (!paymentIntent.client_secret) {
      throw new HttpsError("internal", "Failed to create payment intent.");
    }

    return {
      paymentIntent: paymentIntent.client_secret,
      ephemeralKey: ephemeralKey.secret,
      customer: customerId,
      // NEW: help the client reflect "remembered card" state without another round-trip
      hasSavedPaymentMethod: hasSaved,
      paymentMethodSummary: savedSummary,
      publishableKey: process.env.STRIPE_PUBLISHABLE_KEY || null,
    };
  }
);

// --- getPaymentSummary (callable) ---
// Lightweight way to check whether the user already has a saved payment method
// and get a brief summary (brand/last4) without creating a PaymentIntent.
export const getPaymentSummary = onCall(
  { region: "us-central1", secrets: [STRIPE_SECRET_KEY] },
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }

    const stripe = new Stripe(STRIPE_SECRET_KEY.value());
    const db = admin.firestore();
    const userRef = db.collection("users").doc(uid);
    const snap = await userRef.get();

    let customerId = snap.get("stripeCustomerId") as string | undefined;
    if (!customerId) {
      // No customer yet; nothing saved
      return { hasSavedPaymentMethod: false, paymentMethodSummary: null };
    }

    const pmList = await stripe.paymentMethods.list({
      customer: customerId,
      type: "card",
      limit: 1,
    });
    const hasSaved = pmList.data.length > 0;
    const savedSummary = hasSaved
      ? {
          brand: pmList.data[0].card?.brand || null,
          last4: pmList.data[0].card?.last4 || null,
          expMonth: pmList.data[0].card?.exp_month || null,
          expYear: pmList.data[0].card?.exp_year || null,
          paymentMethodId: pmList.data[0].id || null,
        }
      : null;

    return { hasSavedPaymentMethod: hasSaved, paymentMethodSummary: savedSummary };
  }
);