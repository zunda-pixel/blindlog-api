// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "BlindLogServer",
  platforms: [
    .macOS(.v26)
  ],
  products: [
    .executable(
      name: "Server",
      targets: ["Server"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/hummingbird-project/hummingbird", from: "2.0.0"),
    .package(url: "https://github.com/hummingbird-project/hummingbird-fluent", from: "2.0.0"),
    .package(url: "https://github.com/valkey-io/valkey-swift", from: "0.1.0"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.1"),
  ],
  targets: [
    .executableTarget(
      name: "Server",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "HummingbirdFluent", package: "hummingbird-fluent"),
        .product(name: "Valkey", package: "valkey-swift"),
      ]
    ),
    .testTarget(
      name: "ServerTests",
      dependencies: [
        .target(name: "Server"),
        .product(name: "HummingbirdTesting", package: "hummingbird"),
      ]
    ),
  ]
)
