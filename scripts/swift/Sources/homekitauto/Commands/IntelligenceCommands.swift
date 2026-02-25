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
        let suggestions = analyzer.generateSuggestions()

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

        // Output insights in requested format
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(insights)
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
