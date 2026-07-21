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
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.2"),
        .package(url: "git@github.com:Ryu0118/swift-module-graph-kit.git", from: "0.1.0"),
        .package(url: "git@github.com:Ryu0118/swift-module-graph-lint.git", from: "0.1.0"),
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
            name: "ModuleGraphDoctorKit",
            dependencies: [
                .product(name: "ModuleGraphKit", package: "swift-module-graph-kit"),
                .product(name: "ModuleGraphLint", package: "swift-module-graph-lint"),
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
                .product(name: "ModuleGraphKit", package: "swift-module-graph-kit"),
                .product(name: "ModuleGraphLint", package: "swift-module-graph-lint"),
            ],
        ),
    ],
)
