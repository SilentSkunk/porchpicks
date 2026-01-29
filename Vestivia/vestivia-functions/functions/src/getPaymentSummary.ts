import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as admin from "firebase-admin";
import Stripe from "stripe";

if (!admin.apps.length) admin.initializeApp();

const STRIPE_SECRET_KEY = defineSecret("STRIPE_SECRET_KEY");

export const getPaymentSummary = onCall(
  { region: "us-central1", secrets: [STRIPE_SECRET_KEY] },
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }

    const stripe = new Stripe(STRIPE_SECRET_KEY.value());

    // Look up the Stripe customer id saved on the user doc
    const userRef = admin.firestore().collection("users").doc(uid);
    const snap = await userRef.get();
    const customerId = snap.get("stripeCustomerId") as string | undefined;

    if (!customerId) {
      // No Stripe customer yet, therefore no saved card
      return {
        hasSavedCard: false,
        customerId: null,
        defaultCard: null,
        paymentMethodId: null,
      };
    }

    // Try to get a default payment method if one is set on the customer
    const customer = (await stripe.customers.retrieve(customerId)) as Stripe.Customer;
    let defaultPmId: string | null = null;

    // invoice_settings.default_payment_method can be a string or an object
    const invDefault = customer.invoice_settings?.default_payment_method;
    if (typeof invDefault === "string") {
      defaultPmId = invDefault;
    } else if (invDefault && typeof invDefault === "object") {
      defaultPmId = invDefault.id ?? null;
    }

    // If we have a default pm id, retrieve it; otherwise list the first card
    let chosenPm: Stripe.PaymentMethod | null = null;

    if (defaultPmId) {
      try {
        const pm = await stripe.paymentMethods.retrieve(defaultPmId);
        if (pm?.customer === customerId && pm.type === "card") {
          chosenPm = pm;
        }
      } catch {
        // fall through to listing below if retrieval failed
      }
    }

    if (!chosenPm) {
      const list = await stripe.paymentMethods.list({
        customer: customerId,
        type: "card",
        limit: 1,
      });
      chosenPm = list.data[0] ?? null;
    }

    if (!chosenPm || chosenPm.type !== "card" || !chosenPm.card) {
      return {
        hasSavedCard: false,
        customerId,
        defaultCard: null,
        paymentMethodId: null,
      };
    }

    const card = chosenPm.card;
    return {
      hasSavedCard: true,
      customerId,
      paymentMethodId: chosenPm.id,
      // Keep the object minimal & safe for client display
      defaultCard: {
        brand: card.brand ?? "unknown",
        last4: card.last4 ?? "****",
        expMonth: card.exp_month ?? 0,
        expYear: card.exp_year ?? 0,
        funding: card.funding ?? "unknown",
        country: card.country ?? null,
      },
    };
  }
);