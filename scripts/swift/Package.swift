// swift-tools-version: 6.0
// Package.swift — Swift Package Manager manifest for HomeKit Automator
//
// This manifest builds the `homekitauto` CLI tool only. The HomeKitHelper
// (Mac Catalyst app) and the main SwiftUI app are built separately via Xcode
// because they require app bundle signing with the HomeKit entitlement, which
// SPM does not support.
//
// Build targets:
//   SPM:     homekitauto CLI (this manifest)
//   Xcode:   HomeKitHelper.app (Sources/HomeKitHelper/project.yml via XcodeGen)
//
// Dependencies:
//   - swift-argument-parser: Provides the CLI subcommand infrastructure
//   - swift-log: Structured logging via swift-log

import PackageDescription

let package = Package(
    name: "HomeKitAutomator",
    platforms: [
        .macOS(.v14)  // Requires macOS 14 Sonoma for latest HomeKit APIs
    ],
    products: [
        // The CLI binary that users and the MCP server invoke
        .executable(name: "homekitauto", targets: ["homekitauto"]),
        // Shared library containing canonical model types and AnyCodableValue
        .library(name: "HomeKitCore", targets: ["HomeKitCore"]),
    ],
    dependencies: [
        // CLI framework: provides @Argument, @Option, @Flag, and subcommand routing
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.1"),
        // Structured logging framework (available for diagnostic output)
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        // Shared library — canonical AnyCodableValue and model types used by all targets.
        // HomeKitHelper and HomeKitAutomator (Xcode targets) mirror these sources;
        // the CLI and test targets import this module directly.
        //
        // NOTE: Sources/HomeKitHelper/ is intentionally NOT an SPM target.
        // It is built separately via XcodeGen (see Sources/HomeKitHelper/project.yml)
        // because it requires Mac Catalyst + HomeKit entitlement, which SPM cannot provide.
        // HomeKitHelper maintains its own copies of AnyCodableValue and SocketConstants
        // since it cannot import the SPM HomeKitCore module in the XcodeGen build.
        .target(
            name: "HomeKitCore",
            path: "Sources/HomeKitCore"
        ),

        // CLI tool — the user-facing command-line interface.
        // Communicates with HomeKitHelper via Unix domain socket in Application Support directory.
        // Source files are in Sources/homekitauto/ (main.swift, Commands/, Models, etc.)
        .executableTarget(
            name: "homekitauto",
            dependencies: [
                "HomeKitCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/homekitauto",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),

        // Unit tests for CLI models, registry operations, and codable roundtrips.
        // Run with: swift test
        .testTarget(
            name: "HomeKitAutomatorTests",
            dependencies: ["homekitauto", "HomeKitCore"],
            path: "Tests/HomeKitAutomatorTests"
        ),
    ]
)
