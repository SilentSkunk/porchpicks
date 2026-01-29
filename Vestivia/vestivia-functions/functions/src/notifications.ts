// functions/src/notifications.ts
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

// Ensure Admin SDK is initialized even when this module is imported directly
if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

/**
 * saveFcmToken
 * Callable that stores the caller's FCM token under:
 *   users/{uid}/fcmTokens/{token}
 * Adds platform (optional) and timestamps.
 */
export const saveFcmToken = onCall({ region: "us-central1" }, async (req) => {
  if (!req.auth?.uid) {
    throw new HttpsError("unauthenticated", "Auth required.");
  }

  const token = String(req.data?.token || "").trim();
  const platform = String(req.data?.platform || "").trim().toLowerCase();

  if (!token) {
    throw new HttpsError("failed-precondition", "token is required.");
  }

  const now = admin.firestore.FieldValue.serverTimestamp();

  const docRef = db
    .collection("users")
    .doc(req.auth.uid)
    .collection("fcmTokens")
    .doc(token);

  await docRef.set(
    {
      active: true,
      platform: platform || null,
      updatedAt: now,
      createdAt: now,
    },
    { merge: true }
  );

  // Also mirror into top-level arrays for legacy clients / dashboards (best-effort)
  const userRef = db.collection("users").doc(req.auth.uid);
  await userRef.set(
    {
      // last seen single token copy (legacy)
      fcmToken: token,
      // ensure token appears in arrays
      fcmTokens: admin.firestore.FieldValue.arrayUnion(token),
      messagingTokens: admin.firestore.FieldValue.arrayUnion(token),
      fcmUpdatedAt: now,
    },
    { merge: true }
  );

  console.log("[NOTIF] saveFcmToken ok", {
    uid: req.auth.uid,
    platform: platform || "unknown",
    tokenPrefix: token.slice(0, 12) + "…",
  });

  return { ok: true };
});

/**
 * Collect all known FCM tokens for a user from:
 *  - users/{uid}/fcmTokens subcollection (active !== false)
 *  - users/{uid} doc fields: fcmToken (string), fcmTokens (array), messagingTokens (array)
 */
async function getAllUserFcmTokens(uid: string): Promise<string[]> {
  const tokens: string[] = [];

  // Parallel execution for better performance
  const [subSnap, userDoc] = await Promise.all([
    db.collection("users").doc(uid).collection("fcmTokens").get(),
    db.collection("users").doc(uid).get(),
  ]);

  // 1) subcollection documents
  const subTokens = subSnap.docs
    .filter((d) => (d.data() as any)?.active !== false)
    .map((d) => d.id)
    .filter(Boolean);

  tokens.push(...subTokens);

  // 2) top-level arrays / fields
  const user = userDoc.data() || {};

  const topSingle = typeof user["fcmToken"] === "string" ? [user["fcmToken"]] : [];
  const topArray = Array.isArray(user["fcmTokens"]) ? user["fcmTokens"] : [];
  const topMsgArray = Array.isArray(user["messagingTokens"])
    ? user["messagingTokens"]
    : [];

  tokens.push(
    ...topSingle.filter(Boolean),
    ...topArray.filter(Boolean),
    ...topMsgArray.filter(Boolean)
  );

  // Dedupe + sanitize
  const deduped = Array.from(new Set(tokens.map((t) => String(t).trim()))).filter(
    (t) => !!t
  );

  console.log("[NOTIF] tokens:aggregate", {
    uid,
    subCount: subTokens.length,
    topSingle: topSingle.length,
    topArray: topArray.length,
    topMsgArray: topMsgArray.length,
    totalUnique: deduped.length,
    samples: deduped.slice(0, 3).map((t) => t.slice(0, 12) + "…"),
  });

  return deduped;
}

/**
 * onMatchInboxNotify
 * Fires when a new match inbox doc is created:
 *   users/{uid}/matchInbox/{listingId}
 * Includes a deep link in the payload (data.deeplink) so the app can open the listing.
 */
