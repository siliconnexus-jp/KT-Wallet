// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "native_wallet_tabs",
  platforms: [.iOS("15.0")],
  products: [.library(name: "native-wallet-tabs", targets: ["native_wallet_tabs"])],
  dependencies: [.package(name: "FlutterFramework", path: "../FlutterFramework")],
  targets: [
    .target(name: "native_wallet_tabs", dependencies: [
      .product(name: "FlutterFramework", package: "FlutterFramework")
    ])
  ]
)
