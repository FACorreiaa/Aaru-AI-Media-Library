// swift-tools-version:6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "aaru-core",
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18)],
    products: [
        .library(name: "AaruCore", targets: ["AaruCore"]),
    ],
    targets: [
        .target(name: "AaruCore"),
        .testTarget(name: "AaruCoreTests", dependencies: ["AaruCore"]),
    ]
)
