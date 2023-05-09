// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "MultipeerDistributed",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "MultipeerDistributed",
            targets: ["MultipeerDistributed"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MultipeerDistributed",
            dependencies: []),
        .testTarget(
            name: "MultipeerDistributedTests",
            dependencies: ["MultipeerDistributed"]),
    ]
)
