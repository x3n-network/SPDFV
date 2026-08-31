// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SPDFVCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SPDFVCore", targets: ["SPDFVCore"])
    ],
    targets: [
        .target(name: "SPDFVCore"),
        .testTarget(name: "SPDFVCoreTests", dependencies: ["SPDFVCore"])
    ]
)
