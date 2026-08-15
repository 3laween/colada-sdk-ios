# Colada iOS SDK — Developer Guide

Everything you need to integrate the **Colada iOS SDK (Core Module, `Colada`)** into your
app: installation, configuration, deep links, attribution, events, offline behavior,
privacy, errors, and troubleshooting.

---

## Table of contents

1. [What the SDK does](#1-what-the-sdk-does)
2. [Requirements](#2-requirements)
3. [Installation](#3-installation)
4. [Configure the SDK at launch](#4-configure-the-sdk-at-launch)
5. [Forward deep links](#5-forward-deep-links)
6. [Identify the user](#6-identify-the-user)
7. [The handshake — how attribution is resolved](#7-the-handshake--how-attribution-is-resolved)
8. [Read the attribution result](#8-read-the-attribution-result)
9. [Deferred Deep Linking](#9-deferred-deep-linking)
10. [Report lifecycle events](#10-report-lifecycle-events)
11. [Report registration with user data](#11-report-registration-with-user-data)
12. [Offline queue: `flush()` and `pendingEvents()`](#12-offline-queue-flush-and-pendingevents)
13. [Session token (diagnostics)](#13-session-token-diagnostics)
14. [Device identity](#14-device-identity)
15. [Privacy, App Tracking Transparency, and opt-out](#15-privacy-app-tracking-transparency-and-opt-out)
16. [Errors and how to handle them](#16-errors-and-how-to-handle-them)
18. [Minimum integration checklist](#18-minimum-integration-checklist)
19. [Troubleshooting](#19-troubleshooting)
20. [Common questions](#20-common-questions)

---

## 1. What the SDK does

The Core Module resolves **which ad campaign drove each install and re-engagement** and
reports **lifecycle events** (purchase, login, add-to-cart, …) back to the Colada backend.
The backend forwards conversions to ad platforms (Meta, TikTok, Google Ads, Snapchat)
server-side.

Key properties:

- **Zero third-party dependencies** — nothing to install besides this package.
- **No IDFA, no App Tracking Transparency** — the SDK does not use the advertising
  identifier and never prompts for tracking permission.
- **Self-driving** — configuration alone handles the first-install handshake; deep links
  handle re-engagements. You do not have to implement an attribution policy.
- **iOS 13.0+** required.

Two modules exist:

| Module | Package product | What it is | Who uses it |
|---|---|---|---|
| `Colada` (Core) | `Colada` | Attribution + events + lifecycle, zero dependencies | Everyone |

The **binary package** ships Core only — no source code, zero third-party dependencies.

---

## 2. Requirements

- iOS **13.0 or later**.
- Swift **5.9 or later** (Xcode 15+).
- A Colada **API key** (`pk_live_…`) — reach out to your Colada contact if you don't
  have one.
- Deep links configured (if you want re-engagement attribution) — see §5.

---

## 3. Installation

### Via Xcode (recommended)

1. Open your project in Xcode.
2. **File ▸ Add Package Dependencies…**
3. Enter the package URL:
   `https://github.com/3laween/colada-sdk-ios`
4. Choose **Up to Next Major Version** and a version (the current release is `0.1.0`).
5. Add the **`Colada`** product to your app target.

### Via `Package.swift`

```swift
dependencies: [
    .package(url: "https://github.com/3laween/colada-sdk-ios.git", from: "0.1.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "Colada", package: "colada-sdk-ios"),
        ]
    )
]
```

### Import

```swift
import Colada
```

The SDK is used through the singleton `ColadaSDK.shared`. There is **exactly one
instance** — the initializer is private, so you can never create a second one.

---

## 4. Configure the SDK at launch

Call `configure` **once, early**, in your app's startup (SwiftUI `init`/`task` or
`application(_:didFinishLaunchingWithOptions:)`). This is the single most important call.

```swift
import Colada
import SwiftUI

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

```swift
// UIKit
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

What `configure` does — point by point:

1. **Reads (or mints) the device identity.** The SDK keeps a stable per-device UUID in
   the Keychain. On a fresh install it creates one; on later launches it reads the
   existing one. The identity survives uninstall/reinstall.
2. **Exchanges the API key for a session token.** It calls
   `POST /attribution/sdk/init` in the background and caches the result in the Keychain.
   Every later SDK call authorizes itself with this token automatically — you never
   handle it.
3. **Kicks off the first-install handshake (self-driving).** If this install has never
   completed a handshake, the SDK reads the clipboard once (bounded wait for
   foreground) and sends whatever it found — including a `matched: false` result for an
   organic install. A failed attempt (offline, backend error) leaves the "gate" open so
   the next launch retries.
4. **Flushes the offline queue** of any events that failed delivery previously.

Properties of `configure`:

- **Idempotent** — calling it twice with the same key is safe (no-op).
- **Must run before** `reportEvent`/`reportRegistration` (and technically before any
  handshake, though the self-driving flow covers the common cases).
- **`apiKey` doubles as your tenant key** on every backend call — the backend identifies
  which tenant you are from it.
- Other SDK calls made while `configure` is still in flight **suspend until it
  finishes**, so you don't need to coordinate ordering yourself.
- **Can throw** `ColadaError.deviceIdentityUnavailable` (see [§16](#16-errors-and-how-to-handle-them)) — this means the Keychain was
  unreadable (typically: device rebooted and is still locked). Nothing was changed;
  call `configure` again later.

> **You do not need to call `handshake()` yourself anymore.** `configure` covers first
> installs; `handleDeepLink` covers re-engagements. §7 explains the manual API for the
> edge cases.

---

## 5. Forward deep links

Deep links are how the SDK learns about **re-engagements** (a user tapped an ad, the
OS opened your app, and you must tell Colada). Forward **every** deep link the OS
delivers — the SDK decides what to do with it.

### SwiftUI

```swift
.onOpenURL { url in
    Task { await ColadaSDK.shared.handleDeepLink(url) }
}
```

### UIKit

Cold start (app was launched by the link) — in `didFinishLaunchingWithOptions`:

```swift
if let url = launchOptions?[.url] as? URL {
    Task { await ColadaSDK.shared.handleDeepLink(url) }
}
```

Hot (app was already running):

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

What `handleDeepLink` does — point by point:

1. **Parses the URL's query parameters** for an attribution signal.
2. **Drops it silently** if it carries no attribution signal (no click id, no `utm_*`
   parameter) or if it is the same URL delivered twice within ~2 seconds (the common
   cold-start double-delivery).
3. **Otherwise handshakes immediately** with the link's `clickId`/`utm_*` values. This
   is the deep-link arm of the self-driving handshake — you do not parse URLs yourself.
4. **Always sends** — deep links are the "100%-accuracy tier" and are never gated by
   `needsInitialHandshake`. A deep-link handshake also takes priority over an in-flight
   first-install handshake for the same cold start.

The result is returned for convenience (e.g. to show a toast) but **you never need it**:
the outcome is persisted to `lastAttribution` and broadcast to `observeAttribution()`
like any other handshake. Returns `nil` when nothing was sent (duplicate / no signal /
delivery failed).

---

## 6. Identify the user

Before reporting events, tell the SDK who the user is with **your own** user ID
(the same ID your signup/login API returns):

```swift
await ColadaSDK.shared.setExternalUserId("user_1234")
```

Why this matters, point by point:

- The backend keys every event and attribution record on this ID. Without it, events
  cannot be linked to the right attribution.
- It **must match** whatever was sent as `externalUserId` during the handshake — if you
  handshake with one ID and report events with another, the backend won't connect them.
- Call it as soon as you know the user's ID (after login/signup), and **before** the
  first `reportEvent`. `reportEvent` throws `ColadaError.missingExternalUserId` if it
  hasn't been set.
- Pass `nil` to clear it (e.g. on logout). Handshake events still work without it —
  only events require it.

---

## 7. The handshake — how attribution is resolved

A **handshake** is a request to the Colada backend that says "this install/open
happened, here's the attribution signal I have" — the backend matches it against ad
campaign data and returns the result (`matched`, campaign parameters, tenant info,
deferred deep-link targets).

### When it happens automatically

| Scenario | Who triggers it |
|---|---|
| First install (fresh open, gate open) | `configure()` — self-driving, clipboard read included |
| Deep-link open (re-engagement) | `handleDeepLink(_:)` |
| Every app open afterwards | Nothing — an ordinary open sends no traffic |

### The manual API (for edge cases only)

You should not need these in a normal integration, but they exist:

```swift
// True while THIS INSTALL has never completed a successful handshake.
// Persisted in UserDefaults (cleared on uninstall, so it re-arms per install).
// Useful for an attribution-consent hint in your UI.
let needsIt: Bool = await ColadaSDK.shared.needsInitialHandshake

// Fires the handshake ONLY if needsInitialHandshake is true; no-op (returns nil) otherwise.
// Use this when you want to pass YOUR OWN clipboardToken/installReferrer instead of
// letting the SDK read the pasteboard.
let result = try await ColadaSDK.shared.handshakeIfNeeded(
    clipboardToken: nil,
    installReferrer: nil
)

// Low-level manual handshake — for sending something outside the self-driving policy,
// e.g. re-sending a specific directParams object on demand.
let result = try await ColadaSDK.shared.handshake(
    clipboardToken: nil,
    installReferrer: nil,
    directParams: AttributionDirectParams(clickId: "abc123", utmCampaign: "summer")
)
```

Point by point:

- **`needsInitialHandshake`** reads a persisted first-launch latch (UserDefaults). `true`
  until this install's first successful handshake. Not for deep-link re-engagements.
- **`handshakeIfNeeded`** is the manual version of what `configure` does automatically.
  Use it only if you want to supply your own `clipboardToken`/`installReferrer`.
  Concurrent calls with identical parameters share one network request. A failed
  handshake leaves the latch unset so the next call (next app open) retries.
- **`handshake`** is the raw API. Only for scenarios the self-driving policy doesn't
  cover. `directParams` carries UTM/click-id data — see below.
- **`matched: false` is a normal organic install, not an error.**
- **`AttributionDirectParams`** carries `clickId` + the `utm_*` fields. You can build it
  manually (memberwise) or from a URL via `AttributionDirectParams(from: url)`, which
  extracts only the industry-standard keys (`fbclid`/`ttclid`/`gclid`/`sccid`, `utm_*`).
  The store/menu-item fields are deliberately NOT extracted from URLs — your tenant
  defines its own deep-link scheme, so you supply those yourself.

---

## 8. Read the attribution result

Two ways to learn what a handshake resolved:

### The last known attribution (one-shot)

```swift
if let last = await ColadaSDK.shared.lastAttribution {
    print("matched: \(last.matched), campaign: \(last.utmCampaign ?? "—")")
    print("tenant: \(last.tenantKey ?? "—")")
}
```

- Persisted in the Keychain — survives launches and **reinstalls**.
- `nil` until the first successful handshake (or after `reset()`).
- Use it whenever you need "the last known attribution" without re-handshaking.

### A live stream of handshake completions (events)

```swift
let updates = await ColadaSDK.shared.observeAttribution()
for await result in updates {
    // UI-touching code must hop to the main actor — values arrive on the SDK's executor.
    await MainActor.run { viewModel.apply(result) }
}
```

Point by point:

- Replays the current `lastAttribution` **immediately** — a listener registered after
  resolution still sees the current value.
- Then yields every future successful handshake.
- **The stream never finishes** — cancel the consuming `Task` to unsubscribe.
- Values arrive on the SDK's executor, **not the main thread**; hop to `.main` if you
  touch UI.

### The result model (`AttributionHandshakeResult`)

| Field | Meaning |
|---|---|
| `matched` | Whether the backend matched this open to an ad campaign. `false` = organic install (normal). |
| `matchMethod` | How it was matched (e.g. click id, clipboard, fingerprint). |
| `utmSource/Campaign/Medium/Content/Term` | Campaign parameters the backend resolved. |
| `attributionStoreId`, `attributionMenuItemId`, `isCoffeeSubscription` | Deferred deep-link targets — feed them to `consumeDeferredDeepLink()` (§9). |
| `clickId` | The matched click identifier. |
| `attributionId` | The backend's attribution record id. |
| `asn`, `osVersion`, `screenResolution`, `rawLink` | Diagnostic context from the match. |
| `tenantKey` | **Cache this** — identifies which tenant this install belongs to. |

---

## 9. Deferred Deep Linking

When a handshake resolves a deferred deep-link target (e.g. a new user clicked an ad for
a specific store, installed, and should be navigated there on first open), you get it
with a one-shot consumer:

```swift
if let ddl = await ColadaSDK.shared.consumeDeferredDeepLink() {
    if let storeId = ddl.storeId {
        navigate(to: .store(id: storeId))
    } else if let menuItemId = ddl.menuItemId {
        navigate(to: .menuItem(id: menuItemId))
    }
}
```

Point by point:

- Returns the DDL target **exactly once per handshake**, then `nil` until the next
  successful handshake re-arms it.
- This guarantees the app **never re-navigates** the user on every launch.
- Call it after the first successful handshake — typically in the same flow where you
  read `lastAttribution` or stream `observeAttribution()`.

---

## 10. Report lifecycle events

Report the events that matter for ad optimization. The SDK accepts exactly **9 fixed
event names**:

| Event | Raw value | When to fire |
|---|---|---|
| `.completeRegistration` | `CompleteRegistration` | Use `reportRegistration` instead (§11) |
| `.login` | `Login` | User logged in |
| `.purchase` | `Purchase` | Order completed |
| `.subscribe` | `Subscribe` | Subscription started/renewed |
| `.addToCart` | `AddToCart` | Item added to cart |
| `.initiateCheckout` | `InitiateCheckout` | Checkout started |
| `.viewContent` | `ViewContent` | Item/page viewed |
| `.placeAnOrder` | `PlaceAnOrder` | Order placed |
| `.search` | `Search` | Search performed |

> There is **no `.download`** case — the install event is fired automatically by the
> handshake. Never report it yourself.

```swift
do {
    let result = try await ColadaSDK.shared.reportEvent(
        .purchase,
        metadata: AttributionEventMetadata(amount: 99.5, currency: "SAR", orderId: "ORD-123")
    )
    print("attributed: \(result.attributed)")
} catch {
    print("event failed: \(error)")
}
```

Point by point:

- **`metadata`**: `amount`, `currency`, `orderId`.
  - `amount` + `currency` are **required by the backend for `.purchase`/`.subscribe`** —
    omitting them means the event value is 0, which degrades ad-optimization quality.
  - `currency` **defaults to `"SAR"`** — pass the right value if your store is not in
    Saudi Riyals.
- **Retries**: the SDK retries with backoff up to a bounded attempt count, then throws.
- **Queueing**: if the network is down after retries, the event is placed in the offline
  queue and re-sent later (§12).
- **Suspension**: if `configure()` hasn't finished, the call suspends (never throws for
  that reason).
- **Throws** `ColadaError.missingExternalUserId` if `setExternalUserId` hasn't been
  called (§6).
- **The result** — check `.attributed` if you care whether the event linked to a
  campaign. `attributed: false` is a normal organic install, **not an error** — the
  event is still recorded server-side. `duplicate: true` means the backend recognized a
  replay (retries are already idempotent — dedup happens server-side).

---

## 11. Report registration with user data

`CompleteRegistration` is the **one event that can carry raw user data**, and it has its
own method. Call it **after your sign-up API returns successfully**, passing exactly what
your form collected:

```swift
let userInfo = ColadaUserInfo(
    name: form.name,
    email: form.email,
    phoneNumber: form.phone
)
let result = try await ColadaSDK.shared.reportRegistration(userInfo: userInfo)
```

Point by point:

- **`ColadaUserInfo` fields** — `name`, `email`, `phoneNumber`. All optional; **only
  present fields leave the device**. Do not fabricate values to "complete" the record.
- **This is the only path** that transmits raw PII, and it is opt-in per call —
  `reportEvent` never carries user data for any other event name.
- **The backend hashes `phoneNumber`** before forwarding it to ad platforms.
- The privacy manifest declares `Name`/`EmailAddress`/`PhoneNumber` because this path
  exists (§15).
- Same semantics as `reportEvent`: retry budget, queue-on-failure, `.attributed` result,
  `missingExternalUserId` guard.

---

## 12. Offline queue: `flush()` and `pendingEvents()`

When an event exhausts its retry budget (offline, backend 5xx), it is persisted to an
**offline queue** and re-sent later — events are never lost to a flaky connection.

### Flush — force a re-send

```swift
await ColadaSDK.shared.flush()
```

- Re-sends every event sitting in the queue, in FIFO order.
- Also runs **automatically** after every successful `configure()` and after every
  successful `reportEvent`.
- Call it yourself when you control the moment the network comes back — e.g. from
  `NWPathMonitor` — instead of waiting for the next launch.
- Stops at the first failure, which stays queued (everything behind it stays queued
  too, in order).

### Inspect the queue (diagnostics)

```swift
for pending in await ColadaSDK.shared.pendingEvents() {
    print("\(pending.eventName) / \(pending.eventId) / user \(pending.externalUserId)")
}
```

- Returns one entry per queued event in FIFO order.
- Each entry carries identity only: `eventId`, `eventName`, `externalUserId`, `deviceId`.
- Purely diagnostic — reading it triggers nothing, and you don't need it to use the SDK.

---

## 13. Session token (diagnostics)

Every SDK call authorizes with a session token minted during `configure` and cached in
the Keychain. The SDK manages the full lifecycle automatically:

- **Proactive refresh** within an hour of its 24h expiry.
- **Reactive re-mint** on a `401 TOKEN_EXPIRED` response.

```swift
// Current token state — expiry, tenant key, and a short prefix.
// NEVER the token itself. Diagnostic-only; reading it triggers no network call.
if let info = await ColadaSDK.shared.sessionToken {
    print("expires: \(info.expiry), tenant: \(info.tenantKey)")
}

// Force a fresh token exchange even if the current one is still valid.
// Only for verifying an integration — normal apps never call this.
let fresh = try await ColadaSDK.shared.refreshSessionToken()
```

---

## 14. Device identity

```swift
let deviceId = await ColadaSDK.shared.deviceIdentity
```

- A stable per-device UUID persisted in the **Keychain**.
- Survives **uninstall/reinstall** unconditionally — this is how the backend ties a
  fresh install back to a prior attribution.
- Suspends on an unfinished `configure()` like other calls.
- You generally never need to read it — it exists for diagnostics and advanced wiring.

---

## 15. Privacy, App Tracking Transparency, and opt-out

- **No IDFA.** The SDK does not read the advertising identifier and never requests
  App Tracking Transparency permission. No ATT prompt will ever appear because of this
  SDK.
- **Privacy manifest** — the SDK ships `PrivacyInfo.xcprivacy`, declaring:
  - Collected data types: `DeviceId`, plus `Name`/`EmailAddress`/`PhoneNumber` (the
    `reportRegistration` path — §11) and `OtherUserContent` as applicable.
  - `NSPrivacyTrackingDomains` for the Colada backend.
- **Blocked-by-ATT handling**: if the user has not authorized tracking, iOS may block
  requests to the SDK's tracking domain. The SDK surfaces this as
  `ColadaError.blockedByTrackingPrevention` (§16) rather than the misleading "offline"
  error.
- **Full opt-out / GDPR delete**:

```swift
await ColadaSDK.shared.reset()
```

  `reset()` wipes **everything** — device identity, session token, stored attribution,
  pending events, all persisted SDK state.

---

## 16. Errors and how to handle them

All errors are thrown as `ColadaError` (with associated values where useful). A
practical handling pattern:

```swift
do {
    try await ColadaSDK.shared.reportEvent(.purchase, metadata: ...)
} catch ColadaError.missingExternalUserId {
    // You forgot setExternalUserId — fix the flow, don't retry now.
} catch ColadaError.backendRejected(let status, let message) {
    // Client bug (bad key/missing field). Show the server's message.
    print("Backend rejected (\(status)): \(message ?? "—")")
} catch ColadaError.blockedByTrackingPrevention {
    // iOS privacy policy blocked the request. Retrying won't help until ATT is granted.
} catch {
    // .deliveryFailed, .networkError, .tokenExpired, ... — safe to retry later.
}
```

Every case, point by point:

| Case | When it happens | What to do |
|---|---|---|
| `.deliveryFailed(attempts:)` | Retry budget exhausted without success (429/5xx/network). The event was queued offline. | Nothing urgent — it will be re-sent via `flush()`/next launch. |
| `.encodingFailed` | Request body could not be JSON-encoded. | Internal invariant — report it, retrying won't help. |
| `.networkError` | `URLSession` failed outside the retry path (e.g. request cancelled). | Retry later. |
| `.missingExternalUserId` | `reportEvent`/`reportRegistration` before `setExternalUserId`. | Fix the flow — call `setExternalUserId` first. |
| `.backendRejected(statusCode:message:)` | Backend answered 400/401/404 — a client bug, e.g. bad API key or missing required field. | Read `message` (the server's `{"message": …}`), fix the call. Not transient. |
| `.invalidConversionValue` | SKAdNetwork conversion value outside `0...63`. | Internal invariant — don't call SKAdNetwork code with out-of-range values. |
| `.blockedByTrackingPrevention` | iOS blocked the request because the user hasn't authorized ATT. | Inform the user / wait for ATT grant. Retrying cannot help. |
| `.tokenExpired` | Backend returned `401 TOKEN_EXPIRED` even after automatic re-mint. | Rare. Realistic causes: device clock far off, or tenant key revoked mid-session. Check the clock first. |
| `.deviceIdentityUnavailable` | `configure()` couldn't read the persisted device identity from the Keychain (e.g. device rebooted and still locked). | Retry `configure()` later. Nothing was changed — the SDK deliberately does not mint a new id here (that would rotate the uninstall-surviving identity). |

---

## 18. Minimum integration checklist

- [ ] SDK added to the app target (`Colada` product).
- [ ] `ColadaSDK.shared.configure(apiKey:)` called once at launch.
- [ ] Every deep link forwarded to `handleDeepLink(_:)` (cold-start and hot).
- [ ] `setExternalUserId` called after login/signup, before the first event.
- [ ] `reportEvent`/`reportRegistration` called at the lifecycle moments you care about.
- [ ] `consumeDeferredDeepLink()` called on first open after handshake (if you support DDL).
- [ ] `reset()` wired to your account-deletion/opt-out flow.

That's the complete integration — roughly 10 lines of SDK calls for the core flow.

---

## 19. Troubleshooting

Each entry lists the **symptom**, the **cause**, and the **fix**, point by point.

### 19.1 `failed downloading ... Colada.xcframework.zip: badResponseStatusCode(404)`

**Symptom:** dependency resolution fails with a 404 on the binary download URL.

**Causes:**
- The package repo is **private** — SPM's `binaryTarget` cannot send credentials, so
  unauthenticated downloads of a private release return 404.
- The **version you pinned has no release** — the `url` in `Package.swift` points at
  `releases/download/<tag>/...`, and that tag/asset doesn't exist.
- Your app is still pinned to the **old package URL** (`3laween/colada-sdk-spm`), which
  no longer exists.

**Fixes:**
1. Make sure the package repo is **public** (SPM requires it for binary downloads).
2. Pin a version that actually has a published release (`from: "0.1.0"` — the current
   one). Check the tag name in `Package.swift`'s `binaryTarget` matches a real release.
3. Migrate to the current URL: `https://github.com/3laween/colada-sdk-ios`.
4. Verify the URL in a browser/`curl` — it should download the zip directly.
5. After any change: **File ▸ Packages ▸ Reset Package Caches** (or delete
   `~/Library/Developer/Xcode/DerivedData`) and re-resolve.

### 19.2 `no such module 'Colada'`

**Symptom:** `import Colada` fails after adding the package.

**Causes / fixes:**
- The **`Colada` product wasn't added to your app target** — in the package dialog,
  select the `Colada` library and add it to the target explicitly.
- The binary **failed to download** earlier and Xcode cached the failure — Reset Package
  Caches (19.1).
- **Stale DerivedData** — delete `~/Library/Developer/Xcode/DerivedData` and rebuild.

### 19.3 "The Internet connection appears to be offline" (-1009) but the network is fine

**Cause:** iOS **privacy-blocked** the request — the user has not granted App Tracking
Transparency, so requests to the SDK's tracking domain are refused. The OS reports it
with the misleading `NSURLErrorNotConnectedToInternet`.

**Fix:** this is `ColadaError.blockedByTrackingPrevention`. Retrying cannot help — wait
for ATT to be granted, or test on a device where it has been. Don't chase network bugs;
there are none.

### 19.4 Nothing arrives after `configure` — no attribution, no events

Check, in order:
1. **Ordinary app opens are silent by design.** The self-driving policy sends traffic
   only on first install and on deep links. This is expected — see §7.
2. **`matched: false` is normal** for an organic install — not a failure (§8).
3. Verify the SDK actually works: read `lastAttribution`, subscribe to
   `observeAttribution()`, and inspect `sessionToken` (or force
   `refreshSessionToken()`) to confirm the token exchange happened (§13).
4. On a **first install**, the clipboard read waits (bounded) for the app to reach the
   foreground — launch the app to the foreground, don't start it in the background.

### 19.5 `reportEvent` throws `missingExternalUserId`

**Cause:** `setExternalUserId(_:)` hasn't been called yet (§6).

**Fix:** call `setExternalUserId` after login/signup and before the first event. This is
a flow bug, not a network issue — don't retry; fix the ordering.

### 19.6 `backendRejected` with 400 / 401 / 404

**Causes:** a client bug — bad `apiKey` (or revoked), a missing required field
(e.g. `amount`/`currency` on `.purchase`/`.subscribe`), or an invalid request shape.

**Fix:** read the server's `message` (the error carries it) and fix the call. This case
is **not transient** — retrying the same bad request will keep failing.

### 19.7 `tokenExpired`

**Cause:** the backend rejected the session token as expired even **after** the SDK's
automatic re-mint — i.e. a freshly minted token also came back expired.

**Realistic causes:** the device clock is far enough off that a brand-new token reads as
already expired, or the tenant key was revoked mid-session.

**Fix:** check the device clock (enable automatic time), confirm the key is still valid.
The SDK's automatic recovery is already exhausted by the time this reaches you.

### 19.8 `deviceIdentityUnavailable` from `configure`

**Cause:** the Keychain was unreadable — typically the device **rebooted and is still
locked**, so Keychain access fails.

**Fix:** retry `configure()` later. Nothing was changed: the SDK deliberately does **not**
mint a new id here, because minting would rotate the identity that survives
uninstall/reinstall (and break attribution continuity).

### 19.9 Deep links never reach the SDK

**Causes / fixes:**
- The OS only delivers URLs your app is **registered to receive**:
  - Custom URL schemes: add `CFBundleURLTypes` to your `Info.plist`.
  - Universal links: configure **Associated Domains** and the AASA file.
- You're only handling one of the two delivery paths — forward **both** cold start
  (`launchOptions[.url]`) and hot (`application(_:open:)`) links to
  `handleDeepLink(_:)` (§5).
- Test the link from a browser / Notes app, not from a debugger that may swallow the
  delivery.

### 19.10 `duplicate: true` in an event result

**Expected.** Retried events are idempotent — the backend deduplicates server-side by
tenant + user + event name. `duplicate: true` means the backend recognized a replay and
did **not** forward it to the ad platforms again. Nothing to fix (§10).

### 19.11 Events "disappeared" while offline

**Cause:** nothing is lost — events that exhaust their retry budget are persisted to the
**offline queue**.

**Fix:** they're re-sent automatically after the next successful `configure()` or
`reportEvent`, or manually via `flush()` (e.g. from `NWPathMonitor` when the network
returns). Inspect the queue with `pendingEvents()` (§12).

### 19.12 The app keeps navigating the user to a store page

**Cause:** `consumeDeferredDeepLink()` is **one-shot per handshake** — if your app
re-navigates on every launch, you're probably reading `attributionStoreId` from
`lastAttribution` instead of consuming the DDL (§9).

**Fix:** use `consumeDeferredDeepLink()` — it returns the target exactly once, then
`nil` until the next handshake re-arms it.

### 19.13 Simulator behavior differs from a device

- **Clipboard**: the first-install clipboard read works on the simulator but depends on
  the pasteboard contents — a handshake with `matched: false` on an empty simulator
  pasteboard is expected.
- **Keychain**: simulator keychains persist per simulator — wiping the app does not
  always wipe the Keychain identity. Use `reset()` if you need a clean slate.
- **Privacy block (19.3)** behaves the same, but ATT state must be granted explicitly in
  the simulator's Settings.

### 19.14 App Store Connect privacy warnings

- The SDK ships its own `PrivacyInfo.xcprivacy` — its collected-data declarations
  (`DeviceId`, and `Name`/`EmailAddress`/`PhoneNumber` when you use
  `reportRegistration`) and tracking domains are already covered by the SDK's manifest.
- **You** must declare in **your app's** manifest anything your own code collects. If
  you never call `reportRegistration`, no user PII ever leaves the device through the
  SDK.

### 19.15 Version / cache problems in general

- Pin with `from: "0.1.0"` and let `Package.resolved` lock it.
- Released artifacts are **immutable** — a published version's binary is never replaced,
  so a lockfile that resolved once keeps resolving.
- On any unexplained behavior after an update: **Reset Package Caches**, delete
  DerivedData, rebuild.

### 19.16 CocoaPods users

- The **binary package is SPM-only** — there is no prebuilt pod.
- The SDK repository ships a `ColadaSDK.podspec` for source integrators; the module is
  named `Colada` there too, so `import Colada` works identically.

---

## 20. Common questions

**Q: Do I need to call `handshake()`?**
No. `configure()` handles first installs (self-driving, clipboard included) and
`handleDeepLink` handles re-engagements. The manual API exists for edge cases only.

**Q: `matched: false` — is something broken?**
No. It means an organic install with no ad campaign behind it. It is a normal result.

**Q: Why is there no ATT prompt / IDFA usage?**
The SDK doesn't use IDFA. Attribution resolves through your click data + the stable
device identity + your user ID.

**Q: Does the SDK keep working offline?**
Events are retried with backoff and then queued offline; `flush()` or the next launch
re-sends them. `configure` failures leave the handshake gate open for the next launch.

**Q: I see `NSURLErrorNotConnectedToInternet` (-1009) but the network is fine.**
That's iOS's privacy-blocked behavior; the SDK re-surfaces it as
`ColadaError.blockedByTrackingPrevention`. It resolves once ATT is granted.

**Q: How do I verify the token exchange is working?**
Read `sessionToken` (never exposes the token itself) or call
`refreshSessionToken()` — diagnostics only.

**Q: Versions?**
The package tracks the SDK versions one-for-one: package `0.1.0` is
`Colada.xcframework` `0.1.0`. Released artifacts are immutable.