export const onMatchInboxNotify = onDocumentCreated(
  { region: "us-central1", document: "users/{uid}/matchInbox/{listingId}" },
  async (event) => {
    const uid = event.params.uid as string;
    const listingId = event.params.listingId as string;

    const snap = event.data;
    if (!snap) {
      console.log("[NOTIF] no event data; exiting", { uid, listingId });
      return;
    }

    const data = snap.data() || {};
    console.log("[NOTIF] inbox:created", { uid, listingId, dataKeys: Object.keys(data) });

    // Collect tokens from all supported locations
    const tokens = await getAllUserFcmTokens(uid);

    if (!tokens.length) {
      console.log("[NOTIF] tokens:none – skipping push", { uid, listingId });
      return;
    }

    const brandLower: string = String(data["brandLower"] ?? "");
    const score: number | null =
      typeof data["score"] === "number" ? (data["score"] as number) : null;

    const title = "We found a match!";
    const body = brandLower
      ? `New ${brandLower.toUpperCase()} listing matched your pattern`
      : "A new listing matched your saved pattern.";

    // Deep link your iOS app can handle (adjust scheme/host to your app)
    const deeplink = `vestivia://listing/${encodeURIComponent(listingId)}`;

    // Optional image to show in the notification (if client supports it)
    const imageUrl: string | undefined =
      typeof data["primaryImageUrl"] === "string" && data["primaryImageUrl"]
        ? String(data["primaryImageUrl"])
        : undefined;

    // Build notification object - only include imageUrl if defined
    const notification: admin.messaging.Notification = { title, body };
    if (imageUrl) {
      notification.imageUrl = imageUrl;
    }

    // Build fcmOptions - only include imageUrl if defined
    const apnsFcmOptions: admin.messaging.ApnsFcmOptions = {
      analyticsLabel: "match_inbox",
    };
    if (imageUrl) {
      apnsFcmOptions.imageUrl = imageUrl;
    }

    const message: admin.messaging.MulticastMessage = {
      tokens,
      notification,
      data: {
        type: "match",
        listingId: String(data["listingId"] ?? listingId ?? ""),
        brandLower: brandLower,
        score: score != null ? String(score) : "",
        deeplink,
      },
      android: { priority: "high" },
      apns: {
        payload: {
          aps: {
            alert: { title, body },
            sound: "default",
            badge: 1,
          },
        },
        fcmOptions: apnsFcmOptions,
      },
    };

    try {
      console.log("[NOTIF] push:send:start", { uid, listingId, tokensTried: tokens.length });
      const res = await admin.messaging().sendEachForMulticast(message);
      console.log("[NOTIF] push:send:done", {
        uid,
        listingId,
        tokensTried: tokens.length,
        successCount: res.successCount,
        failureCount: res.failureCount,
      });

      // Remove invalid tokens
      const invalid: string[] = [];
      res.responses.forEach((r, i) => {
        if (!r.success) {
          const code = r.error?.code || "";
          const msg = r.error?.message || "";
          const isInvalid =
            code.includes("registration-token-not-registered") ||
            code.includes("messaging/registration-token-not-registered") ||
            msg.toLowerCase().includes("unregistered") ||
            msg.toLowerCase().includes("not registered");

          const token = tokens[i];
          if (isInvalid && token) invalid.push(token);

          console.log("[NOTIF] push:send:error", {
            idx: i,
            code,
            message: msg,
            token: token ? token.slice(0, 12) + "…" : "unknown",
          });
        }
      });

      if (invalid.length) {
        // Split into chunks of 500 (Firestore batch limit)
        const BATCH_SIZE = 500;
        const chunks: string[][] = [];

        for (let i = 0; i < invalid.length; i += BATCH_SIZE) {
          chunks.push(invalid.slice(i, i + BATCH_SIZE));
        }

        // Process each chunk in parallel
        await Promise.all(
          chunks.map(async (chunk) => {
            const batch = db.batch();
            chunk.forEach((t) => {
              batch.delete(
                db.collection("users").doc(uid).collection("fcmTokens").doc(t)
              );
            });
            await batch.commit();
          })
        );

        console.log("[NOTIF] tokens:pruned", { count: invalid.length, batches: chunks.length });
      }
    } catch (err: any) {
      console.error("[NOTIF] push:send:fatal", {
        uid,
        listingId,
        error: String(err?.message || err),
      });
    }
  }
);