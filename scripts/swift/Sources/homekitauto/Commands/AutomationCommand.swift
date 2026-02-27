/// AutomationCommand.swift
/// Define, manage, and execute home automation workflows.
///
/// Maps to MCP tools:
/// - `homekit_create_automation` — AutomationCreate command
/// - `homekit_list_automations` — AutomationList command
/// - `homekit_modify_automation` — AutomationEdit command
/// - `homekit_delete_automation` — AutomationDelete command
/// - `homekit_test_automation` — AutomationTest command
///
/// Automations are registered in a local registry and exported as Apple Shortcuts.
/// Each automation defines a trigger (schedule, sensor, manual), conditions, and actions.

import ArgumentParser
import Foundation

/// Root command for automation management with subcommands.
struct Automation: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage home automations.",
        subcommands: [
            AutomationCreate.self,
            AutomationList.self,
            AutomationEdit.self,
            AutomationDelete.self,
            AutomationTest.self,
        ]
    )
}

// MARK: - Create

/// Creates a new automation from a JSON definition and registers it as an Apple Shortcut.
///
/// This command:
/// 1. Parses automation definition (trigger, conditions, actions)
/// 2. Validates actions against discovered device map
/// 3. Generates an Apple Shortcut file from the actions
/// 4. Imports the Shortcut into macOS Shortcuts app
/// 5. Saves automation to local registry
///
/// The automation definition should include:
/// - name: Display name of the automation
/// - description: Human-readable description (optional)
/// - trigger: Trigger configuration (type: schedule, solar, sensor, manual; cron or expression)
/// - conditions: Array of conditions to evaluate (optional)
/// - actions: Array of device actions (deviceUuid/Name, characteristic, value, optional delaySeconds)
/// - enabled: Whether automation starts enabled (default: true)
///
/// Output: JSON with automation ID, shortcut name, registration status, and action count
///
/// Usage:
///   hka automation create --definition '{"name":"Evening","trigger":{"type":"schedule","cron":"0 18 * * *"},"actions":[...]}'
///   hka automation create --file /path/to/automation.json
struct AutomationCreate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new automation and register it as an Apple Shortcut."
    )

    /// Inline JSON string with the complete automation definition
    @Option(name: .long, help: "Automation definition as inline JSON")
    var definition: String?

    /// File path to JSON file containing the automation definition
    @Option(name: .long, help: "Path to JSON file with automation definition")
    var file: String?

    /// When true, returns result as formatted JSON instead of human-readable text
    @Flag(name: .long, help: "Output as JSON")
    var json = false

    /// Parses automation definition, generates Shortcut, and registers it
    func run() async throws {
        guard let jsonString = definition ?? readFile(file) else {
            throw ValidationError("Provide either --definition or --file with the automation definition.")
        }

        // Step 1: Parse the automation definition from JSON
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw ValidationError("Invalid JSON string.")
        }

        let decoder = JSONDecoder()
        let definition = try decoder.decode(AutomationDefinition.self, from: jsonData)

        // Step 2: Load the automation registry and create config directory
        let registry = AutomationRegistry()
        let configDir = try registry.ensureConfigDir()

        // Step 3: Validate actions against discovered device map
        let client = SocketClient()
        let discoverResponse = try await client.send(command: "discover")
        guard discoverResponse.isOk else {
            throw SocketError.helperError("Cannot validate devices: \(discoverResponse.error ?? "discovery failed")")
        }

        // Step 3b: Validate all actions against device map
        let validator = AutomationValidator()
        let deviceMap = extractDeviceMap(from: discoverResponse)

        do {
            try validator.validateDefinition(definition, deviceMap: deviceMap)
        } catch {
            print("Validation failed: \(error.localizedDescription)")
            throw ExitCode.validationFailure
        }

        // Step 4: Generate the Apple Shortcut file from actions
        let shortcutGenerator = ShortcutGenerator()
        let shortcutName = "HKA: \(definition.name)"
        let shortcutPath = configDir
            .appendingPathComponent("shortcuts")
            .appendingPathComponent(shortcutName.replacingOccurrences(of: " ", with: "_") + ".shortcut")

        try FileManager.default.createDirectory(
            at: shortcutPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try shortcutGenerator.generate(
            name: shortcutName,
            actions: definition.actions,
            outputPath: shortcutPath
        )

        // Step 5: Import the Shortcut into macOS
        let importResult = try await shortcutGenerator.importShortcut(
            name: shortcutName,
            path: shortcutPath
        )

        // Step 6: Create automation record and save to registry
        let automation = RegisteredAutomation(
            id: UUID().uuidString,
            name: definition.name,
            description: definition.description,
            trigger: definition.trigger,
            conditions: definition.conditions,
            actions: definition.actions,
            enabled: definition.enabled ?? true,
            shortcutName: shortcutName,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )

        try registry.save(automation)

        // Output result
        // Include human-readable cron description if available
        var triggerDescription = definition.trigger.humanReadable
        if definition.trigger.type == "schedule", let cron = definition.trigger.cron {
            triggerDescription = validator.humanReadableCron(cron)
        }

        let result: [String: AnyCodableValue] = [
            "id": .string(automation.id),
            "name": .string(automation.name),
            "shortcutName": .string(shortcutName),
            "registered": .bool(importResult),
            "trigger": .string(triggerDescription),
            "actionCount": .int(definition.actions.count)
        ]

        try printJSON(result)
    }

    /// Reads automation definition from file if path is provided
    private func readFile(_ path: String?) -> String? {
        guard let path = path else { return nil }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }
}

