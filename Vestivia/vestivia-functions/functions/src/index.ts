import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";
import crypto from "crypto";
import { onObjectFinalized } from "firebase-functions/v2/storage";
import * as admin from "firebase-admin";
import { computeHexPHashFromBuffer, hammingHex } from "./hashing";

// ─────────────── Secrets ───────────────
const ALGOLIA_APP_ID        = defineSecret("ALGOLIA_APP_ID");
const ALGOLIA_SEARCH_API_KEY = defineSecret("ALGOLIA_SEARCH_API_KEY");

const CF_IMAGES_TOKEN = defineSecret("CF_IMAGES_TOKEN");
const CF_ACCOUNT_ID   = defineSecret("CF_ACCOUNT_ID");
const CF_ACCOUNT_HASH = defineSecret("CF_ACCOUNT_HASH"); // optional, for imagedelivery.net links
const CLOUDFLARE_SIGNKEY = defineSecret("CLOUDFLARE_SIGNKEY");


// ─────────────── Admin init ───────────────
try { admin.initializeApp(); } catch {}
const db = admin.firestore();
const bucketFor = (b?: string) => admin.storage().bucket(b);

// ─────────────── Algolia Key Cache ───────────────
interface CachedAlgoliaKey {
  key: string;
  appId: string;
  expiresAt: number;
  userToken: string;
  filters: string | null;
  cachedAt: number;
}
const algoliaKeyCache = new Map<string, CachedAlgoliaKey>();
const ALGOLIA_CACHE_TTL_MS = 14 * 60 * 1000; // 14 minutes (keys expire at 15)

function cleanupAlgoliaCache() {
  const now = Date.now();
  for (const [cacheKey, cached] of algoliaKeyCache) {
    if (now - cached.cachedAt > ALGOLIA_CACHE_TTL_MS) {
      algoliaKeyCache.delete(cacheKey);
    }
  }
}

function getAlgoliaCacheKey(uid: string, filters: string | null): string {
  return `${uid}:${filters || ""}`;
}

// ─────────────── Helpers ───────────────
function requireAuth(uid?: string) {
  if (!uid) throw new HttpsError("unauthenticated", "Auth required.");
}
function assertString(v: unknown, name: string): string {
  if (typeof v !== "string" || !v.trim()) {
    throw new HttpsError("failed-precondition", `Missing or invalid ${name}`);
  }
  return v;
}
function logErr(ctx: string, err: unknown) {
  if (err instanceof HttpsError) {
    console.error(`[${ctx}] HttpsError`, { code: err.code, message: err.message, details: err.details });
  } else {
    console.error(`[${ctx}]`, err);
  }
}

// ---- Query debug helpers ----
function logQueryError(err: any, label: string, params: Record<string, any>) {
  console.error(`[QERR] ${label}`, {
    params,
    code: (err && (err.code || err?.details?.code)) || undefined,
    details: err?.details || undefined,
    message: String(err),
  });
}

async function probeCgQuery<T>(label: string, q: FirebaseFirestore.Query<T>) {
  const t0 = Date.now();
  try {
    const snap = await q.get();
    console.log(`[Q] ${label} ok`, { count: snap.size, ms: Date.now() - t0 });
    return snap;
  } catch (err) {
    console.error(`[Q] ${label} error`, { ms: Date.now() - t0, message: String(err), code: (err as any)?.code });
    throw err;
  }
}

/**
 * Generate a secured Algolia API key without depending on algoliasearch typings.
 * See https://www.algolia.com/doc/guides/security/api-keys/how-to/user-restricted-access-to-data/
 */
function generateSecuredApiKeyLocal(searchKey: string, restrictions: Record<string, string | number | boolean>) {
  // Build a stable querystring from restrictions
  const params = new URLSearchParams();
  Object.keys(restrictions)
    .sort()
    .forEach((k) => {
      const v = restrictions[k];
      if (v === undefined || v === null) return;
      params.append(k, String(v));
    });
  const queryString = params.toString();

  // Signature is HMAC-SHA256(queryString, searchKey) as hex
  const signature = crypto.createHmac("sha256", searchKey).update(queryString).digest("hex");

  // Secured key is base64(signature + queryString)
  const secured = Buffer.from(signature + queryString).toString("base64");
  return secured;
}

// ─────────────── Image matching utils ───────────────
const PHASH_THRESHOLD = 14; // tune 12–16
// Confidence score is derived as 1 - (hammingDistance / 64). Logged and stored with each hit.

