// --- createPaymentIntent (callable) ---
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import Stripe from "stripe";
import crypto from "crypto";

const STRIPE_SECRET_KEY = defineSecret("STRIPE_SECRET_KEY");

// Generate deterministic idempotency key to prevent duplicate PaymentIntents
function generateIdempotencyKey(uid: string, listingId: string, amount: number): string {
  return crypto
    .createHash("sha256")
    .update(`${uid}-${listingId}-${amount}`)
    .digest("hex")
    .slice(0, 32);
}

export const createPaymentIntent = onCall(
  { region: "us-central1", secrets: [STRIPE_SECRET_KEY] },
  async (req) => {
    const stripe = new Stripe(STRIPE_SECRET_KEY.value());

    const uid = req.auth?.uid;
    const {
      amount,
      currency = "usd",
      shipping,
      listingId,
      buyerId,
      sellerId,
    } = req.data ?? {};

    // ⚠️ This endpoint does NOT calculate sales tax.
    // Use `initFlowController` for checkout with Stripe Tax.

    if (!Number.isInteger(amount) || amount <= 0) {
      throw new HttpsError("invalid-argument", "amount must be a positive integer (cents).");
    }

    const metadata: Record<string, string> = {};
    if (listingId) metadata["listingId"] = String(listingId);
    if (buyerId) metadata["buyerId"] = String(buyerId);
    if (sellerId) metadata["sellerId"] = String(sellerId);

    // Generate idempotency key to prevent duplicate PaymentIntents on retry
    const idempotencyKey = generateIdempotencyKey(
      uid || buyerId || "anonymous",
      listingId || "checkout",
      amount
    );

    const params = {
      amount,
      currency,
      automatic_payment_methods: { enabled: true }, // Apple Pay etc.
      metadata,
    } as Stripe.PaymentIntentCreateParams;

    // Optional shipping block (what you're already sending from the app)
    if (shipping) {
      params.shipping = {
        name: shipping.fullName || "Customer",
        phone: shipping.phone || undefined,
        address: {
          line1: shipping.address || "",
          ...(shipping.city ? { city: shipping.city } : {}),
          ...(shipping.state ? { state: shipping.state } : {}),
          ...(shipping.postal_code ? { postal_code: shipping.postal_code } : {}),
          country: (shipping.country || "US").toUpperCase(),
        },
      };
    }

    const pi = await stripe.paymentIntents.create(params, { idempotencyKey });
    if (!pi.client_secret) {
      throw new HttpsError("internal", "No client_secret on PaymentIntent.");
    }
    return { clientSecret: pi.client_secret };
  }
);