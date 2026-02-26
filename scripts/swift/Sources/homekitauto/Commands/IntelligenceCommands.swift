/// IntelligenceCommands.swift
/// Analyze home setup and provide automation suggestions and energy insights.
///
/// Maps to MCP tools:
/// - `homekit_suggest_automations` — Suggest command generates recommendations
/// - `homekit_analyze_energy` — Energy command shows usage patterns
/// - `homekit_get_config` / `homekit_set_config` — Config command manages preferences
///
/// Uses HomeAnalyzer to examine device types, existing automations, and patterns
/// to generate smart suggestions and provide consumption insights.

import ArgumentParser
import Foundation

/// Analyzes home setup and suggests useful automations.
///
/// This command queries the discovered device map and existing automations,
/// then uses HomeAnalyzer to generate relevant suggestions based on:
/// - Available device types (thermostats, lights, switches, etc.)
/// - Current automation coverage
/// - Selected focus area (energy, security, comfort, convenience)
/// - Industry best practices
///
/// Output:
/// - Suggestion name and category
/// - Reason why it's recommended
/// - Trigger and action descriptions
/// - Formatted list or JSON array
///
/// Usage:
///   hka intelligence suggest
///   hka intelligence suggest --focus energy
///   hka intelligence suggest --focus security --json
struct Suggest: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Suggest useful automations based on your home setup."
    )

    /// Focus area for suggestions (energy, security, comfort, convenience)
    @Option(name: .long, help: "Focus area: energy, security, comfort, convenience")
    var focus: String?

    /// When true, returns suggestions as formatted JSON instead of formatted list
    @Flag(name: .long, help: "Output as JSON")
    var json = false

    /// Discovers devices, loads automations, analyzes patterns, and generates suggestions
    func run() async throws {
        let client = SocketClient()

        // Step 1: Discover current device map
        let discoverResponse = try await client.send(command: "discover")
        guard discoverResponse.isOk else {
            throw SocketError.helperError("Cannot discover devices: \(discoverResponse.error ?? "")")
        }

        // Step 2: Load existing automations from registry
        let registry = AutomationRegistry()
        let existingAutomations = try registry.loadAll()

        // Step 3: Analyze home and generate suggestions
        let analyzer = HomeAnalyzer(
            deviceMap: discoverResponse.data,
            existingAutomations: existingAutomations,
            focus: focus
        )
        var suggestions = analyzer.generateSuggestions()

        // Step 4: Add seasonal suggestions
        suggestions += analyzer.generateSeasonalSuggestions()

        // Step 5: Add pattern-based suggestions from execution log
        let log = try registry.loadLog()
        suggestions += analyzer.generatePatternSuggestions(from: log)

        // Output suggestions in requested format
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(["suggestions": suggestions])
            print(String(data: jsonData, encoding: .utf8) ?? "{}")
            return
        }

        if suggestions.isEmpty {
            print("No new suggestions — your home is well-automated!")
            return
        }

        // Display suggestions in formatted list
        print("Suggested Automations")
        print("=====================")
        for (i, suggestion) in suggestions.enumerated() {
            print("\n\(i + 1). \(suggestion.name) [\(suggestion.category)]")
            print("   Why: \(suggestion.reason)")
            print("   Trigger: \(suggestion.trigger)")
            for action in suggestion.actions {
                print("   - \(action)")
            }
        }
    }
}