// ───────── 1) Algolia secured search key (with caching) ─────────
export const getSecuredSearchKey = onCall(
  { region: "us-central1", secrets: [ALGOLIA_APP_ID, ALGOLIA_SEARCH_API_KEY] },
  async (req) => {
    requireAuth(req.auth?.uid);
    const uid = req.auth!.uid;

    const filters = typeof req.data?.filters === "string" && req.data.filters.trim()
      ? req.data.filters.trim()
      : null;

    // Check cache first
    const cacheKey = getAlgoliaCacheKey(uid, filters);
    const cached = algoliaKeyCache.get(cacheKey);
    const now = Date.now();

    if (cached && (now - cached.cachedAt) < ALGOLIA_CACHE_TTL_MS) {
      console.log("[ALG] cache hit", {
        uid,
        filters: filters || "(none)",
        cacheAgeMs: now - cached.cachedAt,
      });
      return {
        appId: cached.appId,
        key: cached.key,
        expiresAt: cached.expiresAt,
        userToken: cached.userToken,
        filters: cached.filters,
      };
    }

    // Cache miss - generate new key
    const appId = assertString(ALGOLIA_APP_ID.value(), "ALGOLIA_APP_ID");
    const searchKey = assertString(ALGOLIA_SEARCH_API_KEY.value(), "ALGOLIA_SEARCH_API_KEY");

    const nowSec = Math.floor(now / 1000);
    const restrictions: Record<string, string | number | boolean> = {
      restrictIndices: "LoomPair",
      userToken: uid,
      validUntil: nowSec + 15 * 60,
    };

    if (filters) {
      restrictions["filters"] = filters;
    }

    const key = generateSecuredApiKeyLocal(searchKey, restrictions);

    // Store in cache
    const cacheEntry: CachedAlgoliaKey = {
      key,
      appId,
      expiresAt: restrictions["validUntil"] as number,
      userToken: uid,
      filters,
      cachedAt: now,
    };
    algoliaKeyCache.set(cacheKey, cacheEntry);

    // Periodic cleanup (every 100 cache sets)
    if (algoliaKeyCache.size % 100 === 0) {
      cleanupAlgoliaCache();
    }

    console.log("[ALG] cache miss - issued new key", {
      uid,
      restrictIndices: restrictions["restrictIndices"],
      exp: restrictions["validUntil"],
      filters: filters || "(none)",
      cacheSize: algoliaKeyCache.size,
    });

    return {
      appId,
      key,
      expiresAt: restrictions["validUntil"] as number,
      userToken: uid,
      filters,
    };
  }
);

