# Firebase Functions - Fix Checklist
**Track your progress fixing critical backend issues**

---

## 🚨 CRITICAL FIXES (Do First - Required for Production)

### Week 1: Security Vulnerabilities

- [ ] **Remove Duplicate Webhook Handler** (30 min)
  - [ ] Delete webhook export from `initPaymentSheet.ts` line 123
  - [ ] Move `markListingSold()` logic to `stripeWebhook.ts`
  - [ ] Test webhook with `stripe listen --forward-to`
  - [ ] Verify only one webhook endpoint exists after deploy
  
- [ ] **Fix Webhook Signature Bypass** (1 hour)
  - [ ] Add environment detection (`GCLOUD_PROJECT` check)
  - [ ] Use dashboard secret in production only
  - [ ] Use CLI secret in development/emulator only
  - [ ] Test both production and dev webhooks
  - [ ] Document webhook setup in README

- [ ] **Add Idempotency Keys to Stripe** (2 hours)
  - [ ] Create `generateIdempotencyKey()` helper in utils
  - [ ] Add idempotency to `initPaymentSheet` (line 146)
  - [ ] Add idempotency to `initFlowController` (line 68)
  - [ ] Add idempotency to `createPaymentIntent`
  - [ ] Test with intentional retries (kill function mid-execution)
  - [ ] Verify no duplicate PaymentIntents created

- [ ] **Fix markListingSold Race Condition** (2 hours)
  - [ ] Use paymentIntentId as order document ID
  - [ ] Add pre-check for existing order
  - [ ] Add status transition validation (active → sold only)
  - [ ] Test with concurrent webhook calls
  - [ ] Verify idempotent behavior

- [ ] **Add Address Validation** (1 hour)
  - [ ] Create `validateUSState()` function
  - [ ] Create `validateZipCode()` function
  - [ ] Apply to `ShippoShipmentGetRates`
  - [ ] Apply to `initPaymentSheet` shipping
  - [ ] Apply to `initFlowController` shipping
  - [ ] Test with invalid inputs (expect errors)
  - [ ] Test with valid inputs (expect success)

**Total Time: ~6.5 hours**

---

## ⚠️ HIGH PRIORITY (Do Second - Important for Stability)

### Week 2: Production Hardening

- [ ] **Add Rate Limiting** (3 hours)
  - Option A: Enable Firebase App Check
    - [ ] Set up App Check in Firebase Console
    - [ ] Add `consumeAppCheckToken: true` to all callable functions
    - [ ] Update iOS app with App Check SDK
    - [ ] Test token verification
  - Option B: Manual rate limiting
    - [ ] Install `rate-limiter-flexible`
    - [ ] Create rate limiter instances
    - [ ] Add `checkRateLimit()` helper
    - [ ] Apply to payment functions (5 req/min)
    - [ ] Apply to upload functions (20 req/min)
    - [ ] Apply to shipping functions (10 req/min)
    - [ ] Test rate limit enforcement

- [ ] **Add Transaction Rollback** (2 hours)
  - [ ] Update `findOrCreateStripeCustomer` to return `isNew` flag
  - [ ] Wrap `initFlowController` in try-catch
  - [ ] Add cleanup on failure (delete Firestore customer record)
  - [ ] Test rollback behavior
  - [ ] Add logging for rollback events

- [ ] **Fix Shippo Weight Conversion** (30 min)
  - [ ] Convert `toFixed(2)` strings to numbers
  - [ ] Add `OUNCES_PER_POUND` constant
  - [ ] Test with Shippo API (verify rates returned)

- [ ] **Add Null Checks for Stripe** (1 hour)
  - [ ] Fix `getPaymentSummary.ts` card access (line 76)
  - [ ] Fix `getSavedCardSummary.ts` card access
  - [ ] Add fallback values for all card fields
  - [ ] Test with customer that has no saved cards
  - [ ] Test with customer that has saved card

- [ ] **Fix Async Anti-patterns** (1 hour)
  - [ ] Update `getAllUserFcmTokens` to use `Promise.all`
  - [ ] Find other sequential awaits
  - [ ] Convert to parallel where possible
  - [ ] Measure performance improvement

- [ ] **Fix Batch Overflow** (1 hour)
  - [ ] Create `batchDelete()` helper (chunks of 500)
  - [ ] Apply to FCM token deletion in notifications
  - [ ] Test with >500 invalid tokens
  - [ ] Add logging for batch count

**Total Time: ~8.5 hours**

---

## 📊 CODE QUALITY (Do Third - Maintainability)

### Week 3: Code Cleanup

- [ ] **Standardize Error Handling** (2 hours)
  - [ ] Create `errors.ts` with `FunctionErrors` class
  - [ ] Replace all `throw new Error()` with `FunctionErrors`
  - [ ] Replace all inconsistent `HttpsError` with standard methods
  - [ ] Update all functions to use new error utilities
  - [ ] Test error responses are consistent