/// Provides energy consumption and usage insights for the home.
///
/// This command analyzes:
/// - Currently active devices and their power consumption
/// - Historical automation execution counts
/// - Most frequently run automations
/// - Consumption patterns over selected period
///
/// Insights help identify:
/// - Devices always running that could be optimized
/// - Automations that run frequently (tuning opportunities)
/// - Peak usage times
/// - Energy-saving recommendations
///
/// Output:
/// - Currently active devices
/// - Automation run counts and most active automation
/// - Insights and optimization suggestions
/// - JSON format for machine consumption
///
/// Usage:
///   hka intelligence energy
///   hka intelligence energy --period month
///   hka intelligence energy --period week --json
struct Energy: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Get energy and usage insights for your home."
    )

    /// Time period for analysis (today, week, month; default: week)
    @Option(name: .long, help: "Period: today, week, month (default: week)")
    var period: String = "week"

    /// When true, includes historical energy analysis with execution patterns, peak hours, and device-level estimates
    @Flag(name: .long, help: "Include historical energy analysis")
    var history = false

    /// When true, returns insights as formatted JSON instead of formatted summary
    @Flag(name: .long, help: "Output as JSON")
    var json = false

    /// Discovers devices, loads automation history, analyzes patterns, and reports insights
    func run() async throws {
        let client = SocketClient()

        // Step 1: Get current device states and capabilities
        let discoverResponse = try await client.send(command: "discover")
        guard discoverResponse.isOk else {
            throw SocketError.helperError("Cannot discover devices: \(discoverResponse.error ?? "")")
        }

        // Step 2: Load automation registry and execution history
        let registry = AutomationRegistry()
        let automations = try registry.loadAll()
        let log = try registry.loadLog(period: period)

        // Step 3: Analyze current state and generate insights
        let analyzer = HomeAnalyzer(
            deviceMap: discoverResponse.data,
            existingAutomations: automations,
            focus: "energy"
        )
        let insights = analyzer.generateEnergyInsights(log: log, period: period)

        // If --history is set, generate extended historical analysis
        var historyData: [String: AnyCodableValue]? = nil
        if history {
            historyData = generateEnergyHistory(log: log, automations: automations, deviceMap: discoverResponse.data)
        }

        // Output insights in requested format
        if json {
            var output = insights
            if let hd = historyData {
                output["history"] = .dictionary(hd)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(output)
            print(String(data: jsonData, encoding: .utf8) ?? "{}")
            return
        }

        // Display insights as human-readable summary
        print("Energy Summary (\(period))")
        print("========================")

        // Show currently active devices
        if let devicesOn = insights["devicesCurrentlyOn"]?.arrayValue {
            print("\nCurrently Active:")
            for device in devicesOn {
                print("  - \(device)")
            }
        }

        // Show automation execution count
        if let runs = insights["automationRuns"]?.intValue {
            print("\nAutomation Runs: \(runs)")
        }

        // Show most frequently executed automation
        if let mostActive = insights["mostActiveAutomation"]?.stringValue {
            print("Most Active: \(mostActive)")
        }

        // Show generated insights and recommendations
        if let insightsList = insights["insights"]?.arrayValue {
            print("\nInsights:")
            for insight in insightsList {
                print("  * \(insight)")
            }
        }

        // Show historical analysis if --history flag is set
        if let hd = historyData {
            print("\nHistorical Analysis")
            print("-------------------")

            if let energyAutomations = hd["energyRelatedAutomations"]?.arrayValue {
                print("  Energy-related automations: \(energyAutomations.count)")
                for auto in energyAutomations {
                    if let name = auto.stringValue {
                        print("    - \(name)")
                    }
                }
            }

            if let weekChange = hd["weekOverWeekChange"]?.stringValue {
                print("  Week-over-week execution change: \(weekChange)")
            }

            if let peakHours = hd["peakUsageHours"]?.arrayValue {
                let hourStrings = peakHours.compactMap { $0.stringValue }
                print("  Peak usage hours: \(hourStrings.joined(separator: ", "))")
            }

            if let estimates = hd["deviceEnergyEstimates"]?.arrayValue {
                print("  Device energy estimates:")
                for est in estimates {
                    if let dict = est.dictionaryValue,
                       let name = dict["device"]?.stringValue,
                       let wh = dict["estimatedWh"]?.stringValue {
                        print("    - \(name): ~\(wh)")
                    }
                }
            }
        }
    }

    /// Generates historical energy analysis from the automation execution log.
    ///
    /// Computes:
    /// - Which automations affect energy-related devices (thermostats, lights, outlets)
    /// - Week-over-week change in execution frequency
    /// - Device-level energy estimates based on device type and automation frequency
    /// - Peak usage hours from the execution log
    ///
    /// - Parameters:
    ///   - log: Automation execution log entries.
    ///   - automations: All registered automations for cross-referencing device types.
    ///   - deviceMap: Current device map for device category lookup.
    /// - Returns: Dictionary with historical energy analysis data.
    func generateEnergyHistory(
        log: [AutomationLogEntry],
        automations: [RegisteredAutomation],
        deviceMap: AnyCodableValue?
    ) -> [String: AnyCodableValue] {
        var result: [String: AnyCodableValue] = [:]

        // Find which automations affect energy-related devices
        var energyRelatedNames: [String] = []
        for auto in automations {
            let affectsEnergy = auto.actions.contains { action in
                // Check if the action targets energy characteristics
                let energyChars: Swift.Set<String> = ["power", "brightness", "targetTemperature", "hvacMode", "active"]
                return energyChars.contains(action.characteristic) || action.type == "scene"
            }
            if affectsEnergy {
                energyRelatedNames.append(auto.name)
            }
        }
        result["energyRelatedAutomations"] = .array(energyRelatedNames.map { .string($0) })

        // Week-over-week change in execution frequency
        let formatter = ISO8601DateFormatter()
        let now = Date()
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now

        let thisWeekRuns = log.filter { entry in
            guard let date = formatter.date(from: entry.timestamp) else { return false }
            return date >= oneWeekAgo
        }.count

        let lastWeekRuns = log.filter { entry in
            guard let date = formatter.date(from: entry.timestamp) else { return false }
            return date >= twoWeeksAgo && date < oneWeekAgo
        }.count

        if lastWeekRuns > 0 {
            let changePercent = Int(Double(thisWeekRuns - lastWeekRuns) / Double(lastWeekRuns) * 100)
            let changeStr = changePercent >= 0 ? "+\(changePercent)%" : "\(changePercent)%"
            result["weekOverWeekChange"] = .string("\(changeStr) (\(lastWeekRuns) -> \(thisWeekRuns) runs)")
        } else {
            result["weekOverWeekChange"] = .string("No data from previous week")
        }

        // Peak usage hours
        var hourCounts: [Int: Int] = [:]
        for entry in log {
            if let date = formatter.date(from: entry.timestamp) {
                let hour = Calendar.current.component(.hour, from: date)
                hourCounts[hour, default: 0] += 1
            }
        }

        let sortedHours = hourCounts.sorted { $0.value > $1.value }
        let topHours = sortedHours.prefix(3).map { (hour, count) -> String in
            let amPm = hour >= 12 ? "\(hour == 12 ? 12 : hour - 12) PM" : "\(hour == 0 ? 12 : hour) AM"
            return "\(amPm) (\(count) runs)"
        }
        result["peakUsageHours"] = .array(topHours.map { .string($0) })

        // Device-level energy estimates (rough estimates based on device type)
        // Watts estimates: light ~10W, thermostat ~varies, outlet ~100W, fan ~50W
        let deviceTypeWatts: [String: Double] = [
            "light": 10.0, "lightbulb": 10.0,
            "thermostat": 0.0, // Can't estimate HVAC from automation data alone
            "outlet": 100.0,
            "fan": 50.0,
            "switch": 60.0
        ]

        // Build device name → category lookup from device map for energy estimates
        var deviceCategories: [String: String] = [:]
        if let homes = deviceMap?.dictionaryValue?["homes"]?.arrayValue {
            for home in homes {
                guard let rooms = home.dictionaryValue?["rooms"]?.arrayValue else { continue }
                for room in rooms {
                    guard let accessories = room.dictionaryValue?["accessories"]?.arrayValue else { continue }
                    for accessory in accessories {
                        if let name = accessory.dictionaryValue?["name"]?.stringValue,
                           let cat = accessory.dictionaryValue?["category"]?.stringValue {
                            deviceCategories[name] = cat
                        }
                    }
                }
            }
        }

        var deviceEstimates: [[String: AnyCodableValue]] = []
        // Estimate energy from automations that control power on devices
        for auto in automations where energyRelatedNames.contains(auto.name) {
            let runsForAuto = log.filter { $0.automationName == auto.name }.count
            for action in auto.actions {
                if action.characteristic == "power" && action.value.boolValue == true {
                    // Estimate: device runs for ~1 hour per automation trigger
                    let category = deviceCategories[action.deviceName] ?? "unknown"
                    let watts = deviceTypeWatts[category] ?? 10.0
                    let estimatedWh = watts * Double(runsForAuto) // 1 hour per run
                    deviceEstimates.append([
                        "device": .string(action.deviceName),
                        "category": .string(category),
                        "estimatedWh": .string(String(format: "%.0f Wh", estimatedWh)),
                        "runsInPeriod": .int(runsForAuto)
                    ])
                }
            }
        }
        result["deviceEnergyEstimates"] = .array(deviceEstimates.map { .dictionary($0) })

        return result
    }
}