// ───────── 2) Cloudflare Images: get direct-upload URL (v2) with JSON + multipart fallback ─────────
export const getCFDirectUploadURL = onCall(
  { region: "us-central1", secrets: [CF_IMAGES_TOKEN, CF_ACCOUNT_ID, CF_ACCOUNT_HASH] },
  async (req) => {
    try {
      requireAuth(req.auth?.uid);

      const token       = assertString(CF_IMAGES_TOKEN.value(), "CF_IMAGES_TOKEN").trim();
      const accountId   = assertString(CF_ACCOUNT_ID.value(), "CF_ACCOUNT_ID").trim();
      const accountHash = (CF_ACCOUNT_HASH.value() ?? "").trim(); // optional; for UI

      const requireSigned = typeof req.data?.requireSignedURLs === "boolean"
        ? !!req.data.requireSignedURLs
        : true;

      console.log("[CF] direct_upload v2 (multipart) start", {
        uid: req.auth!.uid,
        requireSigned,
        accountId: accountId.slice(0, 6) + "…",
      });

      // v2 requires multipart/form-data body
      const fd = new FormData();
      // Optional fields supported by v2:
      if (typeof req.data?.customId === "string" && req.data.customId.trim()) {
        fd.append("id", req.data.customId.trim());
      }
      if (typeof req.data?.expiry === "string" && req.data.expiry.trim()) {
        fd.append("expiry", req.data.expiry.trim()); // RFC3339 timestamp if provided
      }
      fd.append("requireSignedURLs", requireSigned ? "true" : "false");

      const resp = await fetch(
        `https://api.cloudflare.com/client/v4/accounts/${accountId}/images/v2/direct_upload`,
        {
          method: "POST",
          headers: {
            // Do NOT set Content-Type; fetch sets the multipart boundary automatically
            Authorization: `Bearer ${token}`,
          },
          body: fd,
        }
      );

      const text = await resp.text();
      if (!resp.ok) {
        console.error("[CF] direct_upload v2 failed", { status: resp.status, body: text.slice(0, 800) });
        let msg = `Cloudflare direct_upload failed (status ${resp.status})`;
        try {
          const j = JSON.parse(text);
          if (j?.errors?.[0]?.message) msg += `: ${j.errors[0].message}`;
        } catch {}
        throw new HttpsError("failed-precondition", msg);
      }

      let json: any;
      try { json = JSON.parse(text); } catch (e) {
        console.error("[CF] parse error", e, text.slice(0, 800));
        throw new HttpsError("internal", "Could not parse Cloudflare response.");
      }

      const uploadURL: string | undefined = json?.result?.uploadURL;
      if (!uploadURL) {
        console.error("[CF] missing uploadURL", json);
        throw new HttpsError("internal", "Cloudflare did not return an uploadURL.");
      }

      console.log("[CF] direct_upload v2 OK");
      return { uploadURL, accountHash };
    } catch (err) {
      logErr("getCFDirectUploadURL", err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", "Unexpected error creating direct upload URL.");
    }
  }
);

// ───────── 3) Signed image delivery URL (direct Cloudflare Images) ─────────
export const getSignedImageUrl = onCall(
  { region: "us-central1", secrets: [CLOUDFLARE_SIGNKEY, CF_ACCOUNT_HASH] },
  async (req) => {
    try {
      // requireAuth(req.auth?.uid);

      const hash = assertString(CF_ACCOUNT_HASH.value(), "CF_ACCOUNT_HASH");
      const signKey = assertString(CLOUDFLARE_SIGNKEY.value(), "CLOUDFLARE_SIGNKEY");

      // accept either "id" or legacy "imageId"
      const id =
        typeof req.data?.id === "string" && req.data.id.trim()
          ? req.data.id.trim()
          : assertString(req.data?.imageId, "id");

      let variant =
        typeof req.data?.variant === "string" && req.data.variant.trim()
          ? req.data.variant.trim()
          : "card";

      const ttlSec =
        Number.isFinite(req.data?.ttlSec)
          ? Math.max(60, Math.min(6 * 3600, Number(req.data.ttlSec)))
          : 3600;
      const exp = Math.floor(Date.now() / 1000) + ttlSec;

      const path = `/${hash}/${id}/${variant}?exp=${exp}`;
      const sig = crypto.createHmac("sha256", signKey).update(path).digest("hex");
      const url = `https://imagedelivery.net/${hash}/${id}/${variant}?exp=${exp}&sig=${sig}`;

      // Optional probe for sanity (HEAD) if caller passes { probe: true }
      let status = 0;
      if (req.data?.probe === true) {
        try {
          const r = await fetch(url, { method: "HEAD" });
          status = r.status;
        } catch {
          status = -1;
        }
      }

      console.log("[CF] signed_url issued", {
        uid: req.auth?.uid ?? null,
        id,
        variant,
        exp,
        status,
      });

      return { ok: true, url, exp, variant, status };
    } catch (err) {
      logErr("getSignedImageUrl", err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", "Unexpected error creating signed image URL.");
    }
  }
);

// ───────── 3b) Batch signed image delivery URLs (direct Cloudflare Images) ─────────
export const getSignedImageUrls = onCall(
  { region: "us-central1", secrets: [CLOUDFLARE_SIGNKEY, CF_ACCOUNT_HASH] },
  async (req) => {
    try {
      // requireAuth(req.auth?.uid);

      const hash = assertString(CF_ACCOUNT_HASH.value(), "CF_ACCOUNT_HASH");
      const signKey = assertString(CLOUDFLARE_SIGNKEY.value(), "CLOUDFLARE_SIGNKEY");

      const rawIds = Array.isArray(req.data?.ids)
        ? req.data.ids
        : Array.isArray(req.data?.imageIds)
          ? req.data.imageIds
          : [];

      const ids: string[] = rawIds
        .filter((v: unknown) => typeof v === "string")
        .map((s: string) => s.trim())
        .filter(Boolean);

      if (!ids.length) {
        return { ok: true, urls: [], exp: Math.floor(Date.now() / 1000), variant: "card", count: 0 };
      }

      let variant =
        typeof req.data?.variant === "string" && req.data.variant.trim()
          ? req.data.variant.trim()
          : "card";

      const ttlSec =
        Number.isFinite(req.data?.ttlSec)
          ? Math.max(60, Math.min(6 * 3600, Number(req.data.ttlSec)))
          : 3600;
      const exp = Math.floor(Date.now() / 1000) + ttlSec;

      const MAX = 50;
      const safeIds = ids.slice(0, MAX);

      const urls = safeIds.map((id) => {
        const path = `/${hash}/${id}/${variant}?exp=${exp}`;
        const sig = crypto.createHmac("sha256", signKey).update(path).digest("hex");
        return `https://imagedelivery.net/${hash}/${id}/${variant}?exp=${exp}&sig=${sig}`;
      });

      console.log("[CF] batch signed_urls issued", {
        uid: req.auth?.uid ?? null,
        variant,
        exp,
        count: urls.length,
        capped: ids.length > MAX,
      });

      return { ok: true, urls, exp, variant, count: urls.length, capped: ids.length > MAX };
    } catch (err) {
      logErr("getSignedImageUrls", err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", "Unexpected error creating signed image URLs.");
    }
  }
);

// ───────── 4) Listing pattern uploaded → match buyers ─────────
export const onListingPatternUpload = onObjectFinalized({ bucket: "vest-9495e.firebasestorage.app", region: "us-central1", memory: "512MiB", timeoutSeconds: 120 }, async (event) => {
  try {
    const name = event.data?.name || "";
    const bucket = event.data?.bucket || undefined;
    console.log("[LISTING_MATCH] trigger", { name, bucket });
    if (!name.startsWith("active_listing_patterns/brands/")) return;

    // Expected: active_listing_patterns/brands/{brandLower}/{listingId}/pattern.jpg
    const parts = name.split("/");
    // [0] active_listing_patterns, [1] brands, [2] brandLower, [3] listingId, [4] pattern.jpg
    if (parts.length < 5) return;
    const brandLower = (parts[2] || "").toLowerCase();
    const listingId = parts[3];
    if (!listingId) return;
    console.log("[LISTING_MATCH] parsed", { brandLower, listingId });

    // Compute pHash for listing image (with defensive checks)
    let buf: Buffer;
    console.log("[LISTING_MATCH] download:start", { name, bucket });
    try {
      [buf] = await bucketFor(bucket).file(name).download();
      console.log("[LISTING_MATCH] download:ok", { bytes: buf?.length ?? 0, ct: event.data?.contentType, gen: event.data?.generation });
    } catch (e) {
      console.error("[LISTING_MATCH] download:fail", { name, bucket, err: String(e) });
      return;
    }
    console.log("[LISTING_MATCH] phash:start");
    const listingPhash = await computeHexPHashFromBuffer(buf as Buffer); // 64-bit hex
    console.log("[LISTING_MATCH] phash:ok", { phash: listingPhash });

    // We no longer resolve the listing doc here; inbox entries won’t include listingRef/sellerUid.
    const sellerUid: string | null = null;
    const listingRefPath: string | null = null;

    // ── Compare against Storage-based query images ───────────────────────────
    const storageHitsBatch = db.batch();
    let storageMatchCount = 0;

    // Helper: sanitize a GCS path for use as a doc id
    const safeId = (p: string) => p.replace(/[/.#?\[\]]/g, "_");

    type PrefixSpec = { label: string; prefix: string; extractUid?: (p: string) => string | null };

    const prefixes: PrefixSpec[] = [
      // Static queries you may upload manually
      { label: "pattern_queries", prefix: `pattern_queries/${brandLower}/` },
      // Active buyer queries: users_active_patterns/{uid}/{brandLower}/...
      {
        label: "users_active_patterns",
        prefix: `users_active_patterns/`,
        extractUid: (p: string) => {
          // Expect: users_active_patterns/{uid}/{brandLower}/...
          const parts = p.split("/");
          if (parts.length >= 3 && parts[0] === "users_active_patterns" && (parts[2] || "").toLowerCase() === brandLower) {
            return parts[1] || null;
          }
          return null;
        },
      },
    ];

    for (const spec of prefixes) {
      try {
        // Paginate through files under the prefix, but cap total examined to avoid timeouts
        const MAX_FILES_SCAN = 1000; // safety cap per invocation
        const exts = [".jpg", ".jpeg", ".png", ".webp"];
        let pageToken: string | undefined = undefined;
        let collected: import("@google-cloud/storage").File[] = [];

        while (collected.length < MAX_FILES_SCAN) {
          const pageSize = Math.min(500, MAX_FILES_SCAN - collected.length);
          const getFilesOpts: import("@google-cloud/storage").GetFilesOptions = {
            prefix: spec.prefix,
            maxResults: pageSize,
            autoPaginate: false,
          };
          if (pageToken) {
            getFilesOpts.pageToken = pageToken;
          }
          const resp = await bucketFor(bucket).getFiles(getFilesOpts);

          // resp is a tuple; typings vary by version, so extract defensively
          const respAny = resp as unknown;
          const page = (respAny as [import("@google-cloud/storage").File[], unknown])[0];
          const meta = (respAny as [unknown, { pageToken?: string; nextPageToken?: string; nextPageRequest?: { pageToken?: string } } | null])[1];
          const nextPageToken: string | undefined =
            (meta && (meta.pageToken || meta.nextPageToken || meta.nextPageRequest?.pageToken)) || undefined;

          collected.push(...page);
          pageToken = nextPageToken;
          if (!pageToken) break;
        }

        // Filter to this brand when scanning users_active_patterns, and keep only images
        const brandFiltered = collected.filter((f) => {
          const nm = f.name || "";
          if (!nm || nm.endsWith("/")) return false; // skip pseudo-folders
          const lower = nm.toLowerCase();
          const isImage = exts.some((e) => lower.endsWith(e));
          if (!isImage) return false;

          if (spec.label === "users_active_patterns") {
            const segs = nm.split("/");
            // users_active_patterns/{uid}/{brandLower}/...
            return segs.length >= 3 && segs[0] === "users_active_patterns" && (segs[2] || "").toLowerCase() === brandLower;
          }
          // pattern_queries/{brandLower}/...
          return lower.startsWith(`pattern_queries/${brandLower}/`);
        });

        console.log("[LISTING_MATCH] storage:files", { label: spec.label, prefixTried: spec.prefix, count: brandFiltered.length, cappedAt: MAX_FILES_SCAN });

        let peeked = 0;
        for (const f of brandFiltered) {
          const filePath = f.name || "";
          if (!filePath || filePath.endsWith("/")) continue; // skip pseudo-folders
          const lowerPath = filePath.toLowerCase();
          if (!(lowerPath.endsWith(".jpg") || lowerPath.endsWith(".jpeg") || lowerPath.endsWith(".png") || lowerPath.endsWith(".webp"))) continue;

          let qbuf: Buffer | null = null;
          try {
            const dl = await f.download();
            qbuf = dl[0] as Buffer;
          } catch (e) {
            console.warn("[LISTING_MATCH] storage:download:fail", { path: filePath, err: String(e) });
            continue;
          }
          if (!qbuf || qbuf.length < 32) continue;

          // Compute query image pHash
          let qhash: string;
          try {
            qhash = await computeHexPHashFromBuffer(qbuf);
          } catch (e) {
            console.warn("[LISTING_MATCH] storage:phash:fail", { path: filePath, err: String(e) });
            continue;
          }

          const dist = hammingHex(listingPhash, qhash);
          if (peeked < 5) {
            console.log("[LISTING_MATCH] storage:compare", { label: spec.label, path: filePath, dist });
            peeked++;
          }

          if (dist <= PHASH_THRESHOLD) {
            storageMatchCount++;
            const score = 1 - dist / 64;
            const hitDoc = db.collection("matches_by_listing").doc(listingId).collection("storage_hits").doc(safeId(filePath));
            const uidFromPath = spec.extractUid ? spec.extractUid(filePath) : null;
            storageHitsBatch.set(
              hitDoc,
              {
                path: filePath,
                brandLower,
                score,
                phash: qhash,
                sourceLabel: spec.label,
                uid: uidFromPath || null,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
              },
              { merge: true }
            );

            // If the path encodes a buyer uid (users_active_patterns), also notify them directly
            if (uidFromPath) {
              const inboxRef = db.collection("users").doc(uidFromPath).collection("matchInbox").doc(listingId);
              storageHitsBatch.set(
                inboxRef,
                {
                  listingId,
                  sellerUid: null,
                  searchId: null,
                  brandLower,
                  score,
                  listingRef: null,
                  createdAt: admin.firestore.FieldValue.serverTimestamp(),
                  seen: false,
                  source: spec.label, // 'users_active_patterns'
                },
                { merge: true }
              );
            }
          }
        }
      } catch (e) {
        console.error("[LISTING_MATCH] storage:list:fail", { label: spec.label, prefix: spec.prefix, err: String(e) });
      }
    }

    if (storageMatchCount) {
      console.log("[LISTING_MATCH] storage:batch:commit:start", { storageMatchCount });
      await storageHitsBatch.commit();
      console.log("[LISTING_MATCH] storage:batch:commit:ok", { storageMatchCount });
    }

    console.log("[LISTING_MATCH] lookup:skipped", { reason: "listingRef resolution disabled" });

    // Candidate buyer searches for this brand (with composite-index fallback)
    let searchesDocs: FirebaseFirestore.QueryDocumentSnapshot[] = [];
    console.log("[LISTING_MATCH] searches:start", { brandLower });
    try {
      const activeSnap = await probeCgQuery(
        "patternSearches active (brandLower == & isActive == true)",
        db
          .collectionGroup("patternSearches")
          .where("brandLower", "==", brandLower)
          .where("isActive", "==", true)
      );
      searchesDocs = activeSnap.docs;
      console.log("[LISTING_MATCH] searches:end", { mode: "active", count: searchesDocs.length });
    } catch (err) {
      // Common when composite index isn't ready: FAILED_PRECONDITION
      logQueryError(err, "patternSearches active (composite failed) → fallback to brandOnly + in-memory filter", { brandLower });
      const brandOnlySnap = await probeCgQuery(
        "patternSearches brandOnly (fallback)",
        db.collectionGroup("patternSearches").where("brandLower", "==", brandLower)
      );
      searchesDocs = brandOnlySnap.docs.filter((d) => d.get("isActive") === true);
      console.log("[LISTING_MATCH] searches:end", { mode: "brandOnlyFallback", count: searchesDocs.length });
    }


    const batch = db.batch();
    let matchCount = 0;
    let inspected = 0;
    for (const s of searchesDocs) {
      const sPhash = s.get("phash") as string | undefined;
      if (!sPhash) continue;
      const uid = s.ref.parent.parent?.id; // users/{uid}/patternSearches
      if (!uid) continue;
      if (inspected < 5) {
        try {
          const sPhashPeek = s.get("phash") as string | undefined;
          if (sPhashPeek && uid) {
            const peekDist = hammingHex(listingPhash, sPhashPeek);
            console.log("[LISTING_MATCH] compare", { uid, searchId: s.id, dist: peekDist });
          }
        } catch {}
        inspected++;
      }
      const dist = hammingHex(listingPhash, sPhash);
      if (dist <= PHASH_THRESHOLD) {
        matchCount++;
        const score = 1 - dist / 64;
        // Audit record
        const auditRef = db.collection("matches_by_listing").doc(listingId).collection("hits").doc(uid);
        batch.set(auditRef, { uid, searchId: s.id, brandLower, score, createdAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
        // Inbox delivery
        const inboxRef = db.collection("users").doc(uid).collection("matchInbox").doc(listingId);
        batch.set(inboxRef, { listingId, sellerUid, searchId: s.id, brandLower, score, listingRef: listingRefPath, createdAt: admin.firestore.FieldValue.serverTimestamp(), seen: false }, { merge: true });
      }
    }

    if (matchCount) {
      console.log("[LISTING_MATCH] batch:commit:start", { matchCount });
      await batch.commit();
      console.log("[LISTING_MATCH] batch:commit:ok", { matchCount });
    }
    console.log("[LISTING_MATCH] done", { listingId, brandLower, matchCount });
  } catch (err) {
    console.error("[onListingPatternUpload]", err);
  }
});

// ───────── 5) Buyer pattern uploaded → backfill matches ─────────
export const onBuyerPatternUpload = onObjectFinalized(
  { bucket: "vest-9495e.firebasestorage.app", region: "us-central1", memory: "512MiB", timeoutSeconds: 120 },
  async (event) => {
    try {
      const name = event.data?.name || "";
      const bucket = event.data?.bucket || undefined;
      console.log("[SEARCH_BACKFILL] trigger", { name, bucket });

      // Only react to buyer uploads
      if (!name.startsWith("users_active_patterns/")) return;

      // Path: users_active_patterns/{uid}/{brandLower}/{searchId}.jpg
      const parts = name.split("/");
      if (parts.length < 4) return;
      const uid = parts[1];
      if (!uid) return;
      const brandLower = (parts[2] || "").toLowerCase();
      console.log("[SEARCH_BACKFILL] parsed", { uid, brandLower });

      // 1) Compute pHash for the buyer's image
      let buf2: Buffer;
      console.log("[SEARCH_BACKFILL] download:start", { name, bucket });
      try {
        [buf2] = await bucketFor(bucket).file(name).download();
        console.log("[SEARCH_BACKFILL] download:ok", {
          bytes: buf2?.length ?? 0,
          ct: event.data?.contentType,
          gen: event.data?.generation,
        });
      } catch (e) {
        console.error("[SEARCH_BACKFILL] download:fail", { name, bucket, err: String(e) });
        return;
      }

      console.log("[SEARCH_BACKFILL] phash:start");
      const searchPhash = await computeHexPHashFromBuffer(buf2 as Buffer);
      console.log("[SEARCH_BACKFILL] phash:ok", { phash: searchPhash });

      // 2) Upsert/locate a search doc (attach phash & imagePath)
      let searchRef = db.collection("users").doc(uid).collection("patternSearches").doc();
      const existing = await db
        .collection(`users/${uid}/patternSearches`)
        .where("brandLower", "==", brandLower)
        .where("imagePath", "==", name)
        .limit(1)
        .get();
      const existingDoc = existing.docs[0];
      if (existingDoc) searchRef = existingDoc.ref;

      await searchRef.set(
        {
          brandLower,
          imagePath: name,
          phash: searchPhash,
          isActive: true,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      console.log("[SEARCH_BACKFILL] searchRef", { path: searchRef.path, id: searchRef.id });

      // 3) Scan Storage for listing patterns for this brand
      const listingsPrefix = `active_listing_patterns/brands/${brandLower}/`;
      console.log("[SEARCH_BACKFILL] storage:list:start", { prefix: listingsPrefix });

      let files: import("@google-cloud/storage").File[] = [];
      try {
        const [all] = await bucketFor(bucket).getFiles({ prefix: listingsPrefix });
        // keep only actual pattern files (skip folders/other files)
        files = all.filter((f) => (f.name || "").endsWith("/pattern.jpg"));
        console.log("[SEARCH_BACKFILL] storage:list:ok", { total: all.length, filtered: files.length });
      } catch (e) {
        console.error("[SEARCH_BACKFILL] storage:list:fail", { prefix: listingsPrefix, err: String(e) });
        return;
      }

      // Helper to batch resolve listing mirrors
      async function batchResolveMirrors(listingIds: string[]): Promise<Map<string, { refPath: string | null; sellerUid: string | null }>> {
        const results = new Map<string, { refPath: string | null; sellerUid: string | null }>();

        if (listingIds.length === 0) return results;

        // Firestore getAll supports up to 100 documents per call
        const BATCH_SIZE = 100;
        const chunks: string[][] = [];
        for (let i = 0; i < listingIds.length; i += BATCH_SIZE) {
          chunks.push(listingIds.slice(i, i + BATCH_SIZE));
        }

        console.log("[SEARCH_BACKFILL] mirror:batch:start", { total: listingIds.length, chunks: chunks.length });

        for (const chunk of chunks) {
          try {
            const refs = chunk.map((id) => db.collection("listing_by_id").doc(id));
            const docs = await db.getAll(...refs);

            for (let i = 0; i < docs.length; i++) {
              const doc = docs[i];
              const listingId = chunk[i];
              if (!listingId) continue;
              if (doc && doc.exists) {
                const refPath = doc.get("refPath") as string | undefined;
                const userId = doc.get("userId") as string | undefined;
                results.set(listingId, {
                  refPath: refPath ?? null,
                  sellerUid: userId ?? null,
                });
              } else {
                results.set(listingId, { refPath: null, sellerUid: null });
              }
            }
          } catch (e) {
            console.warn("[SEARCH_BACKFILL] mirror:batch:fail", { chunkSize: chunk.length, err: String(e) });
            // Fill with nulls for failed chunk
            for (const id of chunk) {
              results.set(id, { refPath: null, sellerUid: null });
            }
          }
        }

        console.log("[SEARCH_BACKFILL] mirror:batch:done", { resolved: results.size });
        return results;
      }

      // 4) Compare pHashes and collect matches first (then batch resolve mirrors)
      interface MatchInfo {
        listingId: string;
        score: number;
        sourcePath: string;
      }
      const matches: MatchInfo[] = [];
      let peeked = 0;

      for (const f of files) {
        const fpath = f.name || "";
        // Path: active_listing_patterns/brands/{brandLower}/{listingId}/pattern.jpg
        const segs = fpath.split("/");
        if (segs.length < 5) continue;
        const listingId = segs[3];
        if (!listingId) continue;

        // download pattern.jpg
        let lbuf: Buffer | null = null;
        try {
          const dl = await f.download();
          lbuf = dl[0] as Buffer;
        } catch (e) {
          console.warn("[SEARCH_BACKFILL] storage:download:fail", { path: fpath, err: String(e) });
          continue;
        }
        if (!lbuf || lbuf.length < 32) continue;

        // compute listing pHash
        let listingPhash: string;
        try {
          listingPhash = await computeHexPHashFromBuffer(lbuf);
        } catch (e) {
          console.warn("[SEARCH_BACKFILL] storage:phash:fail", { path: fpath, err: String(e) });
          continue;
        }

        const dist = hammingHex(searchPhash, listingPhash);
        if (peeked < 5) {
          console.log("[SEARCH_BACKFILL] compare", { listingId, path: fpath, dist });
          peeked++;
        }

        if (dist <= PHASH_THRESHOLD) {
          const score = 1 - dist / 64;
          matches.push({ listingId, score, sourcePath: fpath });
        }
      }

      // Batch resolve all mirrors at once
      const matchingListingIds = matches.map((m) => m.listingId);
      const mirrorResults = await batchResolveMirrors(matchingListingIds);

      // Now write all matches to Firestore
      const batch = db.batch();
      const matchCount = matches.length;

      for (const match of matches) {
        const mirror = mirrorResults.get(match.listingId) || { refPath: null, sellerUid: null };

        // inbox for this buyer
        const inboxRef = db.collection("users").doc(uid).collection("matchInbox").doc(match.listingId);
        batch.set(
          inboxRef,
          {
            listingId: match.listingId,
            sellerUid: mirror.sellerUid,
            searchId: searchRef.id,
            brandLower,
            score: match.score,
            listingRef: mirror.refPath,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            seen: false,
            source: "storage-scan",
          },
          { merge: true }
        );

        // audit by search
        const auditRef = db
          .collection("matches_by_search")
          .doc(`${uid}_${searchRef.id}`)
          .collection("hits")
          .doc(match.listingId);
        batch.set(
          auditRef,
          {
            listingId: match.listingId,
            brandLower,
            score: match.score,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            sourcePath: match.sourcePath,
            source: "storage-scan",
          },
          { merge: true }
        );
      }

      if (matchCount) {
        console.log("[SEARCH_BACKFILL] batch:commit:start", { matchCount });
        await batch.commit();
        console.log("[SEARCH_BACKFILL] batch:commit:ok", { matchCount });
      }
      console.log("[SEARCH_BACKFILL] done", { uid, brandLower, searchId: searchRef.id, matchCount });
    } catch (err) {
      console.error("[onBuyerPatternUpload]", err);
    }
  }
);

// ───────── 6) Social graph: follow / unfollow ─────────
export const followUser = onCall({ region: "us-central1" }, async (req) => {
  // Auth required
  requireAuth(req.auth?.uid);
  const me = req.auth!.uid;

  // Validate payload
  const targetUid = assertString(req.data?.targetUid, "targetUid").trim();
  if (targetUid === me) {
    throw new HttpsError("failed-precondition", "You cannot follow yourself.");
  }

  const followerRef  = db.collection("users").doc(targetUid).collection("followers").doc(me);
  const followingRef = db.collection("users").doc(me).collection("following").doc(targetUid);
  const targetUserRef = db.collection("users").doc(targetUid);
  const meUserRef = db.collection("users").doc(me);

  try {
    const result = await db.runTransaction(async (tx) => {
      const existing = await tx.get(followerRef);
      if (existing.exists) {
        // Already following; idempotent OK.
        return { ok: true, alreadyFollowing: true };
      }

      // Create both edges
      tx.set(followerRef, {
        uid: me,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      tx.set(followingRef, {
        uid: targetUid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Increment counters on both user profiles (create if missing)
      tx.set(
        targetUserRef,
        { followerCount: admin.firestore.FieldValue.increment(1) },
        { merge: true }
      );
      tx.set(
        meUserRef,
        { followingCount: admin.firestore.FieldValue.increment(1) },
        { merge: true }
      );

      return { ok: true, alreadyFollowing: false };
    });

    console.log("[FOLLOW] ok", { me, targetUid, idempotent: result.alreadyFollowing === true });
    return result;
  } catch (err) {
    logErr("followUser", err);
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", "Unable to follow user at this time.");
  }
});

export const unfollowUser = onCall({ region: "us-central1" }, async (req) => {
  // Auth required
  requireAuth(req.auth?.uid);
  const me = req.auth!.uid;

  // Validate payload
  const targetUid = assertString(req.data?.targetUid, "targetUid").trim();
  if (targetUid === me) {
    throw new HttpsError("failed-precondition", "You cannot unfollow yourself.");
  }

  const followerRef  = db.collection("users").doc(targetUid).collection("followers").doc(me);
  const followingRef = db.collection("users").doc(me).collection("following").doc(targetUid);
  const targetUserRef = db.collection("users").doc(targetUid);
  const meUserRef = db.collection("users").doc(me);

  try {
    const result = await db.runTransaction(async (tx) => {
      const existing = await tx.get(followerRef);
      if (!existing.exists) {
        // Not following; idempotent OK.
        return { ok: true, alreadyNotFollowing: true };
      }

      // Remove both edges
      tx.delete(followerRef);
      tx.delete(followingRef);

      // Decrement counters (but don't go below zero)
      tx.set(
        targetUserRef,
        { followerCount: admin.firestore.FieldValue.increment(-1) },
        { merge: true }
      );
      tx.set(
        meUserRef,
        { followingCount: admin.firestore.FieldValue.increment(-1) },
        { merge: true }
      );

      return { ok: true, alreadyNotFollowing: false };
    });

    console.log("[UNFOLLOW] ok", { me, targetUid, idempotent: result.alreadyNotFollowing === true });
    return result;
  } catch (err) {
    logErr("unfollowUser", err);
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", "Unable to unfollow user at this time.");
  }
});

// ───────── 7) Scheduled: Follower Count Reconciliation ─────────
/**
 * Weekly scheduled function to reconcile follower/following counts.
 * Runs every Sunday at 3:00 AM UTC (low-traffic time).
 * Compares actual subcollection counts against stored counter values and fixes mismatches.
 */
export const reconcileFollowerCounts = onSchedule(
  {
    region: "us-central1",
    schedule: "0 3 * * 0", // Every Sunday at 3:00 AM UTC
    timeoutSeconds: 540, // 9 minutes max
    memory: "512MiB",
  },
  async () => {
    console.log("[RECONCILE] start");
    const startTime = Date.now();

    // Get all users in batches
    const BATCH_SIZE = 100;
    let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | null = null;
    let totalUsers = 0;
    let fixedFollowerCount = 0;
    let fixedFollowingCount = 0;

    // eslint-disable-next-line no-constant-condition
    while (true) {
      let query = db.collection("users").orderBy("__name__").limit(BATCH_SIZE);
      if (lastDoc) {
        query = query.startAfter(lastDoc);
      }

      const snapshot = await query.get();
      if (snapshot.empty) break;

      console.log("[RECONCILE] batch", { size: snapshot.size, totalSoFar: totalUsers });

      const updatePromises: Promise<void>[] = [];

      for (const userDoc of snapshot.docs) {
        const uid = userDoc.id;
        const userData = userDoc.data() || {};
        const storedFollowerCount = typeof userData["followerCount"] === "number" ? userData["followerCount"] : 0;
        const storedFollowingCount = typeof userData["followingCount"] === "number" ? userData["followingCount"] : 0;

        // Count actual followers
        const [followersSnap, followingSnap] = await Promise.all([
          db.collection("users").doc(uid).collection("followers").count().get(),
          db.collection("users").doc(uid).collection("following").count().get(),
        ]);

        const actualFollowerCount = followersSnap.data().count;
        const actualFollowingCount = followingSnap.data().count;

        // Check for mismatches
        const updates: Record<string, number> = {};

        if (storedFollowerCount !== actualFollowerCount) {
          console.log("[RECONCILE] follower mismatch", {
            uid,
            stored: storedFollowerCount,
            actual: actualFollowerCount,
          });
          updates["followerCount"] = actualFollowerCount;
          fixedFollowerCount++;
        }

        if (storedFollowingCount !== actualFollowingCount) {
          console.log("[RECONCILE] following mismatch", {
            uid,
            stored: storedFollowingCount,
            actual: actualFollowingCount,
          });
          updates["followingCount"] = actualFollowingCount;
          fixedFollowingCount++;
        }

        if (Object.keys(updates).length > 0) {
          updatePromises.push(
            userDoc.ref.update(updates).then(() => {
              console.log("[RECONCILE] fixed", { uid, updates });
            })
          );
        }

        totalUsers++;
      }

      // Wait for all updates in this batch
      if (updatePromises.length > 0) {
        await Promise.all(updatePromises);
      }

      lastDoc = snapshot.docs[snapshot.docs.length - 1] ?? null;

      // Safety timeout check (8 minutes)
      if (Date.now() - startTime > 8 * 60 * 1000) {
        console.log("[RECONCILE] timeout approaching, stopping early", { totalUsers });
        break;
      }
    }

    const elapsedMs = Date.now() - startTime;
    console.log("[RECONCILE] done", {
      totalUsers,
      fixedFollowerCount,
      fixedFollowingCount,
      elapsedMs,
    });
  }
);

export { onMatchInboxNotify, saveFcmToken } from "./notifications";
export { stripeWebhook } from "./stripeWebhook";
export { createPaymentIntent } from "./createPaymentIntent";
export { initPaymentSheet } from "./initPaymentSheet";
export { initSetupSheet } from "./initSetupSheet";
export { buyShippoLabel } from "./buyShippoLabel";
export { ShippoShipmentGetRates } from "./ShippoShipmentGetRates";
export { getPaymentSummary } from "./getPaymentSummary";
export { initFlowController } from "./initFlowController";
export { getSavedCardSummary } from "./getSavedCardSummary";