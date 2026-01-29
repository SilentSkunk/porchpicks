import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import Stripe from "stripe";

if (!admin.apps.length) admin.initializeApp();

export const initSetupSheet = onCall(
  { region: "us-central1" },
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

    console.log("[initSetupSheet] called", { uid });

    const stripeSecret = process.env["STRIPE_SECRET_KEY"];
    console.log("[initSetupSheet] stripe key present:", !!stripeSecret);

    if (!stripeSecret) {
      throw new Error("STRIPE_SECRET_KEY missing at runtime");
    }

    const stripe = new Stripe(stripeSecret);

    const userRef = admin.firestore().collection("users").doc(uid);
    const snap = await userRef.get();
    let customerId = snap.get("stripeCustomerId");

    if (!customerId) {
      const customer = await stripe.customers.create({
        metadata: { uid },
        email: snap.get("email") ?? undefined,
        name: snap.get("username") ?? snap.get("displayName") ?? undefined,
      });
      customerId = customer.id;
      await userRef.set({ stripeCustomerId: customerId }, { merge: true });
    }

    console.log("[initSetupSheet] using customerId:", customerId);

    const ephemeralKey = await stripe.ephemeralKeys.create(
      { customer: customerId },
      { apiVersion: "2025-12-15.clover" }
    );

    console.log("[initSetupSheet] ephemeral key created", {
      hasSecret: !!ephemeralKey.secret,
      apiVersion: "2025-12-15.clover",
    });

    const setupIntent = await stripe.setupIntents.create({
      customer: customerId,
      usage: "off_session", // so you can later charge without re-prompting
    });

    console.log("[initSetupSheet] setupIntent created", {
      setupIntentId: setupIntent.id,
      setupIntentCustomer: setupIntent.customer,
    });

    return {
      setupIntent: setupIntent.client_secret,
      ephemeralKey: ephemeralKey.secret,
      customer: customerId,
      publishableKey: process.env["STRIPE_PUBLISHABLE_KEY"] ?? null,
    };
  }
)