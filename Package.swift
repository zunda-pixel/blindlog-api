// swift-tools-version: 6.1

import PackageDescription

let package = Package(
  name: "BlindLogServer",
  platforms: [
    .macOS(.v15),
  ],
  products: [
    .executable(
      name: "Server",
      targets: ["Server"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/vapor/vapor.git", branch: "vapor-5"),
  ],
  targets: [
    .executableTarget(
      name: "Server",
      dependencies: [
        .product(name: "Vapor", package: "vapor"),
      ]
    ),
    .testTarget(
      name: "ServerTests",
      dependencies: ["Server"]
    ),
  ]
)
