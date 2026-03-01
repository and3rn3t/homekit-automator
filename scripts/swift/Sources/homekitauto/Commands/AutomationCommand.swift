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
            AutomationExport.self,
            AutomationImport.self,
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
            throw ValidationError(
                "Provide either --definition or --file with the automation definition.")
        }

        // Step 1: Parse the automation definition from JSON
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw ValidationError("Invalid JSON string.")
        }

        let decoder = JSONDecoder()
        let definition = try decoder.decode(AutomationDefinition.self, from: jsonData)

        // Step 2: Load the automation registry and create config directory
        let registry = AutomationRegistry()
        let configDir = try await registry.ensureConfigDir()

        // Step 3: Validate actions against discovered device map
        let client = SocketClient()
        let discoverResponse = try await client.send(command: "discover")
        guard discoverResponse.isOk else {
            throw SocketError.helperError(
                "Cannot validate devices: \(discoverResponse.error ?? "discovery failed")")
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
        let shortcutPath =
            configDir
            .appendingPathComponent("shortcuts")
            .appendingPathComponent(
                shortcutName.replacingOccurrences(of: " ", with: "_") + ".shortcut")

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
            createdAt: sharedISO8601Formatter.string(from: Date())
        )

        try await registry.save(automation)

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
            "actionCount": .int(definition.actions.count),
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
        var automations = try await registry.loadAll()

        // Apply filter if specified
        if let filter = filter {
            switch filter {
            case "enabled":
                automations = automations.filter { $0.enabled }
            case "disabled":
                automations = automations.filter { !$0.enabled }
            case "schedule":
                automations = automations.filter {
                    $0.trigger.type == "schedule" || $0.trigger.type == "solar"
                }
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

        guard var automation = try await registry.find(identifier) else {
            throw ValidationError("Automation not found: \(identifier)")
        }

        // Parse changes and apply to automation
        guard let changesData = changes.data(using: .utf8),
            let changesDict = try JSONSerialization.jsonObject(with: changesData) as? [String: Any]
        else {
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

        // Decode and validate changes
        let decoded = try await decodeAndValidateChanges(changesDict, automation: automation)

        // Reconstruct automation with updated fields (trigger/actions/conditions are let properties)
        automation = RegisteredAutomation(
            id: automation.id,
            name: automation.name,
            description: automation.description,
            trigger: decoded.trigger,
            conditions: decoded.conditions,
            actions: decoded.actions,
            enabled: automation.enabled,
            shortcutName: automation.shortcutName,
            createdAt: automation.createdAt,
            lastRun: automation.lastRun
        )

        // If actions or trigger changed, regenerate the Apple Shortcut
        if changesDict["actions"] != nil || changesDict["trigger"] != nil {
            let shortcutGenerator = ShortcutGenerator()
            let configDir = try await registry.ensureConfigDir()
            let shortcutPath =
                configDir
                .appendingPathComponent("shortcuts")
                .appendingPathComponent(
                    automation.shortcutName.replacingOccurrences(of: " ", with: "_") + ".shortcut")

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

        try await registry.update(automation)

        try printJSON(automation)
    }

    /// Decodes updated actions, trigger, and conditions from a changes dictionary,
    /// validates them against the device map, and returns the decoded values.
    private func decodeAndValidateChanges(
        _ changesDict: [String: Any],
        automation: RegisteredAutomation
    ) async throws -> (actions: [AutomationAction], trigger: AutomationTrigger, conditions: [AutomationCondition]?) {
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

        return (updatedActions, updatedTrigger, updatedConditions)
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

        guard let automation = try await registry.find(identifier) else {
            throw ValidationError("Automation not found: \(identifier)")
        }

        // Delete the associated Apple Shortcut from macOS
        let shortcutDeleted = await ShortcutGenerator.deleteShortcut(name: automation.shortcutName)

        // Remove automation from registry
        try await registry.delete(automation.id)

        // Return confirmation with Shortcut removal status
        let result: [String: AnyCodableValue] = [
            "deleted": .bool(true),
            "name": .string(automation.name),
            "shortcutRemoved": .bool(shortcutDeleted),
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

    /// When true, simulate execution without sending commands to devices
    @Flag(name: .long, help: "Simulate execution without controlling devices")
    var dryRun = false

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
            guard let automation = try await registry.find(identifier) else {
                throw ValidationError("Automation not found: \(identifier)")
            }
            actionsToTest = automation.actions
            conditionsToCheck = automation.conditions ?? []
        }

        // Evaluate conditions before executing actions
        let conditionEval = try await evaluateConditions(
            conditionsToCheck, using: client, force: force
        )
        if let earlyOutput = conditionEval.earlyExitOutput {
            try printJSON(earlyOutput)
            return
        }

        // Execute actions and build output
        let results = try await executeActions(
            actionsToTest, dryRun: dryRun, using: client
        )

        // Summarize results
        let succeeded = results.filter { $0["success"]?.boolValue == true }.count
        let failed = results.count - succeeded

        var output: [String: AnyCodableValue] = [
            "tested": .string(name ?? id ?? "ad-hoc"),
            "results": .array(results.map { .dictionary($0) }),
            "succeeded": .int(succeeded),
            "failed": .int(failed),
        ]
        if dryRun {
            output["dryRun"] = .bool(true)
        }
        if !conditionEval.results.isEmpty {
            output["conditionsEvaluated"] = .array(conditionEval.results.map { .dictionary($0) })
            output["conditionsMet"] = .bool(conditionEval.allMet)
            if !conditionEval.allMet && force {
                output["forcedExecution"] = .bool(true)
            }
        }

        try printJSON(output)
    }

    /// Evaluates automation conditions, returning results and an optional early-exit output
    /// if conditions are not met and `--force` is not set.
    private func evaluateConditions(
        _ conditions: [AutomationCondition],
        using client: SocketClient,
        force: Bool
    ) async throws -> (
        results: [[String: AnyCodableValue]], allMet: Bool,
        earlyExitOutput: [String: AnyCodableValue]?
    ) {
        guard !conditions.isEmpty else {
            return ([], true, nil)
        }

        var lat = SolarCalculator.default.latitude
        var lon = SolarCalculator.default.longitude
        if let configResponse = try? await client.send(command: "get_config"),
            configResponse.isOk,
            let configData = configResponse.data?.dictionaryValue
        {
            if let userLat = configData["latitude"]?.doubleValue { lat = userLat }
            if let userLon = configData["longitude"]?.doubleValue { lon = userLon }
        }

        let evaluator = ConditionEvaluator(latitude: lat, longitude: lon)
        let evalResult = try await evaluator.evaluate(conditions: conditions, using: client)
        let conditionResults = evalResult.results.map { r in
            [
                "condition": AnyCodableValue.string(r.condition.humanReadable),
                "type": AnyCodableValue.string(r.condition.type),
                "met": AnyCodableValue.bool(r.met),
                "reason": AnyCodableValue.string(r.reason),
            ]
        }

        if !evalResult.allMet && !force {
            let earlyOutput: [String: AnyCodableValue] = [
                "tested": .string(name ?? id ?? "ad-hoc"),
                "conditionsEvaluated": .array(conditionResults.map { .dictionary($0) }),
                "conditionsMet": .bool(false),
                "skipped": .bool(true),
                "reason": .string("Conditions not met. Use --force to execute anyway."),
            ]
            return (conditionResults, false, earlyOutput)
        }

        return (conditionResults, evalResult.allMet, nil)
    }

    /// Executes automation actions sequentially and collects per-action results.
    private func executeActions(
        _ actions: [AutomationAction],
        dryRun: Bool,
        using client: SocketClient
    ) async throws -> [[String: AnyCodableValue]] {
        var results: [[String: AnyCodableValue]] = []
        for action in actions {
            if action.delaySeconds > 0 && !dryRun {
                try await Task.sleep(nanoseconds: UInt64(action.delaySeconds) * 1_000_000_000)
            }
            if dryRun {
                let device = action.type == "scene" ? (action.sceneName ?? "Unknown") : action.deviceName
                let actionDesc = action.type == "scene" ? "trigger scene" : "\(action.characteristic) -> \(action.value)"
                results.append(["device": .string(device), "action": .string(actionDesc), "dryRun": .bool(true), "success": .bool(true)])
                continue
            }
            if action.type == "scene" {
                let sceneName = action.sceneName ?? "Unknown"
                let response = try await client.send(command: "trigger_scene", params: ["name": .string(sceneName)])
                results.append([
                    "device": .string(sceneName), "action": .string("trigger scene"),
                    "success": .bool(response.isOk), "error": response.error.map { .string($0) } ?? .null,
                ])
                continue
            }
            let response = try await client.send(
                command: "set_device",
                params: [
                    "uuid": .string(action.deviceUuid),
                    "characteristic": .string(action.characteristic),
                    "value": action.value,
                ]
            )
            results.append([
                "device": .string(action.deviceName),
                "action": .string("\(action.characteristic) -> \(action.value)"),
                "success": .bool(response.isOk),
                "error": response.error.map { .string($0) } ?? .null,
            ])
        }
        return results
    }
}

// MARK: - Export

/// Exports automations to a JSON file for backup or sharing.
///
/// Writes all (or filtered) automations as a JSON array to the specified file path,
/// or to stdout if `--output` is not provided. The output format matches the internal
/// RegisteredAutomation schema, so it can be re-imported with `automation import`.
///
/// Usage:
///   hka automation export --output ~/backups/automations.json
///   hka automation export --name "Morning Routine" --json
///   hka automation export --id abc-123 --output single.json
struct AutomationExport: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export automations to a JSON file for backup or sharing."
    )

    /// Optional automation ID to export a single automation
    @Option(name: .long, help: "Export a specific automation by ID")
    var id: String?

    /// Optional automation name to export a single automation
    @Option(name: .long, help: "Export a specific automation by name")
    var name: String?

    /// File path to write the export. If omitted, writes to stdout.
    @Option(name: .long, help: "Output file path (defaults to stdout)")
    var output: String?

    /// When true, outputs as formatted JSON (only relevant for stdout)
    @Flag(name: .long, help: "Output as JSON")
    var json = false

    func run() async throws {
        let registry = AutomationRegistry()
        let all = try await registry.loadAll()

        // Filter to specific automation if requested
        let toExport: [RegisteredAutomation]
        if let id = id {
            guard let found = all.first(where: { $0.id == id }) else {
                throw RegistryError.notFound(id)
            }
            toExport = [found]
        } else if let name = name {
            guard let found = all.first(where: { $0.name.lowercased() == name.lowercased() }) else {
                throw RegistryError.notFound(name)
            }
            toExport = [found]
        } else {
            toExport = all
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(toExport)

        if let outputPath = output {
            let url = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
            try data.write(to: url, options: .atomic)
            let result: [String: AnyCodableValue] = [
                "exported": .int(toExport.count),
                "path": .string(url.path),
            ]
            try printJSON(result)
        } else {
            // Write to stdout
            if json {
                let result: [String: AnyCodableValue] = [
                    "exported": .int(toExport.count),
                    "automations": .array(
                        toExport.map { automation in
                            .dictionary([
                                "id": .string(automation.id),
                                "name": .string(automation.name),
                                "description": automation.description.map { .string($0) } ?? .null,
                                "enabled": .bool(automation.enabled),
                                "trigger": .string(automation.trigger.type),
                                "actionsCount": .int(automation.actions.count),
                                "createdAt": .string(automation.createdAt),
                            ])
                        }),
                ]
                try printJSON(result)
            } else {
                print(String(data: data, encoding: .utf8) ?? "")
            }
        }
    }
}

// MARK: - Import

/// Imports automations from a JSON file, adding them to the local registry.
///
/// Reads a JSON array of automations from the specified file path and registers each one.
/// Skips automations that already exist (by name) unless `--force` is specified, in which
/// case existing automations are overwritten.
///
/// Usage:
///   hka automation import --file ~/backups/automations.json
///   hka automation import --file shared.json --force
struct AutomationImport: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import automations from a JSON file."
    )

    /// Path to the JSON file containing automations to import
    @Option(name: .long, help: "Path to the automation JSON file to import")
    var file: String

    /// When true, overwrites existing automations with the same name
    @Flag(name: .long, help: "Overwrite existing automations with the same name")
    var force = false

    /// When true, returns results as formatted JSON
    @Flag(name: .long, help: "Output as JSON")
    var json = false

    func run() async throws {
        let url = URL(fileURLWithPath: (file as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError("File not found: \(file)")
        }

        let data = try Data(contentsOf: url)
        let automations = try JSONDecoder().decode([RegisteredAutomation].self, from: data)

        let registry = AutomationRegistry()
        var imported = 0
        var skipped = 0
        var updated = 0
        var errors: [[String: AnyCodableValue]] = []

        for automation in automations {
            do {
                let existing = try await registry.find(automation.name)
                if let existing = existing {
                    if force {
                        // Update existing automation
                        var toUpdate = automation
                        toUpdate.id = existing.id  // Preserve original ID
                        try await registry.update(toUpdate)
                        updated += 1
                    } else {
                        skipped += 1
                    }
                } else {
                    try await registry.save(automation)
                    imported += 1
                }
            } catch {
                errors.append([
                    "name": .string(automation.name),
                    "error": .string(error.localizedDescription),
                ])
            }
        }

        let result: [String: AnyCodableValue] = [
            "imported": .int(imported),
            "updated": .int(updated),
            "skipped": .int(skipped),
            "errors": .array(errors.map { .dictionary($0) }),
            "total": .int(automations.count),
        ]
        try printJSON(result)
    }
}
