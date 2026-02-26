// main.swift
// Entry point for the `homekitauto` command-line tool.
//
// This is the user-facing CLI that communicates with the HomeKitHelper process
// via a Unix domain socket at /tmp/homekitauto.sock. It uses Swift Argument
// Parser to provide a rich subcommand interface with built-in help text.
//
// The CLI is also invoked programmatically by the MCP server (scripts/mcp-server/index.js)
// with the --json flag to produce machine-readable output for AI agents.
//
// Architecture:
//   User / MCP server  →  homekitauto CLI  →  Unix socket  →  HomeKitHelper  →  Apple HomeKit
//
// Subcommands are organized into three groups:
//   - Device control: status, discover, get, set, rooms, scenes, trigger
//   - Automation:     automation (create, list, edit, delete, test)
//   - Intelligence:   suggest, energy, config

import ArgumentParser
import Foundation
import Logging

/// Root command for the HomeKit Automator CLI.
///
/// When invoked without a subcommand, defaults to `status` which checks
/// the bridge connectivity and shows a summary of available homes and accessories.
///
/// Usage:
///   homekitauto                        # Show bridge status (default)
///   homekitauto discover               # Full device discovery
///   homekitauto set "Lights" power on  # Control a device
///   homekitauto automation create ...  # Create an automation
///   homekitauto suggest                # Get automation suggestions
@main
struct HomeKitAuto: AsyncParsableCommand {
    @Flag(name: .shortAndLong, help: "Enable verbose (debug-level) logging.")
    var verbose: Bool = false

    static let configuration = CommandConfiguration(
        commandName: "homekitauto",
        abstract: "Control Apple HomeKit devices and manage automations from the command line.",
        version: "1.0.0",
        subcommands: [
            Status.self,         // Bridge connectivity check
            Discover.self,       // Full home/room/device/scene discovery
            Get.self,            // Read a single device's state
            Set.self,            // Write a characteristic to a device
            Rooms.self,          // List rooms and their accessories
            Scenes.self,         // List available HomeKit scenes
            TriggerScene.self,   // Activate a scene
            Automation.self,     // CRUD operations on automations (has subcommands)
            Suggest.self,        // AI-powered automation suggestions
            Energy.self,         // Usage insights and energy summary
            Config.self,         // View/edit configuration
        ],
        defaultSubcommand: Status.self
    )

    mutating func run() async throws {
        Log.configure(verbose: verbose)
        Log.main.info("HomeKit Automator CLI starting", metadata: ["version": "1.0.0"])
        // Default subcommand (Status) is handled by ArgumentParser
        let status = Status()
        try await status.run()
    }
}