- [ ] **Extract Magic Numbers** (1 hour)
  - [ ] Create `constants.ts` file
  - [ ] Define `AppConstants` object
  - [ ] Document each constant with comment
  - [ ] Replace all magic numbers with constants
  - [ ] Update imports across all files

- [ ] **Implement Structured Logging** (3 hours)
  - [ ] Create `logger.ts` with `Logger` class
  - [ ] Add JSON formatting for Cloud Logging
  - [ ] Add context support (function name, uid)
  - [ ] Update all functions to use new logger
  - [ ] Test logs appear correctly in Cloud Logging
  - [ ] Set up log-based metrics/alerts

- [ ] **Update TypeScript Config** (30 min)
  - [ ] Add missing strict compiler options
  - [ ] Fix any new errors from stricter checks
  - [ ] Update CI to enforce strict mode

- [ ] **Audit Secret Logging** (1 hour)
  - [ ] Search codebase for `.value()` in console.log
  - [ ] Create `sanitizeForLog()` helper
  - [ ] Replace all secret logging with sanitized versions
  - [ ] Add pre-commit hook to catch future issues

**Total Time: ~7.5 hours**

---

## 🚀 PERFORMANCE OPTIMIZATIONS (Do Fourth)

### Week 4: Speed & Cost

- [ ] **Cache Algolia Search Keys** (2 hours)
  - [ ] Add in-memory Map cache
  - [ ] Implement 14-minute TTL (keys expire at 15 min)
  - [ ] Add cache cleanup logic
  - [ ] Measure cache hit rate
  - [ ] Monitor Algolia API usage reduction

- [ ] **Optimize Pattern Matching Storage** (2 hours)
  - [ ] Add `maxResults` to storage listing
  - [ ] Add file size filtering
  - [ ] Test with large brand folders
  - [ ] Measure performance improvement

- [ ] **Batch Phash Mirror Lookups** (3 hours)
  - [ ] Create `batchResolveMirrors()` function
  - [ ] Refactor `onBuyerPatternUpload` to collect then batch
  - [ ] Test with multiple matches
  - [ ] Measure Firestore read reduction

- [ ] **Add Follower Count Reconciliation** (2 hours)
  - [ ] Create scheduled function (weekly)
  - [ ] Count actual followers/following
  - [ ] Update mismatched counts
  - [ ] Test reconciliation logic
  - [ ] Schedule for low-traffic time

**Total Time: ~9 hours**

---

## 🔒 SECURITY HARDENING (Do Fifth)

### Week 5: Defense in Depth

- [ ] **Deploy Firestore Security Rules** (2 hours)
  - [ ] Create `firestore.rules` file
  - [ ] Add rules for orders (functions-only write)
  - [ ] Add rules for listings (prevent sold → active)
  - [ ] Add rules for all_listings (read-only)
  - [ ] Add rules for stripe_customers (user read-only)
  - [ ] Test rules with Firebase Emulator
  - [ ] Deploy to production
  - [ ] Verify rules enforced

- [ ] **Add Input Sanitization** (3 hours)
  - [ ] Install `validator` package
  - [ ] Create `validation.ts` with `InputValidator` class
  - [ ] Add email validation
  - [ ] Add alphanumeric validation
  - [ ] Add URL validation
  - [ ] Add positive integer validation
  - [ ] Apply to all callable functions
  - [ ] Test with malicious inputs

- [ ] **Review CORS Settings** (1 hour)
  - [ ] Check `firebase.json` CORS config
  - [ ] Restrict to your domains only
  - [ ] Test from allowed domain
  - [ ] Test from disallowed domain (should fail)

**Total Time: ~6 hours**

---

## 📈 MONITORING & OBSERVABILITY (Do Sixth)

### Week 6: Production Readiness

- [ ] **Set Up Alerts** (3 hours)
  - [ ] Webhook failure alert (Cloud Logging)
  - [ ] Stripe API error alert
  - [ ] Shippo API error alert
  - [ ] Function timeout alert
  - [ ] High error rate alert (>5%)
  - [ ] Test alerts trigger correctly

- [ ] **Add Error Reporting** (2 hours)
  - [ ] Sign up for Sentry (or similar)
  - [ ] Install Sentry SDK in functions
  - [ ] Configure error sampling
  - [ ] Test error reporting
  - [ ] Set up Sentry alerts

- [ ] **Create Dashboard** (2 hours)
  - [ ] Use Cloud Monitoring to create dashboard
  - [ ] Add function invocation charts
  - [ ] Add error rate charts
  - [ ] Add latency percentiles (p50, p95, p99)
  - [ ] Add Stripe/Shippo API call charts
  - [ ] Share with team