// MARK: - List

/// Lists all registered automations with optional filtering.
///
/// Reads automations from the local registry and displays them with:
/// - Enabled/disabled status
/// - Trigger type and expression
/// - Action count
/// - Associated Shortcut name
///
/// Filtering options (--filter):
/// - enabled: Only show enabled automations
/// - disabled: Only show disabled automations
/// - schedule: Only schedule/solar trigger automations
/// - manual: Only manual trigger automations
///
/// Output: Formatted list or JSON array
///
/// Usage:
///   hka automation list
///   hka automation list --filter enabled
///   hka automation list --filter schedule --json
struct AutomationList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all registered automations."
    )

    /// Optional filter to narrow automation list (enabled, disabled, schedule, manual)
    @Option(name: .long, help: "Filter: enabled, disabled, schedule, manual")
    var filter: String?

    /// When true, returns automations as formatted JSON instead of formatted list
    @Flag(name: .long, help: "Output as JSON")
    var json = false

    /// Loads automation registry and displays filtered list
    func run() async throws {
        let registry = AutomationRegistry()
        var automations = try registry.loadAll()

        // Apply filter if specified
        if let filter = filter {
            switch filter {
            case "enabled":
                automations = automations.filter { $0.enabled }
            case "disabled":
                automations = automations.filter { !$0.enabled }
            case "schedule":
                automations = automations.filter { $0.trigger.type == "schedule" || $0.trigger.type == "solar" }
            case "manual":
                automations = automations.filter { $0.trigger.type == "manual" }
            default:
                break
            }
        }

        if json {
            try printJSON(automations)
            return
        }

        if automations.isEmpty {
            print("No automations configured.")
            return
        }

        // Display automations in formatted list
        print("Automations (\(automations.count))")
        print("=============")
        for auto in automations {
            let status = auto.enabled ? "ON" : "OFF"
            print("\n  [\(status)] \(auto.name)")
            print("  Trigger: \(auto.trigger.humanReadable)")
            print("  Actions: \(auto.actions.count) device actions")
            print("  Shortcut: \(auto.shortcutName)")
        }
    }
}

// MARK: - Edit

