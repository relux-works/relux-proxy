// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ReluxProxy",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "ReluxProxy", targets: ["ReluxProxy"]),
    ],
    targets: [
        .executableTarget(
            name: "ReluxProxy",
            path: "Sources/ReluxProxy"
        ),
        .testTarget(
            name: "ReluxProxyTests",
            dependencies: ["ReluxProxy"],
            path: "Tests/ReluxProxyTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
