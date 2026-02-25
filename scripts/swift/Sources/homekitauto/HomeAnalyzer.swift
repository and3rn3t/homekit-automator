/// HomeAnalyzer.swift
/// The intelligence layer that transforms HomeKit device discovery data into actionable automation suggestions
/// and energy insights.
///
/// ## Role in the System
/// HomeAnalyzer consumes:
/// - `deviceMap`: A hierarchical device structure from HomeKit discovery (homes → rooms → accessories)
/// - `existingAutomations`: A registry of already-configured automations to avoid duplicate suggestions
/// - `focus`: An optional category filter (security, comfort, convenience, energy)
///
/// It produces:
/// - Intelligent automation suggestions organized by category
/// - Energy consumption insights that combine current device states with historical automation logs
///
/// The analyzer operates in two phases:
/// 1. Device Categorization: Traverses the device map to group accessories by type
/// 2. Suggestion Generation: Applies category-specific rules while checking existing automation names
///    to ensure suggestions are novel and valuable
///
/// ## Design Rationale
/// By analyzing what exists in HomeKit (devices) and what's already configured (automations),
/// the analyzer avoids suggesting redundant automations and focuses on genuine gaps.
/// The focus filter enables targeted suggestions for users with specific priorities.

import Foundation

/// Analyzes a HomeKit device map and existing automations to provide intelligent automation suggestions
/// and energy insights based on discovered accessories and their relationships.
///
/// - Parameters:
///   - deviceMap: A nested `AnyCodableValue` structure containing HomeKit homes, rooms, and accessories.
///     Expected shape: `{ "homes": [{ "rooms": [{ "name": String, "accessories": [...] }] }] }`
///     Each accessory should have `name`, `category`, and `characteristics` fields.
///   - existingAutomations: Array of `RegisteredAutomation` objects representing already-configured automations.
///     Used to filter out duplicate suggestions by matching against automation names (case-insensitive).
///   - focus: Optional category filter. When set to "security", "comfort", "convenience", or "energy",
///     only suggestions in that category are generated. When `nil`, all categories are included.
struct HomeAnalyzer {
    /// The hierarchical device map from HomeKit discovery containing homes, rooms, and accessories with their capabilities.
    let deviceMap: AnyCodableValue?

    /// Registry of existing automations, checked to avoid suggesting duplicates.
    let existingAutomations: [RegisteredAutomation]

    /// Optional category filter to focus suggestion generation on a specific domain.
    let focus: String?

    // MARK: - Suggestion Generation