- [ ] **Document Runbook** (2 hours)
  - [ ] Create RUNBOOK.md
  - [ ] Document common errors and fixes
  - [ ] Add webhook verification steps
  - [ ] Add payment debugging steps
  - [ ] Add shipping debugging steps
  - [ ] Add rollback procedures

**Total Time: ~9 hours**

---

## 💰 COST OPTIMIZATION (Ongoing)

- [ ] **Set Resource Limits** (30 min)
  - [ ] Update `firebase.json` with `maxInstances: 100`
  - [ ] Set `minInstances: 0` for cost-efficient scaling
  - [ ] Set `timeoutSeconds: 60` (or appropriate)
  - [ ] Set `memory: 256MB` (or appropriate)
  - [ ] Deploy and monitor

- [ ] **Enable Caching** (varies)
  - [x] Algolia search keys (already in checklist above)
  - [ ] Stripe customer lookups (consider)
  - [ ] Cloudflare upload URLs (if reusing)

- [ ] **Monitor Usage** (ongoing)
  - [ ] Review Cloud Functions usage weekly
  - [ ] Review Firestore read/write costs
  - [ ] Review Stripe API call volume
  - [ ] Review Shippo API usage
  - [ ] Review Cloudflare Images quota

---

## 🧪 TESTING CHECKLIST

### Before Production Deploy

- [ ] **Unit Tests**
  - [ ] Test idempotency key generation
  - [ ] Test address validation functions
  - [ ] Test error handling utilities
  - [ ] Test batch operations
  - [ ] Test rate limiting

- [ ] **Integration Tests**
  - [ ] Test webhook with Stripe CLI
  - [ ] Test payment flow end-to-end
  - [ ] Test shipping rate fetch
  - [ ] Test label purchase
  - [ ] Test notification delivery
  - [ ] Test pattern matching upload

- [ ] **Load Tests**
  - [ ] Simulate concurrent webhook deliveries
  - [ ] Simulate rate limit thresholds
  - [ ] Simulate large batch operations
  - [ ] Monitor function execution time
  - [ ] Monitor memory usage

- [ ] **Security Tests**
  - [ ] Test with invalid webhook signatures
  - [ ] Test with malicious inputs
  - [ ] Test Firestore rules enforcement
  - [ ] Test rate limiting enforcement
  - [ ] Verify no secrets in logs

---

## 📝 DOCUMENTATION TASKS

- [ ] **Update README** (1 hour)
  - [ ] Document all environment variables
  - [ ] Document Stripe webhook setup
  - [ ] Document Shippo configuration
  - [ ] Document Cloudflare Images setup
  - [ ] Add troubleshooting section

- [ ] **Create API Documentation** (2 hours)
  - [ ] Document all callable functions
  - [ ] Document request/response formats
  - [ ] Document error codes
  - [ ] Document rate limits
  - [ ] Add example requests

- [ ] **Create Architecture Diagram** (1 hour)
  - [ ] Show function flow
  - [ ] Show Firestore collections
  - [ ] Show external API integrations
  - [ ] Document data flow

---

## ✅ DEPLOYMENT VERIFICATION

After each deploy:

- [ ] Check Cloud Functions logs for errors
- [ ] Verify all functions deployed successfully
- [ ] Test critical user flows:
  - [ ] User signup
  - [ ] Payment processing
  - [ ] Shipping rate calculation
  - [ ] Notification delivery
  - [ ] Pattern matching
- [ ] Check monitoring dashboard
- [ ] Verify alerts are active
- [ ] Monitor for 24 hours

---

## 📊 PROGRESS TRACKING

**Overall Progress:** 0/80+ tasks

### By Priority:
- Critical: 0/5 completed
- High: 0/6 completed
- Code Quality: 0/5 completed
- Performance: 0/4 completed
- Security: 0/3 completed
- Monitoring: 0/4 completed

### Estimated Total Time:
- Critical: 6.5 hours
- High Priority: 8.5 hours
- Code Quality: 7.5 hours
- Performance: 9 hours
- Security: 6 hours
- Monitoring: 9 hours
- **Total: ~46.5 hours** (1-2 weeks of focused work)

---

## 🎯 SUCCESS CRITERIA

You'll know you're done when:

- [ ] No critical security vulnerabilities remain
- [ ] All payments are idempotent
- [ ] Race conditions eliminated
- [ ] Rate limiting prevents abuse
- [ ] Logs are structured and secret-free
- [ ] Error handling is consistent
- [ ] Monitoring alerts are active
- [ ] All tests pass
- [ ] Documentation is complete
- [ ] Team can debug issues independently

---

**Last Updated:** January 29, 2026  
**Next Review:** After critical fixes (Week 1)
