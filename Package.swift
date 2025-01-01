// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "SwiftSeeSaw",
  platforms: [
    .macOS(.v14),
    .iOS(.v17),
  ],
  products: [
    // Products define the executables and libraries a package produces, making them visible to
    // other packages.
    .executable(
      name: "SeeSawQuadRotary",
      targets: ["SeeSawQuadRotary"]
    ),
    .library(
      name: "QuadRotary",
      targets: ["QuadRotary"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/PADL/IORingSwift", from: "0.1.5"),
    .package(url: "https://github.com/PADL/LinuxHalSwiftIO", from: "0.1.8"),
//    .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
//    .package(url: "https://github.com/lhoward/AsyncExtensions", from: "0.9.0"),
    .package(url: "https://github.com/madmachineio/SwiftIO", from: "0.1.0"),
  ],
  targets: [
    // Targets are the basic building blocks of a package, defining a module or a test suite.
    // Targets can depend on other targets in this package and products from dependencies.
    .target(
      name: "SeeSaw",
      dependencies: [
        .product(name: "IORing", package: "IORingSwift", condition: .when(platforms: [.linux])),
        .product(name: "SwiftIO", package: "SwiftIO", condition: .when(platforms: [.linux])),
        .product(
          name: "AsyncSwiftIO",
          package: "LinuxHalSwiftIO",
          condition: .when(platforms: [.linux])
        ),
        .product(
          name: "LinuxHalSwiftIO",
          package: "LinuxHalSwiftIO",
          condition: .when(platforms: [.linux])
        ),
      ]
    ),
    .target(
      name: "QuadRotary",
      dependencies: [
        "SeeSaw",
        .product(name: "SwiftIO", package: "SwiftIO", condition: .when(platforms: [.linux])),
        .product(
          name: "AsyncSwiftIO",
          package: "LinuxHalSwiftIO",
          condition: .when(platforms: [.linux])
        ),
        .product(
          name: "LinuxHalSwiftIO",
          package: "LinuxHalSwiftIO",
          condition: .when(platforms: [.linux])
        ),
      ]
    ),
    .executableTarget(
      name: "SeeSawQuadRotary",
      dependencies: [
        "SeeSaw",
        "QuadRotary",
        .product(name: "SwiftIO", package: "SwiftIO", condition: .when(platforms: [.linux])),
        .product(
          name: "AsyncSwiftIO",
          package: "LinuxHalSwiftIO",
          condition: .when(platforms: [.linux])
        ),
        .product(
          name: "LinuxHalSwiftIO",
          package: "LinuxHalSwiftIO",
          condition: .when(platforms: [.linux])
        ),
      ],
      path: "Examples/SeeSawQuadRotary"
    ),
  ]
)