    /// Generates automation suggestions by analyzing the device map and avoiding duplicates.
    ///
    /// ## Algorithm
    /// 1. **Device Categorization**: Traverses the device map (homes → rooms → accessories) and collects
    ///    devices grouped by type: lights, locks, thermostats, motion sensors, contact sensors, garage doors.
    /// 2. **Deduplication Check**: Extracts names from existing automations (case-insensitive) to build
    ///    a set of already-configured suggestion names.
    /// 3. **Category-Specific Rules**: For each of four suggestion categories (security, comfort, convenience, energy),
    ///    applies heuristic rules that generate suggestions when:
    ///    - Relevant devices exist (e.g., locks for security suggestions)
    ///    - No equivalent automation name is already registered
    ///    - The focus filter either matches the category or is `nil` (include all)
    ///
    /// ## Suggestion Categories
    /// - **Security**: Auto-lock at night, close garage at night — protects against unauthorized access
    /// - **Comfort**: Morning warmup, sleep temperature — optimizes environmental conditions
    /// - **Convenience**: Motion-activated lights, all-off routine — reduces manual control
    /// - **Energy**: Away mode — reduces unnecessary heating/cooling and consumption
    ///
    /// - Returns: An array of `AutomationSuggestion` objects ordered by evaluation sequence
    ///           (security → comfort → convenience → energy).
    func generateSuggestions() -> [AutomationSuggestion] {
        var suggestions: [AutomationSuggestion] = []

        guard let homes = deviceMap?.dictionaryValue?["homes"]?.arrayValue else {
            return suggestions
        }

        // Collect all devices by category
        var lights: [(name: String, room: String)] = []
        var locks: [(name: String, room: String)] = []
        var thermostats: [(name: String, room: String)] = []
        var motionSensors: [(name: String, room: String)] = []
        var contactSensors: [(name: String, room: String)] = []
        var garageDoors: [(name: String, room: String)] = []

        for home in homes {
            guard let rooms = home.dictionaryValue?["rooms"]?.arrayValue else { continue }
            for room in rooms {
                guard let roomName = room.dictionaryValue?["name"]?.stringValue,
                      let accessories = room.dictionaryValue?["accessories"]?.arrayValue else { continue }

                for accessory in accessories {
                    guard let name = accessory.dictionaryValue?["name"]?.stringValue,
                          let category = accessory.dictionaryValue?["category"]?.stringValue else { continue }

                    switch category {
                    case "light", "lightbulb":
                        lights.append((name, roomName))
                    case "lock", "doorLock":
                        locks.append((name, roomName))
                    case "thermostat":
                        thermostats.append((name, roomName))
                    case "motionSensor":
                        motionSensors.append((name, roomName))
                    case "contactSensor":
                        contactSensors.append((name, roomName))
                    case "garageDoor", "garageDoorOpener":
                        garageDoors.append((name, roomName))
                    default:
                        break
                    }
                }
            }
        }

        let existingNames = Set(existingAutomations.map { $0.name.lowercased() })

        // MARK: Security Suggestions
        /// Suggests security-focused automations: nighttime locks and garage door closures.
        /// These automations protect against unauthorized access during sleeping hours.
        // Security suggestions
        if focus == nil || focus == "security" {
            if !locks.isEmpty && !existingNames.contains("auto-lock at night") {
                suggestions.append(AutomationSuggestion(
                    name: "Auto-lock at Night",
                    reason: "You have \(locks.count) smart lock(s) but no nighttime locking automation",
                    trigger: "daily at 10:00 PM",
                    actions: locks.map { "\($0.name) -> locked" },
                    category: "security"
                ))
            }

            if !garageDoors.isEmpty && !existingNames.contains("close garage at night") {
                suggestions.append(AutomationSuggestion(
                    name: "Close Garage at Night",
                    reason: "Your garage door has no nighttime close automation",
                    trigger: "daily at 9:00 PM",
                    actions: garageDoors.map { "\($0.name) -> closed" },
                    category: "security"
                ))
            }
        }

        // MARK: Comfort Suggestions
        /// Suggests comfort-focused automations: morning temperature adjustment and sleep-optimized cooling.
        /// These automations ensure environmental conditions support daily routines and sleep quality.
        // Comfort suggestions
        if focus == nil || focus == "comfort" {
            if !thermostats.isEmpty && !existingNames.contains("morning warmup") {
                suggestions.append(AutomationSuggestion(
                    name: "Morning Warmup",
                    reason: "No morning temperature automation found for your thermostat",
                    trigger: "weekdays at 6:30 AM",
                    actions: thermostats.map { "\($0.name) -> heat to 72 F" },
                    category: "comfort"
                ))
            }

            if !thermostats.isEmpty && !existingNames.contains("sleep temperature") {
                suggestions.append(AutomationSuggestion(
                    name: "Sleep Temperature",
                    reason: "Setting a cooler temperature at night can improve sleep quality",
                    trigger: "daily at 10:00 PM",
                    actions: thermostats.map { "\($0.name) -> cool to 67 F" },
                    category: "comfort"
                ))
            }
        }

        // MARK: Convenience Suggestions
        /// Suggests convenience-focused automations: motion-triggered lighting and bulk control routines.
        /// These automations reduce manual interaction by automating common user actions.
        // Convenience suggestions
        if focus == nil || focus == "convenience" {
            /// Motion-activated lights: For each motion sensor, suggest pairing it with lights in the same room.
            /// Checks if the room has both a motion sensor and lights, and whether they're already connected.
            for sensor in motionSensors {
                let roomLights = lights.filter { $0.room == sensor.room }
                if !roomLights.isEmpty {
                    let suggestionName = "Motion-Activated \(sensor.room) Lights"
                    if !existingNames.contains(suggestionName.lowercased()) {
                        suggestions.append(AutomationSuggestion(
                            name: suggestionName,
                            reason: "\(sensor.room) has a motion sensor and lights but they're not connected",
                            trigger: "when \(sensor.name) detects motion",
                            actions: roomLights.map { "\($0.name) -> on, brightness 60%" },
                            category: "convenience"
                        ))
                    }
                }
            }

            /// All-off routine: Suggests a bulk off command for homes with multiple lights (3+).
            /// Useful as a manual trigger for bedtime or leaving the house.
            if lights.count >= 3 && !existingNames.contains("all lights off") {
                suggestions.append(AutomationSuggestion(
                    name: "All Lights Off",
                    reason: "Quick way to turn off all \(lights.count) lights when leaving or going to bed",
                    trigger: "manual (say 'lights off')",
                    actions: ["All lights -> off"],
                    category: "convenience"
                ))
            }
        }

        // MARK: Energy Suggestions
        /// Suggests energy-focused automations: away mode that disables heating/cooling and turns off lights/locks.
        /// Combines thermostat, lighting, and security actions into a single manual routine for energy savings.
        // Energy suggestions
        if focus == nil || focus == "energy" {
            if !thermostats.isEmpty && !existingNames.contains("away mode") {
                suggestions.append(AutomationSuggestion(
                    name: "Away Mode",
                    reason: "No energy-saving away mode detected — could save on heating/cooling",
                    trigger: "manual (say 'I'm leaving')",
                    actions: thermostats.map { "\($0.name) -> eco mode (64 F)" } +
                             lights.map { "\($0.name) -> off" } +
                             locks.map { "\($0.name) -> locked" },
                    category: "energy"
                ))
            }
        }

        return suggestions
    }

