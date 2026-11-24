// swift-tools-version: 5.9
import PackageDescription

// PUBLIC binary distribution of the Colada iOS SDK (Core Module).
//
// This package contains NO source code. It points at the compiled `Colada.xcframework`
// published as a GitHub Release on this public repository. The Swift source lives in the
// private `colada-sdk-ios` repository and is never exposed here.
//
// The `url` and `checksum` below are rewritten automatically by the private repo's release
// workflow (.github/workflows/release.yml) on every version tag. Before the first release
// is published they are placeholders and resolution will fail — that is expected.
let package = Package(
    name: "Colada",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "Colada",
            targets: ["Colada"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "Colada",
            url: "https://github.com/3laween/colada-sdk-ios/releases/download/v0.3.0/Colada.xcframework.zip",
            checksum: "329f6e75de1ac7cceccaed9a9ff9ba364255b2ce181bc16a09b68ebc2f057ac6"
        ),
    ]
)
