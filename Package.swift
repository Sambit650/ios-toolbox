// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Toolbox",
    platforms: [.iOS(.v14), .macOS(.v12)],
    products: [
        // Umbrella: everything in one import.
        .library(name: "Toolbox", targets: ["Toolbox"]),
        // Individual modules: import only what you need.
        .library(name: "ToolboxCore", targets: ["ToolboxCore"]),
        .library(name: "ToolboxNetworking", targets: ["ToolboxNetworking"]),
        .library(name: "ToolboxDebug", targets: ["ToolboxDebug"]),
    ],
    targets: [
        .target(name: "ToolboxCore"),
        .target(name: "ToolboxNetworking"),
        .target(name: "ToolboxDebug", dependencies: ["ToolboxNetworking"]),
        .target(
            name: "Toolbox",
            dependencies: ["ToolboxCore", "ToolboxNetworking", "ToolboxDebug"]),

        .testTarget(name: "ToolboxCoreTests", dependencies: ["ToolboxCore"]),
        .testTarget(name: "ToolboxNetworkingTests", dependencies: ["ToolboxNetworking"]),
        .testTarget(name: "ToolboxDebugTests", dependencies: ["ToolboxDebug", "ToolboxNetworking"]),
    ]
)
