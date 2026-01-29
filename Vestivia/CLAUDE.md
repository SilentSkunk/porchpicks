# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

This is a native iOS SwiftUI project using Xcode.

```bash
# Build from command line
xcodebuild -project Exchange.xcodeproj -scheme Exchange -configuration Debug build

# Run tests
xcodebuild -project Exchange.xcodeproj -scheme Exchange test -destination 'platform=iOS Simulator,name=iPhone 16'

# Run a single test
xcodebuild -project Exchange.xcodeproj -scheme Exchange test -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:VestiviaTests/VestiviaTests/testExample
```

The main Xcode project is `Exchange.xcodeproj` with bundle ID `com.LoomPair.Market`.

## Architecture Overview

**SwiftUI + MVVM** with centralized state management and Firebase backend.

### App Entry & Navigation
- `VestiviaApp.swift` - @main entry point, manages auth routing via AppStorage
- `AppDelegate.swift` - Firebase config, FCM push notifications, deep linking (`vestivia://listing/<id>`)
- `MainTabView.swift` - Custom tab bar with NavigationStack, 5 tabs: Feed, Shop, Sell, MyStore, Pattern

### Authentication Flow (AuthManager.swift)
State machine routing: `loggedOut → needUsername → needPhoto → ready`
- Supports Email/Password, Google Sign-In, Apple Sign-In
- Firestore listener for real-time user profile updates
- Manages FCM token lifecycle

### Search & Discovery (AlgoliaSearch/)
- `InstantSearchCoordinator.swift` - Centralized Algolia search state, filter management, multi-level caching
- `ListingHit.swift` - Flexible decoding with Mirror reflection for 10+ field name variants (backward compatibility)
- `DefaultFeedCache.swift` - In-memory cache for Algolia results
- Search keys fetched from Firebase Functions (no hardcoded API keys)

### Listing Creation (Item for sale/)
- `ListingViewModel.swift` - Form state management for new listings
- `CloudflareUploader.swift` - Direct image uploads via one-time URLs from Firebase Functions

### User Profiles & Social (My Porch/)
- `LikesService.swift` / `FollowService.swift` - Favorites and follow system
- Multi-layer caching: UserDefaults + in-memory + disk

### E-commerce (Checkout/)
- `CartViewModel.swift` - Shopping cart state
- `PaymentMethodManager.swift` - Stripe integration
- `ShippoManager.swift` - Shipping API

## Technology Stack

**Backend Services:**
- Firebase: Auth, Firestore, Storage, Functions, Messaging (FCM)
- Algolia: Search index `LoomPair`
- Cloudflare Images: CDN with signed URLs
- Stripe: Payments
- Shippo: Shipping

**Firebase Functions Region:** `us-central1`

## Key Patterns

- **Singletons:** AuthManager, SessionManager, CloudflareUploader
- **State Machine:** AuthManager.Route enum for auth flow
- **Cache-First:** Search results use in-memory → local → network
- **Debug Guards:** `#if DEBUG` for development logging
- **Defensive Decoding:** ListingHit supports legacy field name variants via Mirror
- **One-Shot Guards:** `setupTask` pattern prevents duplicate initialization
