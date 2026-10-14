// swift-tools-version:6.2

import PackageDescription

/// The `/v1` client for the Apple apps (APP-001). Types and client are generated from
/// `aaru-server/Sources/AppAPI/openapi.yaml` and committed, so Xcode needs no build plugin.
let package = Package(
    name: "aaru-api",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "AaruAPI", targets: ["AaruAPI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "AaruAPI",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ]
        ),
        .testTarget(name: "AaruAPITests", dependencies: ["AaruAPI"]),
    ]
)