/// Modifies an existing automation and regenerates its Apple Shortcut if needed.
///
/// Supports updating:
/// - name: Automation display name
/// - description: Automation description
/// - enabled: Boolean to enable/disable without deletion
/// - actions: New array of device actions (triggers Shortcut regeneration)
/// - trigger: New trigger configuration (triggers Shortcut regeneration)
/// - conditions: New conditions array
///
/// If actions or trigger change, the Shortcut is regenerated and re-imported.
///
/// Output: JSON with updated automation data
///
/// Usage:
///   hka automation edit --id "abc-123" --changes '{"enabled":false}'
///   hka automation edit --name "Evening" --changes '{"actions":[...]}'
struct AutomationEdit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Edit an existing automation."
    )

    /// Automation ID to identify which automation to modify
    @Option(name: .long, help: "Automation ID or name")
    var id: String?

    /// Automation name to identify which automation to modify (alternative to --id)
    @Option(name: .long, help: "Automation name")
    var name: String?

    /// JSON object with fields to update (name, description, enabled, actions, trigger, conditions)
    @Option(name: .long, help: "JSON with fields to update")
    var changes: String

    /// Looks up automation, applies changes, regenerates Shortcut if needed, and saves
    func run() async throws {
        let registry = AutomationRegistry()
        let identifier = id ?? name

        guard let identifier = identifier else {
            throw ValidationError("Provide either --id or --name to identify the automation.")
        }

        guard var automation = try registry.find(identifier) else {
            throw ValidationError("Automation not found: \(identifier)")
        }

        // Parse changes and apply to automation
        guard let changesData = changes.data(using: .utf8),
              let changesDict = try JSONSerialization.jsonObject(with: changesData) as? [String: Any] else {
            throw ValidationError("Invalid changes JSON.")
        }

        // Apply simple field updates
        if let newName = changesDict["name"] as? String {
            automation.name = newName
        }
        if let enabled = changesDict["enabled"] as? Bool {
            automation.enabled = enabled
        }
        if let description = changesDict["description"] as? String {
            automation.description = description
        }

        // Decode updated actions, trigger, and conditions if provided
        let decoder = JSONDecoder()
        var updatedActions = automation.actions
        var updatedTrigger = automation.trigger
        var updatedConditions = automation.conditions

        if let actionsValue = changesDict["actions"] {
            let actionsData = try JSONSerialization.data(withJSONObject: actionsValue)
            do {
                updatedActions = try decoder.decode([AutomationAction].self, from: actionsData)
            } catch {
                throw ValidationError("Invalid actions format: \(error.localizedDescription)")
            }
        }

        if let triggerValue = changesDict["trigger"] {
            let triggerData = try JSONSerialization.data(withJSONObject: triggerValue)
            do {
                updatedTrigger = try decoder.decode(AutomationTrigger.self, from: triggerData)
            } catch {
                throw ValidationError("Invalid trigger format: \(error.localizedDescription)")
            }
        }

        if let conditionsValue = changesDict["conditions"] {
            let conditionsData = try JSONSerialization.data(withJSONObject: conditionsValue)
            do {
                updatedConditions = try decoder.decode([AutomationCondition].self, from: conditionsData)
            } catch {
                throw ValidationError("Invalid conditions format: \(error.localizedDescription)")
            }
        }

        // Validate updated actions and trigger against device map
        if changesDict["actions"] != nil || changesDict["trigger"] != nil {
            let client = SocketClient()
            let discoverResponse = try await client.send(command: "discover")
            if discoverResponse.isOk {
                let validator = AutomationValidator()
                let deviceMap = extractDeviceMap(from: discoverResponse)

                if changesDict["actions"] != nil {
                    do {
                        try validator.validateActions(updatedActions, deviceMap: deviceMap)
                    } catch {
                        print("Validation failed: \(error.localizedDescription)")
                        throw ExitCode.validationFailure
                    }
                }

                if changesDict["trigger"] != nil {
                    do {
                        try validator.validateTrigger(updatedTrigger)
                    } catch {
                        print("Validation failed: \(error.localizedDescription)")
                        throw ExitCode.validationFailure
                    }
                }
            }
        }

        // Reconstruct automation with updated fields (trigger/actions/conditions are let properties)
        automation = RegisteredAutomation(
            id: automation.id,
            name: automation.name,
            description: automation.description,
            trigger: updatedTrigger,
            conditions: updatedConditions,
            actions: updatedActions,
            enabled: automation.enabled,
            shortcutName: automation.shortcutName,
            createdAt: automation.createdAt,
            lastRun: automation.lastRun
        )

        // If actions or trigger changed, regenerate the Apple Shortcut
        if changesDict["actions"] != nil || changesDict["trigger"] != nil {
            let shortcutGenerator = ShortcutGenerator()
            let configDir = try registry.ensureConfigDir()
            let shortcutPath = configDir
                .appendingPathComponent("shortcuts")
                .appendingPathComponent(automation.shortcutName.replacingOccurrences(of: " ", with: "_") + ".shortcut")

            try shortcutGenerator.generate(
                name: automation.shortcutName,
                actions: automation.actions,
                outputPath: shortcutPath
            )
            let _ = try await shortcutGenerator.importShortcut(
                name: automation.shortcutName,
                path: shortcutPath
            )
        }

        try registry.update(automation)

        try printJSON(automation)
    }
}

