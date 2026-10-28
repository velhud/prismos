// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "PrismCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v8)
    ],
    products: [
        .library(name: "PrismShell", targets: ["PrismShell"]),
        .library(name: "PrismProtocol", targets: ["PrismProtocol"]),
        .library(name: "PrismDraw", targets: ["PrismDraw"]),
        .library(name: "PrismRuntime", targets: ["PrismRuntime"]),
        .library(name: "PrismModels", targets: ["PrismModels"]),
        .library(name: "PrismWatchModels", targets: ["PrismWatchModels"]),
        .library(name: "PrismPersistence", targets: ["PrismPersistence"]),
        .library(name: "PrismDiagnostics", targets: ["PrismDiagnostics"]),
        .library(name: "PrismAI", targets: ["PrismAI"]),
        .library(
            name: "PrismCore",
            targets: [
                "PrismShell",
                "PrismProtocol",
                "PrismDraw",
                "PrismRuntime",
                "PrismModels",
                "PrismWatchModels",
                "PrismPersistence",
                "PrismDiagnostics",
                "PrismAI"
            ]
        )
    ],
    targets: [
        .target(name: "PrismShell", dependencies: ["PrismModels", "PrismDraw", "PrismProtocol", "PrismAI"]),
        .testTarget(name: "PrismShellTests", dependencies: ["PrismShell"], resources: [.copy("Fixtures")]),
        .target(name: "PrismProtocol"),
        .target(name: "PrismDraw", dependencies: ["PrismModels"]),
        .target(name: "PrismRuntime", dependencies: ["PrismDraw", "PrismModels", "PrismDiagnostics"]),
        .target(name: "PrismModels"),
        .target(name: "PrismWatchModels", dependencies: ["PrismModels"]),
        .target(name: "PrismPersistence", dependencies: ["PrismModels"]),
        .target(name: "PrismDiagnostics", dependencies: ["PrismModels"]),
        .target(name: "PrismAI", dependencies: ["PrismModels", "PrismDiagnostics"]),
        .testTarget(name: "PrismProtocolTests", dependencies: ["PrismProtocol"]),
        .testTarget(name: "PrismDrawTests", dependencies: ["PrismDraw"]),
        .testTarget(name: "PrismRuntimeTests", dependencies: ["PrismRuntime"]),
        .testTarget(name: "PrismWatchModelsTests", dependencies: ["PrismWatchModels"]),
        .testTarget(name: "PrismPersistenceTests", dependencies: ["PrismPersistence"]),
        .testTarget(name: "PrismDiagnosticsTests", dependencies: ["PrismDiagnostics"]),
        .testTarget(name: "PrismAITests", dependencies: ["PrismAI"])
    ]
)
