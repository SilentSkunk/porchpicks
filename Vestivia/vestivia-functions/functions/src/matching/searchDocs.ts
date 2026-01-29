import * as admin from "firebase-admin";
import { hammingHex } from "../hashing";
import type { MatchContext } from "./types";

const db = admin.firestore();
const scoreFor = (dist: number) => 1 - dist / 64;

export async function matchAgainstSearchDocs(ctx: MatchContext): Promise<number> {
  const { brandLower, listingId, listingPhash, sellerUid, listingRefPath, bucketName, PHASH_THRESHOLD } = ctx;

  console.time("[LISTING_MATCH] q:patternSearches");
  const snap = await db.collectionGroup("patternSearches")
    .where("brandLower", "==", brandLower)
    .where("isActive", "==", true)
    .get();
  console.timeEnd("[LISTING_MATCH] q:patternSearches");
  console.log("[LISTING_MATCH] buyers.count", { count: snap.size });

  if (snap.empty) return 0;

  const batch = db.batch();
  let count = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    const uid = doc.ref.parent.parent?.id;
    if (!uid) continue;

    let buyerPhash: string | undefined = data["phash"] as string | undefined;

    if (!buyerPhash) {
      const imagePath = data["imagePath"] as string | undefined;
      if (!imagePath) continue;
      try {
        const [buf] = await admin.storage().bucket(bucketName).file(imagePath).download();
        const { computeHexPHashFromBuffer } = await import("../hashing");
        buyerPhash = await computeHexPHashFromBuffer(buf);
      } catch (e) {
        console.warn("[LISTING_MATCH] buyer image download/hash failed", { imagePath, err: String(e) });
        continue;
      }
    }

    const dist = hammingHex(listingPhash, buyerPhash);
    if (dist <= PHASH_THRESHOLD) {
      const score = scoreFor(dist);
      count++;

      const inboxRef = db.collection("users").doc(uid).collection("matchInbox").doc(listingId);
      batch.set(inboxRef, {
        listingId,
        searchId: doc.id,
        brandLower,
        score,
        listingRef: listingRefPath ?? null,
        sellerUid: sellerUid ?? null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        seen: false,
      }, { merge: true });

      const auditRef = db.collection("matches_by_listing").doc(listingId).collection("hits").doc(uid);
      batch.set(auditRef, {
        uid,
        searchId: doc.id,
        brandLower,
        score,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
  }

  if (count) await batch.commit();
  return count;
}