// MARK: - Delete

/// Deletes an automation and removes its associated Apple Shortcut.
///
/// Performs cleanup:
/// - Removes automation from local registry
/// - Deletes associated Apple Shortcut from macOS Shortcuts app
/// - Returns deletion confirmation with Shortcut removal status
///
/// Output: JSON with deletion confirmation and Shortcut removal status
///
/// Usage:
///   hka automation delete --id "abc-123"
///   hka automation delete --name "Evening" --force
struct AutomationDelete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete an automation and its Apple Shortcut."
    )

    /// Automation ID to identify which automation to delete
    @Option(name: .long, help: "Automation ID or name")
    var id: String?

    /// Automation name to identify which automation to delete (alternative to --id)
    @Option(name: .long, help: "Automation name")
    var name: String?

    /// When true, skips confirmation prompt and deletes immediately
    @Flag(name: .long, help: "Skip confirmation prompt")
    var force = false

    /// Looks up automation, deletes registry entry, and removes associated Shortcut
    func run() async throws {
        let registry = AutomationRegistry()
        let identifier = id ?? name

        guard let identifier = identifier else {
            throw ValidationError("Provide either --id or --name.")
        }

        guard let automation = try registry.find(identifier) else {
            throw ValidationError("Automation not found: \(identifier)")
        }

        // Delete the associated Apple Shortcut from macOS
        let shortcutDeleted = await ShortcutGenerator.deleteShortcut(name: automation.shortcutName)

        // Remove automation from registry
        try registry.delete(automation.id)

        // Return confirmation with Shortcut removal status
        let result: [String: AnyCodableValue] = [
            "deleted": .bool(true),
            "name": .string(automation.name),
            "shortcutRemoved": .bool(shortcutDeleted)
        ]

        try printJSON(result)
    }
}

// MARK: - Test

