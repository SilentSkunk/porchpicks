// constants.ts - Application constants and configuration values

export const AppConstants = {
  // Algolia search configuration
  ALGOLIA_INDEX_NAME: "LoomPair",
  ALGOLIA_KEY_TTL_SECONDS: 15 * 60, // 15 minutes

  /**
   * Perceptual hash matching threshold.
   *
   * Hamming distance scale (0-64 for 64-bit hash):
   * - 0-10: Very similar images
   * - 11-15: Similar (CURRENT THRESHOLD = 14)
   * - 16-20: Somewhat similar
   * - 21+: Different images
   *
   * Confidence formula: 1 - (distance / 64)
   * At threshold 14: confidence >= 0.78 (78%)
   */
  PHASH_MATCH_THRESHOLD: 14,
  PHASH_CONFIDENCE_DENOMINATOR: 64, // 64-bit hash

  // Unit conversions
  OUNCES_PER_POUND: 16,

  // Firestore limits
  FIRESTORE_BATCH_LIMIT: 500,

  // Rate limits (requests per minute)
  RATE_LIMITS: {
    PAYMENT_REQUESTS_PER_MINUTE: 5,
    UPLOAD_REQUESTS_PER_MINUTE: 20,
    SHIPPING_REQUESTS_PER_MINUTE: 10,
  },

  // Stripe configuration
  STRIPE_API_VERSION: "2023-10-16" as const,

  // Shippo configuration
  SHIPPO_API_URL: "https://api.goshippo.com",

  // Firebase Functions region
  DEFAULT_REGION: "us-central1",
} as const;

// Export commonly used constants for convenience
export const PHASH_THRESHOLD = AppConstants.PHASH_MATCH_THRESHOLD;
export const OUNCES_PER_POUND = AppConstants.OUNCES_PER_POUND;
export const FIRESTORE_BATCH_LIMIT = AppConstants.FIRESTORE_BATCH_LIMIT;
export const ALGOLIA_KEY_TTL_SECONDS = AppConstants.ALGOLIA_KEY_TTL_SECONDS;
