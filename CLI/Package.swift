// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SPDFVCLI",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "spdfv", targets: ["SPDFVCLI"])
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .executableTarget(
            name: "SPDFVCLI",
            dependencies: [.product(name: "SPDFVCore", package: "Core")]
        ),
        .testTarget(
            name: "SPDFVCLIIntegrationTests",
            dependencies: [.product(name: "SPDFVCore", package: "Core")]
        )
    ]
)
