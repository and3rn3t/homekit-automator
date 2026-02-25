/// DiscoverCommand.swift
/// Maps the entire HomeKit home structure including homes, rooms, devices, and capabilities.
///
/// Maps to MCP tool: `homekit_discover`
/// Recursively enumerates all homes, rooms, accessories, characteristics, and scenes.
/// Includes device reachability status and characteristic permissions (read/write).

import ArgumentParser
import Foundation

/// Discovers and displays the complete HomeKit home structure.
///
/// This command queries the socket bridge to enumerate all available HomeKit data:
/// - All configured homes (with primary home indicator)
/// - Rooms within each home
/// - Accessories (devices) within each room with category and reachability
/// - Characteristics of each accessory with type, value, and read/write permissions
/// - Scenes available in each home
///
/// Output formats:
/// - Default: Hierarchical tree view (homes > rooms > accessories > characteristics)
/// - JSON: Complete structured data (--json flag)
/// - Compact: LLM-optimized summary (--compact flag, shows only writable characteristics)
///
/// Usage:
///   hka discover
///   hka discover --json
///   hka discover --compact
struct Discover: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Discover all HomeKit homes, rooms, devices, and capabilities."
    )

    /// When true, returns discovery data as formatted JSON instead of tree view
    @Flag(name: .long, help: "Output as JSON (default for MCP)")
    var json = false

    /// When true, returns compact output showing only device names and writable characteristics
    @Flag(name: .long, help: "Compact LLM-optimized output")
    var compact = false

    /// Queries the socket bridge to enumerate all HomeKit data and displays it in requested format
    func run() async throws {
        let client = SocketClient()
        let response = try await client.send(command: "discover")

        guard response.isOk else {
            throw SocketError.helperError(response.error ?? "Discovery failed")
        }

        // Output discovery data in requested format
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = response.data {
                let jsonData = try encoder.encode(data)
                print(String(data: jsonData, encoding: .utf8) ?? "{}")
            }
            return
        }

        guard let data = response.data?.dictionaryValue,
              let homes = data["homes"]?.arrayValue else {
            print("No HomeKit data available.")
            return
        }

        for home in homes {
            guard let homeDict = home.dictionaryValue,
                  let homeName = homeDict["name"]?.stringValue else { continue }

            // Display home name with primary indicator
            let isPrimary = homeDict["isPrimary"]?.boolValue ?? false
            print("\n\(homeName)\(isPrimary ? " (Primary)" : "")")
            print(String(repeating: "=", count: homeName.count + (isPrimary ? 10 : 0)))

            guard let rooms = homeDict["rooms"]?.arrayValue else { continue }

            // Iterate through rooms in home
            for room in rooms {
                guard let roomDict = room.dictionaryValue,
                      let roomName = roomDict["name"]?.stringValue else { continue }

                print("\n  \(roomName)")
                print("  " + String(repeating: "-", count: roomName.count))

                guard let accessories = roomDict["accessories"]?.arrayValue else { continue }

                // Display each accessory in the room
                for accessory in accessories {
                    guard let accDict = accessory.dictionaryValue,
                          let name = accDict["name"]?.stringValue,
                          let category = accDict["category"]?.stringValue else { continue }

                    let reachable = accDict["reachable"]?.boolValue ?? false
                    let status = reachable ? "" : " [offline]"

                    if compact {
                        // Compact LLM-optimized format: device name, category, and writable characteristics only
                        var chars: [String] = []
                        if let characteristics = accDict["characteristics"]?.arrayValue {
                            for char in characteristics {
                                if let charDict = char.dictionaryValue,
                                   let type = charDict["type"]?.stringValue,
                                   let writable = charDict["writable"]?.boolValue, writable {
                                    chars.append(type)
                                }
                            }
                        }
                        print("    \(name) (\(category))\(status) -> \(chars.joined(separator: ", "))")
                    } else {
                        // Full format: show all characteristics with values and permissions
                        print("    \(name) [\(category)]\(status)")
                        if let characteristics = accDict["characteristics"]?.arrayValue {
                            for char in characteristics {
                                if let charDict = char.dictionaryValue,
                                   let type = charDict["type"]?.stringValue {
                                    let value = charDict["value"]?.description ?? "?"
                                    let writable = charDict["writable"]?.boolValue ?? false
                                    let rw = writable ? "rw" : "ro"
                                    print("      \(type): \(value) (\(rw))")
                                }
                            }
                        }
                    }
                }
            }

            // Display scenes available in this home
            if let scenes = homeDict["scenes"]?.arrayValue, !scenes.isEmpty {
                print("\n  Scenes")
                print("  ------")
                for scene in scenes {
                    if let sceneDict = scene.dictionaryValue,
                       let name = sceneDict["name"]?.stringValue {
                        let actions = sceneDict["actions"]?.intValue ?? 0
                        print("    \(name) (\(actions) actions)")
                    }
                }
            }
        }

        // Display summary statistics
        if let summary = data["summary"]?.stringValue {
            print("\n\(summary)")
        }
    }
}
