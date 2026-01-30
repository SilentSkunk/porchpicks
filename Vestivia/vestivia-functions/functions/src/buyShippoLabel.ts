import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as admin from "firebase-admin";

// Initialize Admin once
if (!admin.apps.length) {
  admin.initializeApp();
}

// ---- Secrets & constants ----
const SHIPPO_TEST_KEY = defineSecret("SHIPPO_TEST_KEY");
const SHIPPO_API = "https://api.goshippo.com";
const authHeader = (key: string) => ({ Authorization: `ShippoToken ${key}` });

// ---- Types ----
type ShippoTransaction = {
  status?: string;
  label_url?: string;
  tracking_number?: string;
  tracking_provider?: string;
  object_id?: string;
  amount?: string | number;
  currency?: string;
  messages?: unknown[];
};

type BuyLabelInput = {
  shipmentId: string;
  rateId: string;
};

// ---- Callable: buyShippoLabel ----
export const buyShippoLabel = onCall(
  { region: "us-central1", secrets: [SHIPPO_TEST_KEY] },
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }

    const { shipmentId, rateId } = (req.data || {}) as BuyLabelInput;
    if (!shipmentId || !rateId) {
      throw new HttpsError("invalid-argument", "shipmentId and rateId are required");
    }

    const key = SHIPPO_TEST_KEY.value();
    if (!key) {
      throw new HttpsError("internal", "Missing Shippo API key");
    }

    // Create transaction (purchase label)
    const txResp = await fetch(`${SHIPPO_API}/transactions/`, {
      method: "POST",
      headers: {
        ...authHeader(key),
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        rate: rateId,
        label_file_type: "PDF",
        async: false,
      }),
    });

    const tx = (await txResp.json()) as ShippoTransaction;

    if (!txResp.ok || tx?.status !== "SUCCESS") {
      // If FAILED, details are typically in tx.messages
      throw new HttpsError(
        "internal",
        `Shippo purchase failed: HTTP ${txResp.status} ${txResp.statusText} ${JSON.stringify(tx)}`
      );
    }

    // Persist to Firestore
    await admin
      .firestore()
      .collection("users")
      .doc(uid)
      .collection("shipments")
      .doc(shipmentId)
      .set(
        {
          status: "purchased",
          label_url: tx.label_url,
          tracking_number: tx.tracking_number,
          carrier: tx.tracking_provider,
          transaction_id: tx.object_id,
          amount: tx.amount,
          currency: tx.currency,
          purchasedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

    return {
      labelUrl: tx.label_url,
      trackingNumber: tx.tracking_number,
      carrier: tx.tracking_provider,
      transactionId: tx.object_id,
    };
  }
);