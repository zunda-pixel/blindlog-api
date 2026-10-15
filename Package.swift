// swift-tools-version: 6.4

import PackageDescription

let package = Package(
  name: "App",
  platforms: [.macOS(.v27)],
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
    .package(url: "https://github.com/vapor/postgres-kit.git", from: "2.0.0"),
    .package(url: "https://github.com/swift-server/swift-openapi-hummingbird.git", from: "2.0.0"),
    .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.14.1"),
    .package(url: "https://github.com/vapor/jwt-kit.git", from: "5.4.0"),
    .package(url: "https://github.com/zunda-pixel/cloudflare-swift.git", from: "0.8.2"),
    .package(url: "https://github.com/hummingbird-project/hummingbird-postgres.git", from: "1.0.0"),
    .package(url: "https://github.com/valkey-io/valkey-swift.git", from: "1.3.0"),
    .package(url: "https://github.com/swift-otel/swift-otel.git", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-certificates.git", from: "1.19.1"),
    .package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "0.4.0"),
    .package(url: "https://github.com/adam-fowler/swift-zip-archive.git", from: "0.7.0"),
    .package(
      url: "https://github.com/zunda-pixel/pass-builder.git",
      branch: "feat/in-memory-signed-pass"
    ),
    .package(
      url: "https://github.com/zunda-pixel/swift-postgresql.git",
      branch: "fix-postgresql-closure-lifetime",
      traits: ["PostgresNIO"]
    ),
    .package(url: "https://github.com/swift-compositions/swift-sql.git", branch: "main"),
    .package(url: "https://github.com/zunda-pixel/swift-currency.git", from: "0.0.1"),
    .package(url: "https://github.com/zunda-pixel/swift-webauthn.git", branch: "add-init"),
    .package(url: "https://github.com/zunda-pixel/UUIDV7.git", branch: "replace-to-swift-testing"),
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
        .product(name: "PostgreSQL", package: "swift-postgresql"),
        .product(name: "SQL Macros", package: "swift-sql"),
        .product(name: "SQL Foundation Integration", package: "swift-sql"),
        .product(name: "Currency", package: "swift-currency"),
        .product(name: "CloudflareEmailService", package: "cloudflare-swift"),
        .product(name: "CloudflareImages", package: "cloudflare-swift"),
        .product(name: "UUIDV7", package: "UUIDV7"),
        .product(name: "OTel", package: "swift-otel"),
        .product(name: "PassBuilder", package: "pass-builder"),
      ],
      resources: [.copy("Resources/PassIcon")],
      swiftSettings: [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableUpcomingFeature("ImmutableWeakCaptures"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .defaultIsolation(nil),
        .strictMemorySafety(),
        .treatAllWarnings(as: .error),
      ],
      plugins: [
        .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
      ],
    ),
    .testTarget(
      name: "AppTests",
      dependencies: [
        .target(name: "App"),
        .product(name: "HummingbirdTesting", package: "hummingbird"),
        .product(name: "OTel", package: "swift-otel"),
        .product(name: "X509", package: "swift-certificates"),
        .product(name: "ZipArchive", package: "swift-zip-archive"),
        .product(name: "Subprocess", package: "swift-subprocess"),
      ]
    ),
  ]
)
