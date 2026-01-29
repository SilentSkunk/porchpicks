// ShippoShipmentGetRates.ts (only the important bits)

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as admin from "firebase-admin";

if (!admin.apps.length) admin.initializeApp();

const SHIPPO_TEST_KEY = defineSecret("SHIPPO_TEST_KEY");
const SHIPPO_API = "https://api.goshippo.com";
const OUNCES_PER_POUND = 16;

const authHeader = (key: string) => ({
  Authorization: `ShippoToken ${key}`,
  "Content-Type": "application/json",
});

// Validation utilities
const VALID_US_STATES = new Set([
  "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
  "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
  "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
  "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
  "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY", "DC"
]);

function validateUSState(state: unknown, fieldName: string): string {
  if (typeof state !== "string") {
    throw new HttpsError("invalid-argument", `${fieldName} state must be a string`);
  }

  const normalized = state.trim().toUpperCase();
  if (!VALID_US_STATES.has(normalized)) {
    throw new HttpsError("invalid-argument", `Invalid US state in ${fieldName}: ${state}`);
  }

  return normalized;
}

function validateZipCode(zip: unknown, fieldName: string): string {
  if (typeof zip !== "string") {
    throw new HttpsError("invalid-argument", `${fieldName} zip must be a string`);
  }

  const trimmed = zip.trim();
  // US ZIP: 5 digits or 5+4
  if (!/^\d{5}(-\d{4})?$/.test(trimmed)) {
    throw new HttpsError("invalid-argument", `Invalid ZIP code format in ${fieldName}: ${zip}`);
  }

  return trimmed;
}

type AddressIn = {
  fullName?: string;
  address?: string;   // line1
  city?: string;
  state?: string;
  zip?: string;
  country?: string;   // may be missing from client -> we will default to US
  phone?: string;
};

type ParcelIn = {
  weightOz: number;     // in ounces
  lengthIn: number;     // inches
  widthIn: number;      // inches
  heightIn: number;     // inches
};

export const ShippoShipmentGetRates = onCall(
  { region: "us-central1", secrets: [SHIPPO_TEST_KEY] },
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

    const key = SHIPPO_TEST_KEY.value();
    if (!key) throw new HttpsError("internal", "Missing Shippo API key");

    const { to, from, parcel } = req.data as {
      to: AddressIn;
      from: AddressIn;
      parcel: ParcelIn;
      carrier?: string;
      service?: string;
    } || {};

    // Basic validation
    if (!to || !from || !parcel) {
      throw new HttpsError("invalid-argument", "Missing to/from/parcel");
    }
    if (!to.address || !to.city || !to.state || !to.zip) {
      throw new HttpsError("invalid-argument", "Incomplete 'to' address");
    }
    if (!from.address || !from.city || !from.state || !from.zip) {
      throw new HttpsError("invalid-argument", "Incomplete 'from' address");
    }
    if (!parcel.weightOz || !parcel.lengthIn || !parcel.widthIn || !parcel.heightIn) {
      throw new HttpsError("invalid-argument", "Incomplete parcel");
    }

    // Validate state and ZIP formats
    const validatedToState = validateUSState(to.state, "to");
    const validatedToZip = validateZipCode(to.zip, "to");
    const validatedFromState = validateUSState(from.state, "from");
    const validatedFromZip = validateZipCode(from.zip, "from");

    // Default countries to US if omitted
    const toCountry = (to.country || "US").toUpperCase();
    const fromCountry = (from.country || "US").toUpperCase();

    // Build Shippo shipment payload with validated addresses
    const shipmentPayload = {
      address_to: {
        name: to.fullName || "",
        street1: to.address,
        city: to.city,
        state: validatedToState,
        zip: validatedToZip,
        country: toCountry,
        phone: to.phone || undefined,
      },
      address_from: {
        name: from.fullName || "",
        street1: from.address,
        city: from.city,
        state: validatedFromState,
        zip: validatedFromZip,
        country: fromCountry,
        phone: from.phone || undefined,
      },
      parcels: [
        {
          weight: Number((parcel.weightOz / OUNCES_PER_POUND).toFixed(2)),
          mass_unit: "lb",
          length: Number(parcel.lengthIn.toFixed(2)),
          width: Number(parcel.widthIn.toFixed(2)),
          height: Number(parcel.heightIn.toFixed(2)),
          distance_unit: "in",
        },
      ],
      async: false,
    };

    // Create shipment to get rates
    const resp = await fetch(`${SHIPPO_API}/shipments/`, {
      method: "POST",
      headers: authHeader(key),
      body: JSON.stringify(shipmentPayload),
    });

    const shipment: any = await resp.json();
    console.log("[Shippo] create shipment status", resp.status, "body", shipment);

    if (!resp.ok) {
      // Surface Shippo’s error message
      throw new HttpsError("internal", `Shippo error ${resp.status}: ${JSON.stringify(shipment)}`);
    }

    const rates = (shipment?.rates || []).filter((r: any) => r?.carrier === "USPS");
    if (!rates.length) {
      throw new HttpsError("failed-precondition", "No USPS rates returned");
    }

    // Optional: store a little audit under the user for debugging
    await admin
      .firestore()
      .collection("users")
      .doc(uid)
      .collection("shippo_debug")
      .doc(shipment.object_id)
      .set({
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        shipmentId: shipment.object_id,
        rateCount: rates.length,
      });

    // Return minimal clean data to the app
    return {
      shipmentId: shipment.object_id,
      rates: rates.map((r: any) => ({
        object_id: r.object_id,
        servicelevel_name: r.servicelevel?.name,
        servicelevel_token: r.servicelevel?.token,
        amount: r.amount,          // string like "8.95"
        currency: r.currency,      // "USD"
        estimated_days: r.estimated_days,
        provider: r.provider,      // "USPS"
        carrier: r.carrier,        // "USPS"
      })),
    };
  }
);