/// Views or modifies HomeKit Automator global configuration.
///
/// Configuration settings control:
/// - defaultHome: Which home to use when --home flag is not specified
/// - filterMode: Device visibility mode (all or allowlist)
/// - Other helper preferences and behavior settings
///
/// When no flags are provided, displays current configuration.
/// When update flags are provided, applies changes then shows updated config.
///
/// Output:
/// - Configuration key-value pairs in sorted order
/// - JSON format for machine consumption
///
/// Usage:
///   hka intelligence config
///   hka intelligence config --show
///   hka intelligence config --default-home "Main House"
///   hka intelligence config --filter-mode allowlist --json
struct Config: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "View or modify HomeKit Automator configuration."
    )

    /// Sets the default home to use when --home flag is not specified in commands
    @Option(name: .long, help: "Set the default home")
    var defaultHome: String?

    /// Sets device visibility mode (all or allowlist for filtered discovery)
    @Option(name: .long, help: "Set filter mode: all, allowlist")
    var filterMode: String?

    /// When true, explicitly shows current configuration
    @Flag(name: .long, help: "Show current configuration")
    var show = false

    /// When true, returns configuration as formatted JSON instead of text
    @Flag(name: .long, help: "Output as JSON")
    var json = false

    /// Updates config if parameters provided, then displays current configuration
    func run() async throws {
        let client = SocketClient()

        // Apply updates if any configuration changes specified
        if defaultHome != nil || filterMode != nil {
            var params: [String: AnyCodableValue] = [:]
            if let home = defaultHome {
                params["defaultHome"] = .string(home)
            }
            if let mode = filterMode {
                params["filterMode"] = .string(mode)
            }

            let response = try await client.send(command: "set_config", params: params)
            guard response.isOk else {
                throw SocketError.helperError(response.error ?? "Failed to update config")
            }
            print("Configuration updated.")
        }

        // Display configuration (either after update or if --show or no update flags)
        if show || (defaultHome == nil && filterMode == nil) {
            let response = try await client.send(command: "get_config")
            guard response.isOk else {
                throw SocketError.helperError(response.error ?? "Failed to get config")
            }

            // Output in requested format
            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let data = response.data {
                    let jsonData = try encoder.encode(data)
                    print(String(data: jsonData, encoding: .utf8) ?? "{}")
                }
            } else if let config = response.data?.dictionaryValue {
                // Display configuration as sorted key-value pairs
                print("Configuration")
                print("=============")
                for (key, value) in config.sorted(by: { $0.key < $1.key }) {
                    print("  \(key): \(value)")
                }
            }
        }
    }
}