    // MARK: - Energy Insights

    /// Generates energy consumption insights by combining live device states with automation execution history.
    ///
    /// ## Algorithm
    /// 1. **Live State Analysis**: Traverses the device map and identifies currently-active devices
    ///    by checking power/active characteristics and thermostat heating/cooling states.
    /// 2. **Historical Analysis**: Processes the automation log to calculate total runs and identify
    ///    the most frequently triggered automation.
    /// 3. **Insight Generation**: Generates context-aware messages based on:
    ///    - Number of active devices (warns if >5 devices are running)
    ///    - Idle state (congratulates if all devices are off)
    /// 4. **Aggregation**: Returns a structured dictionary with period, device lists, run counts, and insights.
    ///
    /// - Parameters:
    ///   - log: Array of `AutomationLogEntry` objects from the automation execution history.
    ///   - period: A human-readable time period label (e.g., "last 7 days", "this month")
    ///            used in the returned insights dictionary.
    ///
    /// - Returns: A dictionary with keys:
    ///   - `period`: The queried time period
    ///   - `devicesCurrentlyOn`: Array of device names and rooms that are currently active
    ///   - `automationRuns`: Total number of automation executions in the period
    ///   - `mostActiveAutomation`: The automation that ran most frequently (or "none")
    ///   - `insights`: Array of contextual recommendations based on current state and history
    func generateEnergyInsights(log: [AutomationLogEntry], period: String) -> [String: AnyCodableValue] {
        var devicesOn: [String] = []
        var insights: [String] = []

        /// Extract current device states: Scan the device map for accessories with active power or
        /// heating/cooling characteristics. Builds a list of "devices on" for energy analysis.
        if let homes = deviceMap?.dictionaryValue?["homes"]?.arrayValue {
            for home in homes {
                guard let rooms = home.dictionaryValue?["rooms"]?.arrayValue else { continue }
                for room in rooms {
                    guard let roomName = room.dictionaryValue?["name"]?.stringValue,
                          let accessories = room.dictionaryValue?["accessories"]?.arrayValue else { continue }

                    for accessory in accessories {
                        guard let name = accessory.dictionaryValue?["name"]?.stringValue,
                              let chars = accessory.dictionaryValue?["characteristics"]?.arrayValue else { continue }

                        for char in chars {
                            guard let type = char.dictionaryValue?["type"]?.stringValue else { continue }

                            /// Check for power/active characteristics: Identifies devices that are currently on.
                            if type == "power" || type == "active" {
                                if char.dictionaryValue?["value"]?.boolValue == true {
                                    devicesOn.append("\(name) (\(roomName))")
                                }
                            }

                            /// Thermostat state check: Detects if heating (val=1) or cooling (val=2) is active.
                            /// Value of 0 means off; >0 indicates active climate control.
                            if type == "currentHeatingCoolingState" {
                                if let val = char.dictionaryValue?["value"]?.intValue, val > 0 {
                                    let mode = val == 1 ? "heating" : "cooling"
                                    devicesOn.append("\(name) (\(mode))")
                                }
                            }
                        }
                    }
                }
            }
        }

        /// Automation execution analysis: Count total runs and identify the most frequently executed automation.
        /// Provides a measure of which automations are most actively driving device behavior.
        let totalRuns = log.count
        var runCounts: [String: Int] = [:]
        for entry in log {
            runCounts[entry.automationName, default: 0] += 1
        }
        let mostActive = runCounts.max(by: { $0.value < $1.value })

        /// Generate contextual insights: Analyzes active device count to surface energy-saving opportunities.
        /// Alerts user if many devices are running simultaneously; congratulates when all are off.
        if devicesOn.count > 5 {
            insights.append("You have \(devicesOn.count) devices currently active — consider if they all need to be on")
        }

        if devicesOn.isEmpty {
            insights.append("All devices are currently off — great for energy savings")
        }

        return [
            "period": .string(period),
            "devicesCurrentlyOn": .array(devicesOn.map { .string($0) }),
            "automationRuns": .int(totalRuns),
            "mostActiveAutomation": .string(
                mostActive.map { "\($0.key) (\($0.value) runs)" } ?? "none"
            ),
            "insights": .array(insights.map { .string($0) })
        ]
    }
}
