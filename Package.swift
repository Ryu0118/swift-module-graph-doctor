// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "swift-module-graph-doctor",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .executable(name: "swift-module-graph-doctor", targets: ["swift-module-graph-doctor"]),
        .library(name: "ModuleGraphDoctorKit", targets: ["ModuleGraphDoctorKit"]),
        .library(name: "ModuleGraphKit", targets: ["ModuleGraphKit"]),
        .library(name: "ModuleGraphLint", targets: ["ModuleGraphLint"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.2"),
        .package(url: "https://github.com/Ryu0118/ProcessRunning", from: "0.2.1"),
        // ProcessRunning 0.2.1はSubprocess 0.2.1のAPI前提。0.3系でExecutionが
        // generic化される破壊的変更が入りビルド不能になるため、exactで固定する
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", exact: "0.2.1"),
        .package(url: "https://github.com/jpsim/Yams", from: "6.2.0"),
        .package(url: "https://github.com/Ryu0118/FileManagerProtocol", from: "0.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "swift-module-graph-doctor",
            dependencies: [
                "ModuleGraphDoctorCLI",
            ],
        ),
        .target(
            name: "ModuleGraphDoctorCLI",
            dependencies: [
                "ModuleGraphDoctorKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
        ),
        .target(
            name: "ModuleGraphKit",
            dependencies: [
                .product(name: "ProcessRunning", package: "ProcessRunning"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "FileManagerProtocol", package: "FileManagerProtocol"),
            ],
        ),
        .target(
            name: "ModuleGraphLint",
            dependencies: [
                "ModuleGraphKit",
                .product(name: "Yams", package: "Yams"),
                .product(name: "FileManagerProtocol", package: "FileManagerProtocol"),
            ],
        ),
        .target(
            name: "ModuleGraphDoctorKit",
            dependencies: [
                "ModuleGraphKit",
                "ModuleGraphLint",
                .product(name: "Yams", package: "Yams"),
                .product(name: "FileManagerProtocol", package: "FileManagerProtocol"),
            ],
        ),
        .testTarget(
            name: "ModuleGraphDoctorCLITests",
            dependencies: [
                "ModuleGraphDoctorCLI",
            ],
        ),
        .testTarget(
            name: "ModuleGraphDoctorKitTests",
            dependencies: [
                "ModuleGraphDoctorKit",
                "ModuleGraphKit",
                "ModuleGraphLint",
            ],
        ),
    ],
)
