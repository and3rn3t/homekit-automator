/// RoomAndSceneCommands.swift
/// Query and trigger HomeKit rooms and scenes.
///
/// Maps to MCP tools:
/// - `homekit_list_rooms` — Rooms command queries all rooms and accessories
/// - `homekit_list_scenes` — Scenes and TriggerScene commands enumerate and execute scenes
///
/// Provides commands to browse home organization and execute scene automations.

import ArgumentParser
import Foundation

/// Lists all rooms in a HomeKit home with their contained accessories.
///
/// This command queries the socket bridge to retrieve room structure and
/// the accessories assigned to each room.
///
/// Output:
/// - Room names with device count
/// - Each accessory in the room with category (Light, Thermostat, etc.)
/// - Optional filter by home name (--home flag)
/// - Format as JSON with --json flag
///
/// Usage:
///   hka room list
///   hka room list --home "Main House"
///   hka room list --json
struct Rooms: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List rooms and their accessories."
    )

    /// Optional home name filter — if specified, only rooms in this home are listed
    @Option(name: .long, help: "Filter by home name")
    var home: String?

    /// When true, returns rooms as formatted JSON instead of human-readable text
    @Flag(name: .long, help: "Output as JSON")
    var json = false

    /// Queries the socket bridge for room listings and displays them
    func run() async throws {
        let client = SocketClient()
        var params: [String: AnyCodableValue] = [:]
        if let home = home {
            params["home"] = .string(home)
        }

        let response = try await client.send(command: "list_rooms", params: params.isEmpty ? nil : params)

        guard response.isOk else {
            throw SocketError.helperError(response.error ?? "Failed to list rooms")
        }

        // Output rooms in requested format
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = response.data {
                let jsonData = try encoder.encode(data)
                print(String(data: jsonData, encoding: .utf8) ?? "{}")
            }
            return
        }

        guard let rooms = response.data?.dictionaryValue?["rooms"]?.arrayValue else {
            print("No rooms found.")
            return
        }

        // Display each room with its accessory count
        for room in rooms {
            guard let roomDict = room.dictionaryValue,
                  let name = roomDict["name"]?.stringValue else { continue }
            let count = roomDict["accessoryCount"]?.intValue ?? 0
            print("\(name) (\(count) devices)")

            // List accessories in the room with their categories
            if let accessories = roomDict["accessories"]?.arrayValue {
                for acc in accessories {
                    if let accName = acc.dictionaryValue?["name"]?.stringValue,
                       let category = acc.dictionaryValue?["category"]?.stringValue {
                        print("  - \(accName) [\(category)]")
                    }
                }
            }
        }
    }
}

/// Lists all HomeKit scenes with action counts.
///
/// This command queries the socket bridge to retrieve all available scenes
/// and displays how many actions each scene contains.
///
/// Output:
/// - Scene names with action count
/// - Optional filter by home name (--home flag)
/// - Format as JSON with --json flag
///
/// Usage:
///   hka scene list
///   hka scene list --home "Main House"
///   hka scene list --json
struct Scenes: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List available HomeKit scenes."
    )

    /// Optional home name filter — if specified, only scenes in this home are listed
    @Option(name: .long, help: "Filter by home name")
    var home: String?

    /// When true, returns scenes as formatted JSON instead of human-readable text
    @Flag(name: .long, help: "Output as JSON")
    var json = false

    /// Queries the socket bridge for scene listings and displays them
    func run() async throws {
        let client = SocketClient()
        var params: [String: AnyCodableValue] = [:]
        if let home = home {
            params["home"] = .string(home)
        }

        let response = try await client.send(command: "list_scenes", params: params.isEmpty ? nil : params)

        guard response.isOk else {
            throw SocketError.helperError(response.error ?? "Failed to list scenes")
        }

        // Output scenes in requested format
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = response.data {
                let jsonData = try encoder.encode(data)
                print(String(data: jsonData, encoding: .utf8) ?? "{}")
            }
            return
        }

        guard let scenes = response.data?.dictionaryValue?["scenes"]?.arrayValue else {
            print("No scenes found.")
            return
        }

        // Display each scene with its action count
        print("Scenes")
        print("======")
        for scene in scenes {
            if let sceneDict = scene.dictionaryValue,
               let name = sceneDict["name"]?.stringValue {
                let actions = sceneDict["actions"]?.intValue ?? 0
                print("  \(name) (\(actions) actions)")
            }
        }
    }
}

/// Executes a HomeKit scene, triggering all of its configured actions.
///
/// This command sends a trigger request to the socket bridge to activate a scene.
/// The scene performs all its configured actions (typically device state changes)
/// in sequence.
///
/// Output:
/// - Simple confirmation message
/// - Full trigger result as JSON with --json flag
///
/// Usage:
///   hka scene trigger "Good Night"
///   hka scene trigger "Movie Time" --json
struct TriggerScene: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "trigger",
        abstract: "Trigger a HomeKit scene."
    )

    /// Scene name or UUID to execute
    @Argument(help: "Scene name or UUID")
    var scene: String

    /// Optional home name to scope the scene lookup to a specific home
    @Option(name: .long, help: "Home name to scope scene lookup")
    var home: String?

    /// When true, returns trigger result as formatted JSON instead of simple confirmation
    @Flag(name: .long, help: "Output as JSON")
    var json = false

    /// Sends trigger request to socket bridge for the scene
    func run() async throws {
        let client = SocketClient()
        var params: [String: AnyCodableValue] = ["name": .string(scene)]
        if let home = home {
            params["home"] = .string(home)
        }
        let response = try await client.send(
            command: "trigger_scene",
            params: params
        )

        guard response.isOk else {
            throw SocketError.helperError(response.error ?? "Failed to trigger scene")
        }

        // Output result in requested format
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            if let data = response.data {
                let jsonData = try encoder.encode(data)
                print(String(data: jsonData, encoding: .utf8) ?? "{}")
            }
        } else {
            print("Triggered scene: \(scene)")
        }
    }
}
