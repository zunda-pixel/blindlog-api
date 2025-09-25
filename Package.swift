// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "App",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
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
    .package(url: "https://github.com/hummingbird-project/hummingbird-auth.git", from: "2.0.0"),
    .package(
      url: "https://github.com/hummingbird-project/hummingbird-postgres.git",
      from: "1.0.0-rc.1"
    ),
    .package(url: "https://github.com/vapor/postgres-kit.git", from: "2.0.0"),
    .package(url: "https://github.com/valkey-io/valkey-swift.git", from: "0.2.0"),
    // https://github.com/swift-server/swift-webauthn/pull/107
    .package(
      url: "https://github.com/zunda-pixel/swift-webauthn.git",
      branch: "custom-ChallengeGenerator"
    ),
    .package(url: "https://github.com/swift-server/swift-openapi-hummingbird.git", from: "2.0.0"),
    .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.10.0"),
    .package(url: "https://github.com/vapor/jwt-kit.git", from: "5.0.0"),
    .package(url: "https://github.com/coenttb/swift-records.git", from: "0.0.1"),
  ],
  targets: [
    .executableTarget(
      name: "App",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Hummingbird", package: "hummingbird"),
        .product(name: "HummingbirdAuth", package: "hummingbird-auth"),
        .product(name: "HummingbirdPostgres", package: "hummingbird-postgres"),
        .product(name: "PostgresKit", package: "postgres-kit"),
        .product(name: "Valkey", package: "valkey-swift"),
        .product(name: "WebAuthn", package: "swift-webauthn"),
        .product(name: "OpenAPIHummingbird", package: "swift-openapi-hummingbird"),
        .product(name: "JWTKit", package: "jwt-kit"),
        .product(name: "Records", package: "swift-records"),
      ],
      plugins: [
        .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
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
