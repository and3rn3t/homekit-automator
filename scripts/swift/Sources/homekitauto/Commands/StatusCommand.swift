/// StatusCommand.swift
/// Displays the current connectivity status of the HomeKit Automator bridge and home summary.
///
/// Maps to MCP tool: `homekit_check_status`
/// Queries the socket bridge for connection state, active homes, accessory counts, and automation registry.

import ArgumentParser
import Foundation

/// Checks the status of the HomeKit Automator bridge and displays summary information.
///
/// This command queries the socket bridge service to determine if it is currently connected
/// to HomeKit, and retrieves summary information about:
/// - Bridge connection state (Connected/Disconnected)
/// - Number of configured homes
/// - Accessory count per home
/// - Total automation count
///
/// Output formats:
/// - Plain text: Human-readable status table (default)
/// - JSON: Machine-parsable status object (--json flag)
///
/// Usage:
///   hka status
///   hka status --json
struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check HomeKit Automator bridge connectivity and status."
    )

    /// When true, returns status as formatted JSON instead of human-readable text
    @Flag(name: .long, help: "Output as JSON")
    var json = false

    /// Queries the socket bridge for status and displays it in the specified format
    func run() async throws {
        let client = SocketClient()
        let response = try await client.send(command: "status")

        if !response.isOk {
            throw SocketError.helperError(response.error ?? "Unknown error")
        }

        // Output response in requested format
        if json {
            if let data = response.data {
                try printJSON(data)
            }
        } else {
            // Format response as human-readable status report
            print("HomeKit Automator Status")
            print("========================")
            if let data = response.data?.dictionaryValue {
                // Display bridge connection status
                if let connected = data["connected"]?.boolValue {
                    print("Bridge: \(connected ? "Connected" : "Disconnected")")
                }
                // Display each home and its accessory count
                if let homes = data["homes"]?.arrayValue {
                    print("Homes: \(homes.count)")
                    for home in homes {
                        if let name = home.dictionaryValue?["name"]?.stringValue,
                           let count = home.dictionaryValue?["accessoryCount"]?.intValue {
                            print("  - \(name) (\(count) accessories)")
                        }
                    }
                }
                // Display total automation count from registry
                if let automations = data["automationCount"]?.intValue {
                    print("Automations: \(automations)")
                }
            }
        }
    }
}