/// Executes an automation immediately (dry-run) without waiting for triggers.
///
/// Test modes:
/// 1. Test a saved automation: Use --id or --name to select automation from registry
/// 2. Test ad-hoc actions: Use --actions with raw JSON array of actions
///
/// Executes all actions sequentially with configured delays:
/// - Scene actions trigger the scene
/// - Device actions set characteristics via socket bridge
/// - Reports success/failure for each action
/// - Counts total successes and failures
///
/// Output: JSON with array of action results, success/failure counts
///
/// Usage:
///   hka automation test --id "abc-123"
///   hka automation test --name "Evening"
///   hka automation test --actions '[{"type":"device","deviceUuid":"...","characteristic":"power","value":true}]'
struct AutomationTest: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Dry-run an automation — execute all actions immediately."
    )

    /// Automation ID to test from registry
    @Option(name: .long, help: "Automation ID or name")
    var id: String?

    /// Automation name to test from registry (alternative to --id)
    @Option(name: .long, help: "Automation name")
    var name: String?

    /// Raw JSON array of actions to test ad-hoc without saving
    @Option(name: .long, help: "Raw actions JSON to test ad-hoc")
    var actions: String?

    /// When true, execute actions even if conditions are not met
    @Flag(name: .long, help: "Execute even if conditions are not met")
    var force = false

    /// Loads automation or parses ad-hoc actions and executes them sequentially
    func run() async throws {
        let client = SocketClient()

        // Load actions from automation registry or parse ad-hoc JSON
        var actionsToTest: [AutomationAction] = []
        var conditionsToCheck: [AutomationCondition] = []

        if let actionsJson = actions {
            // Ad-hoc test from raw actions JSON
            guard let data = actionsJson.data(using: .utf8) else {
                throw ValidationError("Invalid actions JSON.")
            }
            actionsToTest = try JSONDecoder().decode([AutomationAction].self, from: data)
        } else {
            // Test a saved automation from registry
            let identifier = id ?? name
            guard let identifier = identifier else {
                throw ValidationError("Provide --id, --name, or --actions.")
            }

            let registry = AutomationRegistry()
            guard let automation = try registry.find(identifier) else {
                throw ValidationError("Automation not found: \(identifier)")
            }
            actionsToTest = automation.actions
            conditionsToCheck = automation.conditions ?? []
        }

        // Evaluate conditions before executing actions
        var conditionResults: [[String: AnyCodableValue]] = []
        var conditionsAllMet = true

        if !conditionsToCheck.isEmpty {
            // Attempt to load user-configured lat/long from config for solar calculations.
            // Falls back to SolarCalculator defaults (San Francisco) if not configured.
            var lat = SolarCalculator.default.latitude
            var lon = SolarCalculator.default.longitude
            if let configResponse = try? await client.send(command: "get_config"),
               configResponse.isOk,
               let configData = configResponse.data?.dictionaryValue {
                if let userLat = configData["latitude"]?.doubleValue {
                    lat = userLat
                }
                if let userLon = configData["longitude"]?.doubleValue {
                    lon = userLon
                }
            }

            let evaluator = ConditionEvaluator(latitude: lat, longitude: lon)
            let evalResult = try await evaluator.evaluate(conditions: conditionsToCheck, using: client)
            conditionsAllMet = evalResult.allMet

            for r in evalResult.results {
                conditionResults.append([
                    "condition": .string(r.condition.humanReadable),
                    "type": .string(r.condition.type),
                    "met": .bool(r.met),
                    "reason": .string(r.reason)
                ])
            }

            if !conditionsAllMet && !force {
                // Conditions not met and --force not set — report and exit
                let output: [String: AnyCodableValue] = [
                    "tested": .string(name ?? id ?? "ad-hoc"),
                    "conditionsEvaluated": .array(conditionResults.map { .dictionary($0) }),
                    "conditionsMet": .bool(false),
                    "skipped": .bool(true),
                    "reason": .string("Conditions not met. Use --force to execute anyway.")
                ]
                try printJSON(output)
                return
            }
        }

        // Execute each action sequentially and collect results
        var results: [[String: AnyCodableValue]] = []

        for action in actionsToTest {
            // Wait for delay specified in action (if any)
            if action.delaySeconds > 0 {
                try await Task.sleep(nanoseconds: UInt64(action.delaySeconds) * 1_000_000_000)
            }

            // Handle scene actions (trigger_scene command)
            if action.type == "scene" {
                let sceneName = action.sceneName ?? "Unknown"
                let response = try await client.send(
                    command: "trigger_scene",
                    params: ["name": .string(sceneName)]
                )
                results.append([
                    "device": .string(sceneName),
                    "action": .string("trigger scene"),
                    "success": .bool(response.isOk),
                    "error": response.error.map { .string($0) } ?? .null
                ])
                continue
            }

            // Handle regular device characteristic actions (set_device command)
            let response = try await client.send(
                command: "set_device",
                params: [
                    "uuid": .string(action.deviceUuid),
                    "characteristic": .string(action.characteristic),
                    "value": action.value
                ]
            )

            results.append([
                "device": .string(action.deviceName),
                "action": .string("\(action.characteristic) -> \(action.value)"),
                "success": .bool(response.isOk),
                "error": response.error.map { .string($0) } ?? .null
            ])
        }

        // Summarize results
        let succeeded = results.filter { $0["success"]?.boolValue == true }.count
        let failed = results.count - succeeded

        // Output test results (include condition evaluation if any)
        var output: [String: AnyCodableValue] = [
            "tested": .string(name ?? id ?? "ad-hoc"),
            "results": .array(results.map { .dictionary($0) }),
            "succeeded": .int(succeeded),
            "failed": .int(failed)
        ]

        if !conditionResults.isEmpty {
            output["conditionsEvaluated"] = .array(conditionResults.map { .dictionary($0) })
            output["conditionsMet"] = .bool(conditionsAllMet)
            if !conditionsAllMet && force {
                output["forcedExecution"] = .bool(true)
            }
        }

        try printJSON(output)
    }
}
