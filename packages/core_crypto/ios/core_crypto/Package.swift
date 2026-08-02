// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "core_crypto",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "core-crypto", targets: ["core_crypto"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "core_crypto",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                // AuthGate uses app-scoped UserDefaults for retry/lockout
                // counters. Package the matching CA92.1 declaration when this
                // plugin is consumed through Swift Package Manager as well.
                .process("PrivacyInfo.xcprivacy"),
            ]
        )
    ]
)
