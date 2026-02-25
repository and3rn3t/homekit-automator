/// DeviceCommands.swift
/// Retrieve and modify device state through HomeKit characteristics.
///
/// Maps to MCP tools:
/// - `homekit_get_device_state` — Get command queries current state
/// - `homekit_set_device_state` — Set command modifies characteristics
///
/// Communicates with socket bridge to read and write HomeKit characteristic values.

import ArgumentParser
import Foundation

/// Retrieves and displays the current state of a HomeKit device.
///
/// This command queries the socket bridge for the complete state of a device,
/// including all accessible characteristics and their current values.
///
/// Output:
/// - Device name and room location
/// - Reachability status (Reachable/Offline)
/// - All characteristics with current values (sorted alphabetically)
/// - Format as JSON with --json flag
///
/// Usage:
///   hka device get "Living Room Light"
///   hka device get "abcd-1234-uuid" --json
struct Get: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Get the current state of a device."
    )

    /// Device name or UUID to query
    @Argument(help: "Device name or UUID")
    var device: String

    /// When true, returns device state as formatted JSON instead of human-readable text
    @Flag(name: .long, help: "Output as JSON")
    var json = false

    /// Queries the socket bridge for device state and displays it
    func run() async throws {
        let client = SocketClient()
        let response = try await client.send(
            command: "get_device",
            params: ["name": .string(device)]
        )

        guard response.isOk else {
            throw SocketError.helperError(response.error ?? "Failed to get device")
        }

        // Output device state in requested format
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = response.data {
                let jsonData = try encoder.encode(data)
                print(String(data: jsonData, encoding: .utf8) ?? "{}")
            }
            return
        }

        guard let data = response.data?.dictionaryValue else {
            print("No device data.")
            return
        }

        // Format response as human-readable device status
        let name = data["device"]?.stringValue ?? device
        let room = data["room"]?.stringValue ?? "Unknown"
        let reachable = data["reachable"]?.boolValue ?? false

        print("\(name) (\(room))")
        print("Status: \(reachable ? "Reachable" : "Offline")")

        // Display all characteristics sorted alphabetically
        if let state = data["state"]?.dictionaryValue {
            for (key, value) in state.sorted(by: { $0.key < $1.key }) {
                print("  \(key): \(value)")
            }
        }
    }
}

/// Modifies a HomeKit device characteristic to a specified value.
///
/// This command sends a set request to the socket bridge to change a device's
/// characteristic. Supports multiple value types:
/// - Boolean: true/false or on/off
/// - Integer: whole numbers
/// - Float: decimal numbers
/// - String: any text value
///
/// Value parsing is automatic: booleans detected first, then integers, floats, then strings.
///
/// Output:
/// - Previous and new values displayed
/// - Full transaction details as JSON with --json flag
///
/// Usage:
///   hka device set "Bedroom Light" power true
///   hka device set "Thermostat" targetTemperature 72.5
///   hka device set "Fan" speed 3 --json
struct Set: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Set a device characteristic to a value."
    )

    /// Device name or UUID to modify
    @Argument(help: "Device name or UUID")
    var device: String

    /// Characteristic name to change (e.g., power, brightness, targetTemperature, hue)
    @Argument(help: "Characteristic name (e.g., power, brightness, targetTemperature)")
    var characteristic: String

    /// Value to set — automatically parsed as bool, int, float, or string
    @Argument(help: "Value to set (true/false, number, or string)")
    var value: String

    /// When true, returns transaction details as formatted JSON instead of short summary
    @Flag(name: .long, help: "Output as JSON")
    var json = false

    /// Parses the value string and sends set request to socket bridge
    func run() async throws {
        let client = SocketClient()

        // Parse value into appropriate type (bool > int > float > string)
        let parsedValue: AnyCodableValue
        if value.lowercased() == "true" || value.lowercased() == "on" {
            parsedValue = .bool(true)
        } else if value.lowercased() == "false" || value.lowercased() == "off" {
            parsedValue = .bool(false)
        } else if let intVal = Int(value) {
            // Try integer first before float
            parsedValue = .int(intVal)
        } else if let doubleVal = Double(value) {
            // Then try floating point
            parsedValue = .double(doubleVal)
        } else {
            // Otherwise treat as string
            parsedValue = .string(value)
        }

        let response = try await client.send(
            command: "set_device",
            params: [
                "name": .string(device),
                "characteristic": .string(characteristic),
                "value": parsedValue
            ]
        )

        guard response.isOk else {
            throw SocketError.helperError(response.error ?? "Failed to set device")
        }

        // Output result in requested format
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            if let data = response.data {
                let jsonData = try encoder.encode(data)
                print(String(data: jsonData, encoding: .utf8) ?? "{}")
            }
        } else if let data = response.data?.dictionaryValue {
            // Display brief summary of the change
            let prev = data["previousValue"]?.description ?? "?"
            let new = data["newValue"]?.description ?? value
            print("\(device): \(characteristic) \(prev) -> \(new)")
        }
    }
}
