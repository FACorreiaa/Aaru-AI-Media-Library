// swift-tools-version:6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "aaru-server",
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18)],
    products: [
        .executable(name: "aaru", targets: ["aaru"]),
    ],
    dependencies: [
        .package(path: "../aaru-core"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.25.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-fluent.git", from: "2.0.0"),
        .package(
            url: "https://github.com/apple/swift-configuration.git",
            from: "1.0.0",
            traits: [.defaults, "CommandLineArguments"]
        ),
        .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.7.0"),
        .package(url: "https://github.com/hummingbird-project/swift-openapi-hummingbird.git", from: "2.0.1"),
        .package(url: "https://github.com/vapor/fluent-kit.git", from: "1.56.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.12.0"),
        .package(url: "https://github.com/vapor/jwt-kit.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0" ..< "5.0.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.33.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.80.0"),
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "aaru",
            dependencies: [
                .product(name: "AaruCore", package: "aaru-core"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "Configuration", package: "swift-configuration"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "JWTKit", package: "jwt-kit"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "FluentKit", package: "fluent-kit"),
                .product(name: "FluentSQL", package: "fluent-kit"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdFluent", package: "hummingbird-fluent"),
                .byName(name: "aaruAPI"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIHummingbird", package: "swift-openapi-hummingbird"),
            ],
            path: "Sources/App"
        ),
        .target(
            name: "aaruAPI",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
            path: "Sources/AppAPI",
            plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]
        ),
        .testTarget(
            name: "aaruTests",
            dependencies: [
                .byName(name: "aaru"),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
                .product(name: "JWTKit", package: "jwt-kit"),
                .product(name: "FluentSQL", package: "fluent-kit"),
            ],
            path: "Tests/AppTests"
        ),
    ]
)
