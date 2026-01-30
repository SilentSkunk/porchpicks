# Checkout System Code Review & Fix Tracker

## 🚨 CRITICAL ISSUES (Must Fix Before Production)

### 1. **UserAddress Model - Missing Required Fields**
**File:** `Vestivia/Checkout/Checkout Suppport Files/UserAddress.swift`

**Problem:**
- Missing `state` and `zip` properties that are essential for US shipping
- Currently using a temporary extension shim that returns empty strings
- This will cause Shippo API calls to fail

**Current Hack (lines in CartViewModel.swift):**
```swift
extension UserAddress {
    var state: String { "" }  // ❌ Returns empty string
    var zip: String { "" }    // ❌ Returns empty string
}
```

**Fix Required:**
```swift
struct UserAddress: Identifiable, Codable {
    var id: String = "main"
    var fullName: String
    var address: String
    var city: String
    var state: String        // ✅ ADD THIS
    var zip: String          // ✅ ADD THIS
    var country: String
    var phone: String
    var isPrimary: Bool = true
}
```

**Impact:** High - Shippo shipping rates and label purchase will fail without valid state/zip

---

### 2. **AddressFormView - Duplicate Address Field**
**File:** `Vestivia/Checkout/Checkout Suppport Files/UI/AddressFormView.swift`

**Problem:**
- Lines 86-99 have a duplicate "Address" section
- Already has "Street Address" fields earlier (lines 42-47)
- Creates confusing UX and duplicate data binding

**Fix:** Remove duplicate address section (lines 86-99)

---

### 3. **AddressFormView - State/Zip Not Saved to UserAddress**
**File:** `Vestivia/Checkout/Checkout Suppport Files/UI/AddressFormView.swift`

**Problem:**
- Form collects `state` and `zip` fields
- But when saving (lines 97-110), it creates `UserAddress` without state/zip
- Data is collected but lost

**Current Code:**
```swift
let userAddress = UserAddress(
    id: "main",
    fullName: fullName,
    address: addressLine,
    city: city,
    country: "United States",  // ❌ Missing state & zip
    phone: phone,
    isPrimary: true
)
```

**Fix:** Include state and zip in UserAddress initialization after adding them to the model

---

### 4. **CartViewModel - Order Persistence Not Implemented**
**File:** `Vestivia/Checkout/Checkout Suppport Files/CartViewModel.swift`

**Problem:**
- `saveOrder()` method (lines 279-289) only prints debug info
- No actual Firestore persistence
- Orders won't be saved for seller/buyer to track

**Current Code:**
```swift
private func saveOrder(...) async throws {
    print("""
    💾 Saving order
    - Tracking: \(trackingNumber)
    - Shipping: \(shippingRate.amount) \(shippingRate.currency)
    - Carrier: \(label.carrier)
    """)
    // TODO: Persist full order to Firestore  // ❌
}
```

**Fix Required:**
```swift
private func saveOrder(...) async throws {
    guard let uid = Auth.auth().currentUser?.uid else {
        throw NSError(domain: "Order", code: 401)
    }
    
    let orderData: [String: Any] = [
        "buyerId": uid,
        "sellerId": cartItems.first?.sellerId ?? "",
        "items": cartItems.map { /* serialize cart items */ },
        "trackingNumber": trackingNumber,
        "shippingRate": shippingRate.amount,
        "carrier": label.carrier,
        "labelUrl": label.labelUrl,
        "status": "pending_shipment",
        "createdAt": FieldValue.serverTimestamp()
    ]
    
    try await Firestore.firestore()
        .collection("orders")
        .document()
        .setData(orderData)
}
```

---

## ⚠️ MODERATE ISSUES (Important but not blocking)

### 5. **CheckoutPayload.swift - Potentially Unused Code**
**File:** `Vestivia/Checkout/Checkout Suppport Files/CheckoutPayload.swift`

**Problem:**
- `CheckoutService` creates PaymentIntents
- But `CartViewModel` uses `FlowControllerManager` instead
- May be dead code from earlier implementation

**Action:** Verify if this is still used, remove if not

---

### 6. **ShippoManager.swift - Not Integrated**
**File:** `Vestivia/Checkout/Managers /ShippoManager.swift`

**Problem:**
- Has flat-rate shipping logic
- But `CartViewModel.performCheckout()` bypasses this and calls Firebase Functions directly
- `ShippoManager` is not used anywhere

**Current CartViewModel approach:**
```swift
// CartViewModel calls Firebase Functions directly:
let ratesResult = try await getShippingRates(...)
let label = try await purchaseLabel(...)
```

**Decision Needed:**
- Either use `ShippoManager` for shipping logic
- OR remove `ShippoManager.swift` as unused code
- Don't maintain parallel implementations

---

### 7. **Payment Flow - Missing Error Handling UI**
**File:** `Vestivia/Checkout/Checkout Suppport Files/CartViewModel.swift`

**Problem:**
- `performCheckout()` has try/catch but only prints errors
- No user-facing error messages for:
  - Shippo rate fetch failure
  - Payment failure
  - Label purchase failure

