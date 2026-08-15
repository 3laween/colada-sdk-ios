# Colada iOS SDK (binary)

Public binary distribution of the **Colada iOS SDK — Core Module (`Colada`)**. Attribution,
ad-campaign matching, and lifecycle event reporting for iOS apps.

This repository ships **no source code**. It is a thin Swift Package that references the
compiled `Colada.xcframework`, published as a GitHub Release here. You can add the SDK
without any access to Colada's private source repositories.

Requires iOS 13.0+.

## Install (Swift Package Manager)

In Xcode: **File ▸ Add Package Dependencies…** and enter
`https://github.com/3laween/colada-sdk-ios`, or in a `Package.swift`:

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

```swift
import Colada

Task {
    try await ColadaSDK.shared.configure(apiKey: "pk_live_your_key_here")
}
```

**Full developer documentation: see [USAGE.md](USAGE.md)** — configuration, deep links,
attribution, events, offline queue, privacy, errors, and the optional Platform Module,
explained point by point.

## What's in the binary

- **`Colada`** — Core Module only. Zero third-party dependencies. No App Tracking
  Transparency, no IDFA.

`ColadaPlatform` (optional native TikTok/Meta forwarding) is **not** part of this binary —
it depends on the vendor SDKs and is available only to source integrators.

## How this is built

`Package.swift` here is maintained automatically: the private SDK repository's release
pipeline builds and validates `Colada.xcframework`, publishes it as a Release on this
repo, and updates the `url` + `checksum` in `Package.swift` for each version. Released
artifacts are immutable — a published version's binary is never replaced. This package
tracks the SDK's versions one-for-one — `0.1.0` here is `Colada.xcframework` `0.1.0`.
