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

    const { to, from, parcel, listingId } = req.data as {
      to: AddressIn;
      from?: AddressIn;
      parcel?: ParcelIn;
      listingId?: string;
      carrier?: string;
      service?: string;
    } || {};

    // Validate buyer's address (to)
    if (!to) {
      throw new HttpsError("invalid-argument", "Missing 'to' address");
    }
    if (!to.address || !to.city || !to.state || !to.zip) {
      throw new HttpsError("invalid-argument", "Incomplete 'to' address");
    }

    // Validate state and ZIP formats for buyer
    const validatedToState = validateUSState(to.state, "to");
    const validatedToZip = validateZipCode(to.zip, "to");

    // Determine seller address: use provided 'from' or look up from listing
    let sellerAddress: AddressIn;
    if (from && from.address && from.city && from.state && from.zip) {
      sellerAddress = from;
    } else if (listingId) {
      // Look up the listing to find the seller
      // First try all_listings (public mirror)
      const allListingsDoc = await admin.firestore()
        .collection("all_listings")
        .doc(listingId)
        .get();

      let listingData: FirebaseFirestore.DocumentData | undefined;

      if (allListingsDoc.exists) {
        listingData = allListingsDoc.data();
      } else {
        // If not in all_listings, try collection group query on listings subcollections
        console.log(`[Shippo] Listing ${listingId} not in all_listings, trying collection group`);
        const groupQuery = await admin.firestore()
          .collectionGroup("listings")
          .where("listingID", "==", listingId)
          .limit(1)
          .get();

        const firstDoc = groupQuery.docs[0];
        if (firstDoc) {
          listingData = firstDoc.data();
        }
      }

      if (!listingData) {
        console.log(`[Shippo] Listing ${listingId} not found anywhere`);
        throw new HttpsError("not-found", `Listing not found: ${listingId}`);
      }
      const sellerId = listingData?.["userId"] as string | undefined;
      if (!sellerId) {
        throw new HttpsError("internal", "Listing has no seller");
      }

      // Look up seller's shipping address
      const sellerDoc = await admin.firestore()
        .collection("users")
        .doc(sellerId)
        .get();

      if (!sellerDoc.exists) {
        throw new HttpsError("not-found", "Seller not found");
      }

      const sellerData = sellerDoc.data();
      const addr = (sellerData?.["shippingAddress"] || sellerData?.["address"]) as AddressIn | undefined;

      if (!addr || !addr.address || !addr.city || !addr.state || !addr.zip) {
        throw new HttpsError("failed-precondition", "Seller has no shipping address configured");
      }

      sellerAddress = {
        fullName: addr.fullName || (sellerData?.["displayName"] as string) || (sellerData?.["username"] as string) || "",
        address: addr.address,
        city: addr.city,
        state: addr.state,
        zip: addr.zip,
        country: addr.country || "US",
      };
      if (addr.phone) {
        sellerAddress.phone = addr.phone;
      }
    } else {
      throw new HttpsError("invalid-argument", "Missing 'from' address or 'listingId'");
    }

    // Validate seller address
    if (!sellerAddress.address || !sellerAddress.city || !sellerAddress.state || !sellerAddress.zip) {
      throw new HttpsError("invalid-argument", "Incomplete seller address");
    }

    const validatedFromState = validateUSState(sellerAddress.state, "from");
    const validatedFromZip = validateZipCode(sellerAddress.zip, "from");

    // Determine parcel dimensions: use provided or default for clothing
    const parcelInfo: ParcelIn = parcel && parcel.weightOz && parcel.lengthIn && parcel.widthIn && parcel.heightIn
      ? parcel
      : {
          // Default parcel for clothing: ~1 lb, standard poly mailer size
          weightOz: 16,    // 1 pound
          lengthIn: 12,    // 12 inches
          widthIn: 9,      // 9 inches
          heightIn: 2,     // 2 inches (folded clothing)
        };

    // Default countries to US if omitted
    const toCountry = (to.country || "US").toUpperCase();
    const fromCountry = (sellerAddress.country || "US").toUpperCase();

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
        name: sellerAddress.fullName || "",
        street1: sellerAddress.address,
        city: sellerAddress.city,
        state: validatedFromState,
        zip: validatedFromZip,
        country: fromCountry,
        phone: sellerAddress.phone || undefined,
      },
      parcels: [
        {
          weight: Number((parcelInfo.weightOz / OUNCES_PER_POUND).toFixed(2)),
          mass_unit: "lb",
          length: Number(parcelInfo.lengthIn.toFixed(2)),
          width: Number(parcelInfo.widthIn.toFixed(2)),
          height: Number(parcelInfo.heightIn.toFixed(2)),
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