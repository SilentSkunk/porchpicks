export interface MatchContext {
  brandLower: string;
  listingId: string;
  listingPhash: string;
  bucketName: string;
  sellerUid?: string | null;
  listingRefPath?: string | null;
  PHASH_THRESHOLD: number;
}