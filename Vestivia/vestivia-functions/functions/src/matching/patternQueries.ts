import * as admin from "firebase-admin";
import { hammingHex } from "../hashing";
import type { MatchContext } from "./types";

const scoreFor = (dist: number) => 1 - dist / 64;

export async function matchAgainstPatternQueries(ctx: MatchContext): Promise<number> {
  const { brandLower, listingId, listingPhash, bucketName, sellerUid, listingRefPath, PHASH_THRESHOLD } = ctx;

  console.time("[LISTING_MATCH] scan:pattern_queries");
  const [files] = await admin.storage().bucket(bucketName).getFiles({
    prefix: `pattern_queries/${brandLower}/`,
    autoPaginate: true,
  });
  console.timeEnd("[LISTING_MATCH] scan:pattern_queries");
  console.log("[LISTING_MATCH] pattern_queries.count", { count: files.length });

  if (!files.length) return 0;

  const db = admin.firestore();
  const batch = db.batch();
  let count = 0;

  for (const f of files) {
    try {
      const filePath = f.name; // pattern_queries/{brandLower}/{uid}/{file}.jpg
      const parts = filePath.split("/");
      const maybeUid = parts.length >= 3 ? parts[2] : undefined;
      if (!maybeUid) continue;

      const [buf] = await f.download();
      const { computeHexPHashFromBuffer } = await import("../hashing");
      const buyerPhash = await computeHexPHashFromBuffer(buf);

      const dist = hammingHex(listingPhash, buyerPhash);
      if (dist <= PHASH_THRESHOLD) {
        const score = scoreFor(dist);
        count++;

        const inboxRef = db.collection("users").doc(maybeUid)
          .collection("matchInbox").doc(listingId);

        batch.set(inboxRef, {
          listingId,
          searchId: null,
          brandLower,
          score,
          listingRef: listingRefPath ?? null,
          sellerUid: sellerUid ?? null,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          seen: false,
        }, { merge: true });
      }
    } catch (e) {
      console.warn("[LISTING_MATCH] pattern_queries file failed", { name: f.name, err: String(e) });
    }
  }

  if (count) await batch.commit();
  return count;
}