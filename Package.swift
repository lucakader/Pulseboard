// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Pulseboard",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Pulseboard", targets: ["PulseboardApp"]),
        .library(name: "PulseboardCore", targets: ["PulseboardCore"])
    ],
    targets: [
        .target(
            name: "PulseboardSystem",
            path: "Sources/PulseboardSystem",
            publicHeadersPath: "include"
        ),
        .target(
            name: "PulseboardCore",
            dependencies: ["PulseboardSystem"],
            path: "Sources/PulseboardCore"
        ),
        .executableTarget(
            name: "PulseboardApp",
            dependencies: ["PulseboardCore"],
            path: "Sources/PulseboardApp"
        ),
        .testTarget(
            name: "PulseboardTests",
            dependencies: ["PulseboardCore"],
            path: "Tests/PulseboardTests"
        )
    ]
)
