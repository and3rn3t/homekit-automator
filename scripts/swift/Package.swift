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
//   - swift-log: Structured logging (currently unused but available for debug builds)

import PackageDescription

let package = Package(
    name: "HomeKitAutomator",
    platforms: [
        .macOS(.v14)  // Requires macOS 14 Sonoma for latest HomeKit APIs
    ],
    products: [
        // The CLI binary that users and the MCP server invoke
        .executable(name: "homekitauto", targets: ["homekitauto"]),
    ],
    dependencies: [
        // CLI framework: provides @Argument, @Option, @Flag, and subcommand routing
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        // Structured logging framework (available for diagnostic output)
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        // CLI tool — the user-facing command-line interface.
        // Communicates with HomeKitHelper via Unix domain socket at /tmp/homekitauto.sock.
        // Source files are in Sources/homekitauto/ (main.swift, Commands/, Models, etc.)
        .executableTarget(
            name: "homekitauto",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/homekitauto",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),

        // Main app target — SwiftUI menu bar application (future)
        // NOTE: This target is built via Xcode, not SPM, because it requires
        // app bundle signing with the HomeKit entitlement. SPM executables cannot
        // carry entitlements. See the Xcode project in Sources/HomeKitAutomator/.
        //
        // .executableTarget(
        //     name: "HomeKitAutomator",
        //     path: "Sources/HomeKitAutomator"
        // ),

        // Helper target — Mac Catalyst app that holds the HomeKit entitlement
        // and runs the HMHomeManager. Built via XcodeGen + xcodebuild.
        // See Sources/HomeKitHelper/project.yml for the Xcode project spec.

        // Unit tests for CLI models, registry operations, and codable roundtrips.
        // Run with: swift test
        .testTarget(
            name: "HomeKitAutomatorTests",
            dependencies: ["homekitauto"],
            path: "Tests/HomeKitAutomatorTests"
        ),
    ]
)
