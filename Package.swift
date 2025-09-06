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
    .package(url: "https://github.com/zunda-pixel/ValkeyVapor.git", branch: "main"),
    .package(url: "https://github.com/zunda-pixel/Vapor.git", branch: "fix-some-error")
  ],
  targets: [
    .executableTarget(
      name: "Server",
      dependencies: [
        .product(name: "ValkeyVapor", package: "ValkeyVapor")
      ]
    ),
    .testTarget(
      name: "ServerTests",
      dependencies: [
        .target(name: "Server"),
        .product(name: "VaporTesting", package: "Vapor")
      ]
    ),
  ]
)
