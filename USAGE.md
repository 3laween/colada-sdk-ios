# Colada iOS SDK — Integration Guide

Attribution and lifecycle event tracking for iOS. Zero third-party dependencies. No IDFA, no ATT prompt.

---

## Requirements

- iOS 13.0+
- Swift 5.9+ (Xcode 15+)
- A Colada API key (`pk_live_…`) — contact your Colada account manager.

---

## Installation

### Swift Package Manager (Xcode)

1. **File ▸ Add Package Dependencies…**
2. Enter: `https://github.com/3laween/colada-sdk-ios`
3. Choose **Up to Next Major Version** from `0.1.1`
4. Add the **`Colada`** product to your app target.

### Swift Package Manager (Package.swift)

```swift
dependencies: [
    .package(url: "https://github.com/3laween/colada-sdk-ios.git", from: "0.1.1")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "Colada", package: "colada-sdk-ios")
    ])
]
```

### CocoaPods

```ruby
pod 'Colada', '~> 0.1.1'
```

---

## Integration

### 1. Configure at launch

Call this **once**, as early as possible. This handles attribution resolution automatically.

**SwiftUI**
```swift
import Colada

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    try? await ColadaSDK.shared.configure(apiKey: "pk_live_your_key_here")
                }
        }
    }
}
```

**UIKit**
```swift
import Colada

func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {
    Task {
        try? await ColadaSDK.shared.configure(apiKey: "pk_live_your_key_here")
    }
    return true
}
```

---

### 2. Forward deep links

Forward every deep link the OS delivers — the SDK handles re-engagement attribution automatically.

**SwiftUI**
```swift
.onOpenURL { url in
    Task { await ColadaSDK.shared.handleDeepLink(url) }
}
```

**UIKit — cold start**
```swift
if let url = launchOptions?[.url] as? URL {
    Task { await ColadaSDK.shared.handleDeepLink(url) }
}
```

**UIKit — app already running**
```swift
func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
) -> Bool {
    Task { await ColadaSDK.shared.handleDeepLink(url) }
    return true
}
```

---

### 3. Identify the user

Call this after login or signup, before reporting any events.

```swift
await ColadaSDK.shared.setExternalUserId("user_1234")
```

Pass `nil` to clear on logout:
```swift
await ColadaSDK.shared.setExternalUserId(nil)
```

---

### 4. Report lifecycle events

The SDK supports 9 fixed event names:

| Event | When to fire |
|---|---|
| `.login` | User logged in |
| `.purchase` | Order completed |
| `.subscribe` | Subscription started/renewed |
| `.addToCart` | Item added to cart |
| `.initiateCheckout` | Checkout started |
| `.viewContent` | Item/page viewed |
| `.placeAnOrder` | Order placed |
| `.search` | Search performed |
| `.completeRegistration` | Use `reportRegistration` instead (see below) |

```swift
try await ColadaSDK.shared.reportEvent(
    .purchase,
    metadata: AttributionEventMetadata(amount: 99.5, currency: "SAR", orderId: "ORD-123")
)
```

> Always pass `amount` and `currency` for `.purchase` and `.subscribe`. `currency` defaults to `"SAR"`.

---

### 5. Report registration

Use this instead of `.completeRegistration` — it's the only event that can carry user data.

```swift
let userInfo = ColadaUserInfo(
    name: "Jane Doe",
    email: "jane@example.com",
    phoneNumber: "+966500000000"
)
try await ColadaSDK.shared.reportRegistration(userInfo: userInfo)
```

All fields are optional. Only fields you provide leave the device.

---

### 6. Deferred deep linking (optional)

If a user clicked an ad for a specific page, navigate them there on first open:

```swift
if let ddl = await ColadaSDK.shared.consumeDeferredDeepLink() {
    if let storeId = ddl.storeId {
        navigate(to: .store(id: storeId))
    } else if let menuItemId = ddl.menuItemId {
        navigate(to: .menuItem(id: menuItemId))
    }
}
```

Call this after `configure()` completes on first open. It returns a target exactly once, then `nil`.

---

### 7. User opt-out / account deletion

Wipes all SDK state — device identity, attribution, pending events.

```swift
await ColadaSDK.shared.reset()
```

---

## Minimum integration checklist

- [ ] `configure(apiKey:)` called once at app launch
- [ ] Deep links forwarded to `handleDeepLink(_:)` (both cold-start and while running)
- [ ] `setExternalUserId` called after login/signup, before first event
- [ ] `reportEvent` / `reportRegistration` called at the relevant moments
- [ ] `reset()` wired to your account-deletion or opt-out flow

---

## Error handling

```swift
do {
    try await ColadaSDK.shared.reportEvent(.purchase, metadata: ...)
} catch ColadaError.missingExternalUserId {
    // Call setExternalUserId before reporting events
} catch ColadaError.backendRejected(let status, let message) {
    // Bad API key or missing required field — read message and fix the call
    print("Rejected (\(status)): \(message ?? "—")")
} catch ColadaError.blockedByTrackingPrevention {
    // iOS blocked the request — resolves once ATT is granted
} catch {
    // Network error — event is queued offline and retried automatically
}
```

Failed events are queued and retried automatically on the next launch or successful network call. No action needed.
