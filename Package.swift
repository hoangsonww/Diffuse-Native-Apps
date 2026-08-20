// swift-tools-version: 6.0
import PackageDescription

// Diffuse is deliberately dependency-free: every module below is first-party.
// This keeps CI hermetic, keeps the supply chain auditable, and keeps the
// core domain packages portable across every Apple platform we target.

let strictConcurrency: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
]

func core(_ name: String, dependencies: [Target.Dependency] = []) -> Target {
    .target(
        name: name,
        dependencies: dependencies,
        path: "Packages/\(name)/Sources/\(name)",
        swiftSettings: strictConcurrency
    )
}

func suite(_ name: String, dependencies: [Target.Dependency]) -> Target {
    .testTarget(
        name: "\(name)Tests",
        dependencies: dependencies + ["DiffuseTestSupport"],
        path: "Packages/\(name)/Tests/\(name)Tests",
        swiftSettings: strictConcurrency
    )
}

let package = Package(
    name: "Diffuse",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .watchOS(.v10),
        .tvOS(.v17),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "DiffuseModels", targets: ["DiffuseModels"]),
        .library(name: "DiffuseDiff", targets: ["DiffuseDiff"]),
        .library(name: "DiffuseStorage", targets: ["DiffuseStorage"]),
        .library(name: "DiffuseCapabilities", targets: ["DiffuseCapabilities"]),
        .library(name: "DiffuseCore", targets: ["DiffuseCore"]),
        .library(name: "DiffuseDeveloperTools", targets: ["DiffuseDeveloperTools"]),
        .library(name: "DiffuseCollectors", targets: ["DiffuseCollectors"]),
        .library(name: "DiffuseUI", targets: ["DiffuseUI"]),
        .executable(name: "diffuse-dev", targets: ["diffuse-dev"]),
    ],
    targets: [
        // MARK: - Domain

        core("DiffuseModels"),
        core("DiffuseDiff", dependencies: ["DiffuseModels"]),
        core("DiffuseStorage", dependencies: ["DiffuseModels"]),
        core("DiffuseCapabilities", dependencies: ["DiffuseModels"]),
        core("DiffuseCore", dependencies: ["DiffuseModels", "DiffuseDiff", "DiffuseStorage", "DiffuseCapabilities"]),

        // MARK: - Platform-facing

        core("DiffuseDeveloperTools", dependencies: ["DiffuseModels", "DiffuseCapabilities"]),
        core("DiffuseCollectors", dependencies: [
            "DiffuseModels", "DiffuseCapabilities", "DiffuseCore", "DiffuseStorage", "DiffuseDeveloperTools",
        ]),
        core(
            "DiffuseUI",
            dependencies: ["DiffuseModels", "DiffuseDiff", "DiffuseCore", "DiffuseStorage", "DiffuseCapabilities"]
        ),

        // MARK: - Tools

        .executableTarget(
            name: "diffuse-dev",
            dependencies: [
                "DiffuseModels", "DiffuseDiff", "DiffuseStorage",
                "DiffuseCore", "DiffuseCapabilities", "DiffuseCollectors", "DiffuseDeveloperTools",
            ],
            path: "Tools/diffuse-dev/Sources/diffuse-dev",
            swiftSettings: strictConcurrency
        ),

        // MARK: - Test support

        .target(
            name: "DiffuseTestSupport",
            dependencies: ["DiffuseModels", "DiffuseDiff", "DiffuseStorage", "DiffuseCapabilities", "DiffuseCore"],
            path: "Tests/Support",
            swiftSettings: strictConcurrency
        ),

        // MARK: - Suites

        suite("DiffuseModels", dependencies: ["DiffuseModels"]),
        suite("DiffuseDiff", dependencies: ["DiffuseDiff", "DiffuseModels"]),
        suite("DiffuseStorage", dependencies: ["DiffuseStorage", "DiffuseModels"]),
        suite("DiffuseCapabilities", dependencies: ["DiffuseCapabilities", "DiffuseModels"]),
        suite("DiffuseCore", dependencies: ["DiffuseCore", "DiffuseModels", "DiffuseDiff", "DiffuseStorage"]),
        suite("DiffuseDeveloperTools", dependencies: ["DiffuseDeveloperTools", "DiffuseModels"]),
        suite(
            "DiffuseCollectors",
            dependencies: ["DiffuseCollectors", "DiffuseModels", "DiffuseCapabilities", "DiffuseDeveloperTools"]
        ),
        suite("DiffuseUI", dependencies: ["DiffuseUI", "DiffuseModels", "DiffuseDiff"]),

        .testTarget(
            name: "DiffuseDomainTests",
            dependencies: [
                "DiffuseTestSupport", "DiffuseModels", "DiffuseDiff", "DiffuseStorage",
                "DiffuseCore", "DiffuseCapabilities",
            ],
            path: "Tests/Domain",
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "DiffuseInvariantTests",
            dependencies: [
                "DiffuseTestSupport", "DiffuseModels", "DiffuseDiff", "DiffuseStorage",
                "DiffuseCore", "DiffuseCapabilities",
            ],
            path: "Tests/Invariants",
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "DiffuseIntegrationTests",
            dependencies: [
                "DiffuseTestSupport", "DiffuseModels", "DiffuseDiff", "DiffuseStorage",
                "DiffuseCore", "DiffuseCapabilities", "DiffuseCollectors", "DiffuseDeveloperTools",
            ],
            path: "Tests/Integration",
            swiftSettings: strictConcurrency
        ),
    ],
    swiftLanguageModes: [.v6]
)
