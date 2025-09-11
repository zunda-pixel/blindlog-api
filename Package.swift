// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "BlindLogServer",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .executable(
      name: "App",
      targets: ["App"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.0.0"),
    .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
    .package(
      url: "https://github.com/hummingbird-project/hummingbird-postgres.git",
      from: "1.0.0-rc.1"
    ),
    .package(url: "https://github.com/vapor/postgres-kit.git", from: "2.0.0"),
    .package(url: "https://github.com/valkey-io/valkey-swift.git", from: "0.1.0"),
  ],
  targets: [
    .executableTarget(
      name: "App",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Hummingbird", package: "hummingbird"),
        .product(name: "HummingbirdPostgres", package: "hummingbird-postgres"),
        .product(name: "PostgresKit", package: "postgres-kit"),
        .product(name: "Valkey", package: "valkey-swift"),
      ]
    ),
    .testTarget(
      name: "AppTests",
      dependencies: [
        .target(name: "App"),
        .product(name: "HummingbirdTesting", package: "hummingbird"),
      ]
    ),
  ]
)
