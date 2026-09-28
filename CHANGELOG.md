# Changelog

All notable changes to the Colada iOS SDK (`Colada`) are documented here. Format loosely
follows [Keep a Changelog](https://keepachangelog.com/); versions follow semver.

## 0.2.1 — 2026-08-24

- **More reliable deep link attribution.** Re-engagement links now attribute correctly on
  iOS, matching Android — so campaigns that bring existing users back into your app are
  measured accurately.

## 0.2.0 — 2026-08-19

### Removed — BREAKING

- **PII collection removed. The SDK now collects a single value: `deviceId`.** Removed
  `ColadaSDK.identifyUser(email:phone:)` and `AttributionEventMetadata.phoneNumber`.
  `externalUserId` — your own opaque user id — is the only user identifier the SDK holds.

  **Migration:** delete `identifyUser(...)` calls; `setExternalUserId(_:)` is now the whole
  of identity. Drop the `phoneNumber:` argument from any `AttributionEventMetadata(...)`
  initializer.

- **App Tracking Transparency and the IDFA are no longer used.** Removed
  `ColadaSDK.requestTrackingPermission()`, `ColadaSDK.idfa`, and the public
  `ColadaTrackingStatus` enum; `AppTrackingTransparency` and `AdSupport` are no longer
  linked. Attribution runs off the SDK's own per-install identity plus the deep-link signal
  an app open carries.

  **Migration:** delete any `requestTrackingPermission()` / `idfa` call — nothing replaces
  them. Remove `NSUserTrackingUsageDescription` from your `Info.plist`.

  **Required:** the SDK's `PrivacyInfo.xcprivacy` now declares `NSPrivacyTracking = false`
  with an empty `NSPrivacyTrackingDomains`. If your app's own manifest still lists
  `backend.coladaapp.io` as a tracking domain, iOS will block requests to it and surface the
  block as `-1009 "The Internet connection appears to be offline"`. Remove it.

### Added

- **`ColadaClipboard` — opt-in attribution-token paste access.** The SDK never reads the
  pasteboard on its own. When your app opts in, `ColadaClipboard.readAttributionToken()`
  performs a single read; only Colada's own attribution tokens are ever returned, and an
  empty pasteboard costs no prompt.
- **Automatic session authentication.** `configure()` now authenticates the SDK with the
  backend transparently and attaches the credential to subsequent requests — fully
  automatic, integrators write no auth code. `ColadaSDK.sessionToken` and
  `ColadaSDK.refreshSessionToken()` are available as integration diagnostics; neither is
  needed in production code.
- **`ColadaSKAdNetwork`** — wrapper over Apple's SKAdNetwork conversion-value API
  (SKAN 4.0 on iOS 16.1+, with fallback to earlier generations).
- **Offline retry queue** — event reports that exhaust their retry budget are queued and
  re-sent on the next successful `configure()`.

### Changed

- **`configure(apiKey:)` now throws — and the device identity can never be silently
  rotated.** A real device-identity storage read failure (e.g. device rebooted and still
  locked) now throws `ColadaError.deviceIdentityUnavailable` with no state changed, so the
  next call retries the read instead of overwriting the stable, reinstall-surviving id.

  **BREAKING:** `configure(apiKey:)` changes from `async` to `async throws`. Existing call
  sites need `try`. A fresh install behaves exactly as before.

### Fixed

- **`reset()` now fully severs the previous device session** and persists the regenerated
  device identity, so a relaunch no longer produces a second identity.

## 0.1.1 — 2026-08-15

First public release.
