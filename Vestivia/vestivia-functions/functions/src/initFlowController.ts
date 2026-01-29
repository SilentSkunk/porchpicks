import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as admin from "firebase-admin";
import Stripe from "stripe";
import crypto from "crypto";

// Generate deterministic idempotency key to prevent duplicate PaymentIntents
function generateIdempotencyKey(uid: string, identifier: string, amount: number): string {
  return crypto
    .createHash("sha256")
    .update(`${uid}-${identifier}-${amount}`)
    .digest("hex")
    .slice(0, 32);
}

if (!admin.apps.length) {
  admin.initializeApp();
}

// ✅ Use secrets instead of environment variables
const STRIPE_SECRET_KEY = defineSecret("STRIPE_SECRET_KEY");
const STRIPE_PUBLISHABLE_KEY = defineSecret("STRIPE_PUBLISHABLE_KEY");

/**
 * initFlowController
 * Creates:
 * - Stripe customer (if not exists)
 * - Ephemeral key
 * - PaymentIntent
 * Returns:
 * - client secret
 * - ephemeral key secret
 * - customer ID
 * - publishable key
 */
export const initFlowController = onCall(
  { 
    region: "us-central1",
    secrets: [STRIPE_SECRET_KEY, STRIPE_PUBLISHABLE_KEY] // ✅ Add secrets here
  },
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }

    // ✅ Initialize Stripe INSIDE the function
    const stripe = new Stripe(STRIPE_SECRET_KEY.value());

    const subtotal = Number(req.data?.subtotal);
    const shipping = Number(req.data?.shipping);
    const currency = (req.data?.currency as string) || "usd";
    const address = req.data?.address;

    if (!subtotal || subtotal <= 0) {
      throw new HttpsError("invalid-argument", "Missing or invalid subtotal.");
    }

    if (shipping == null || shipping < 0) {
      throw new HttpsError("invalid-argument", "Missing or invalid shipping.");
    }

    if (!address?.line1) {
      throw new HttpsError(
        "invalid-argument",
        "Shipping address is required."
      );
    }

    // 1 – find or create stripe customer
    const customerId = await findOrCreateStripeCustomer(uid, stripe);

    // 2 – ephemeral key
    const ephemeralKey = await stripe.ephemeralKeys.create({
      customer: customerId,
    });

    // 3 – PaymentIntent
    const totalAmount = subtotal + shipping;

    // Generate idempotency key to prevent duplicate PaymentIntents on retry
    const idempotencyKey = generateIdempotencyKey(uid, address.line1 || "checkout", totalAmount);

    const params = {
      amount: totalAmount, // pre-tax
      currency,
      customer: customerId,
      automatic_payment_methods: { enabled: true },
      shipping: {
        name: address.name || "Customer",
        address: {
          line1: address.line1,
          ...(address.city ? { city: address.city } : {}),
          ...(address.state ? { state: address.state } : {}),
          ...(address.postal_code ? { postal_code: address.postal_code } : {}),
          country: (address.country || "US").toUpperCase(),
        },
      },
      metadata: {
        subtotal: subtotal.toString(),
        shipping: shipping.toString(),
        tax_category: "clothing",
      },
    } as Stripe.PaymentIntentCreateParams;

    const paymentIntent = await stripe.paymentIntents.create(params, { idempotencyKey });

    console.log(
      "[initFlowController] PI created",
      paymentIntent.id,
      "amount:",
      paymentIntent.amount
    );

    return {
      paymentIntent: paymentIntent.client_secret,
      ephemeralKey: ephemeralKey.secret,
      customer: customerId,
      publishableKey: STRIPE_PUBLISHABLE_KEY.value(), // ✅ Use .value()

      // Explicit client-visible breakdown
      amountSubtotal: subtotal,
      amountShipping: shipping, // ✅ expose shipping separately
      amountTax: null,          // calculated by Stripe internally
      amountTotal: paymentIntent.amount,
    };
  }
);

// ✅ Updated helper to accept stripe instance
async function findOrCreateStripeCustomer(uid: string, stripe: Stripe): Promise<string> {
  const doc = await admin
    .firestore()
    .collection("stripe_customers")
    .doc(uid)
    .get();

  if (doc.exists && doc.get("customerId")) {
    return doc.get("customerId");
  }

  const customer = await stripe.customers.create({
    metadata: { uid },
  });

  await doc.ref.set({ customerId: customer.id }, { merge: true });

  return customer.id;
}