**Fix:** Add `@Published var checkoutError: String?` and display alerts

---

### 8. **CartViewModel - No Checkout Success State**
**File:** `Vestivia/Checkout/Checkout Suppport Files/CartViewModel.swift`

**Problem:**
- After successful checkout, no navigation or confirmation
- User sees no success message or order confirmation
- No redirect to order tracking/confirmation screen

**Fix Required:**
- Add `@Published var checkoutSuccess: Bool = false`
- Show success alert or navigate to order confirmation
- Clear cart after success

---

## 📝 MINOR ISSUES / IMPROVEMENTS

### 9. **FlowControllerManager - Hardcoded Merchant Name**
**File:** `Vestivia/Checkout/Checkout Suppport Files/FlowControllerManager.swift`

**Issue:** Line 51 has `configuration.merchantDisplayName = "PorchPick"`
**Note:** Make sure this matches your app name or make it configurable

---

### 10. **CartScreen - Payment Section Commented Code**
**File:** `Vestivia/Checkout/Checkout Suppport Files/CartScreen.swift`

**Issue:** Lines 147-158 have inline setup flow logic
**Note:** This is fine but consider moving to CartViewModel for consistency

---

### 11. **Address Display - Incomplete Format**
**File:** `Vestivia/Checkout/Checkout Suppport Files/CartScreen.swift`

**Problem:** Line 224 extension shows: `"\(address), \(city)"`
**Missing:** State and ZIP code in display
**Fix:** Update to: `"\(address), \(city), \(state) \(zip)"`

---

### 12. **AddressManager - Missing Address Validation**
**File:** `Vestivia/Checkout/Checkout Suppport Files/UserAddress.swift`

**Improvement:** Add validation before saving:
- ZIP code format (5 digits)
- Phone number format
- Required field checks

---

### 13. **CartViewModel - No Multi-Item Cart Handling**
**File:** `Vestivia/Checkout/Checkout Suppport Files/CartViewModel.swift`

**Problem:**
- `performCheckout()` only uses first item: `cartItems.first`
- No logic for calculating shipping for multiple items
- No combined order handling

**Future Fix:** Add multi-item order support

---

### 14. **Payment Methods - No Delete/Change Option**
**Files:** `CartViewModel.swift`, `PaymentMethodManager.swift`

**Missing Feature:** 
- No way to delete saved payment method
- No way to select different saved card
- Can only add new methods

**Future Enhancement:** Add payment method management screen

---

## 🎯 TESTING CHECKLIST

Before production, test:

- [ ] Complete address with state/zip saves correctly
- [ ] Shippo API returns valid rates with real address
- [ ] Payment confirmation completes successfully
- [ ] Shipping label purchases and returns tracking number
- [ ] Order saves to Firestore with all required fields
- [ ] Error states display user-friendly messages
- [ ] Success state shows confirmation and clears cart
- [ ] Multi-item cart calculates shipping correctly
- [ ] Payment method updates after adding new card
- [ ] Address updates after editing

---

## 🔧 PRIORITY FIXES (In Order)

1. **Add state/zip to UserAddress model** (Blocks Shippo integration)
2. **Update AddressFormView to save state/zip** (Required for #1)
3. **Implement saveOrder() with Firestore** (Required for order tracking)
4. **Add checkout error handling UI** (Required for UX)
5. **Add checkout success state** (Required for UX)
6. **Fix duplicate address field in AddressFormView** (Confusing UX)
7. **Remove unused code** (CheckoutPayload, ShippoManager)
8. **Add address display with state/zip** (Polish)

---

## 📊 FILE STATUS SUMMARY

| File | Status | Priority |
|------|--------|----------|
| CartScreen.swift | ✅ Mostly Good | Low |
| CartViewModel.swift | ⚠️ Needs Work | **HIGH** |
| CheckoutPayload.swift | ❓ Possibly Unused | Medium |
| FlowControllerManager.swift | ✅ Complete | Low |
| AddressFormView.swift | ⚠️ Has Issues | **HIGH** |
| PaymentMethodSectionView.swift | ✅ Complete | Low |
| UserAddress.swift | 🚨 Critical Issue | **CRITICAL** |
| PaymentMethodManager.swift | ✅ Complete | Low |
| ShippoManager.swift | ❓ Not Integrated | Medium |

---

## 💡 ARCHITECTURAL NOTES

### Current Payment Flow:
1. User adds items to cart
2. User selects/adds address (AddressFormView → AddressManager)
3. User adds payment method (PaymentMethodManager → Stripe SetupIntent)
4. User clicks checkout:
   - FlowControllerManager creates PaymentIntent
   - User confirms payment
   - Shippo rates fetched via Firebase Function
   - Shippo label purchased via Firebase Function
   - Order saved (TODO)

### Recommendation:
Consider creating an `OrderManager` class to:
- Centralize order creation logic
- Handle Firestore persistence
- Manage order state transitions
- Provide order history queries

This would clean up CartViewModel significantly.
