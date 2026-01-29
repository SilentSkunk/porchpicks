import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as admin from "firebase-admin";
import Stripe from "stripe";

if (!admin.apps.length) admin.initializeApp();

const STRIPE_SECRET_KEY = defineSecret("STRIPE_SECRET_KEY");

export const getSavedCardSummary = onCall(
  { region: "us-central1", secrets: [STRIPE_SECRET_KEY] },
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "You must be signed in");

    const stripe = new Stripe(STRIPE_SECRET_KEY.value());

    // Load Stripe customer ID
    const userRef = admin.firestore().collection("users").doc(uid);
    const snap = await userRef.get();
    const customerId = snap.get("stripeCustomerId");

    if (!customerId) {
      return {
        hasSavedPaymentMethod: false,
        paymentMethodSummary: null,
      };
    }

    // Retrieve stored payment methods
    const methods = await stripe.paymentMethods.list({
      customer: customerId,
      type: "card",
      limit: 1,
    });

    if (!methods.data.length) {
      return {
        hasSavedPaymentMethod: false,
        paymentMethodSummary: null,
      };
    }

    const pm = methods.data[0];
    if (!pm) {
      return {
        hasSavedPaymentMethod: false,
        paymentMethodSummary: null,
      };
    }

    return {
      hasSavedPaymentMethod: true,
      paymentMethodSummary: {
        brand: pm.card?.brand ?? "",
        last4: pm.card?.last4 ?? "",
      },
    };
  }
);