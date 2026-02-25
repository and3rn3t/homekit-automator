// Models.swift
// Core data models for automations, triggers, conditions, and actions.
//
// These models define the JSON schema that flows between the LLM (via SKILL.md guidance),
// the MCP server, the CLI tool, and the automation registry on disk. All models conform
// to Codable for JSON serialization over the Unix socket protocol and for persistence
// in the automation registry file at ~/.config/homekit-automator/automations.json.
//
// Data flow:
//   LLM parses user intent → AutomationDefinition (JSON) → CLI validates → RegisteredAutomation (saved)
//   RegisteredAutomation → ShortcutGenerator → .shortcut file → Apple Shortcuts app

import Foundation

// MARK: - Automation Definition (Input from LLM)

/// The raw automation definition as constructed by the LLM from the user's natural language request.
/// This is the input format for `automation create`. The engine validates it against the live device
/// map and transforms it into a `RegisteredAutomation` upon successful creation.
///
/// Example JSON:
/// ```json
/// {
///   "name": "Morning Routine",
///   "trigger": { "type": "schedule", "cron": "0 7 * * 1-5", "humanReadable": "weekdays at 7 AM" },
///   "actions": [{ "deviceUuid": "abc", "deviceName": "Lights", "characteristic": "power", "value": true, "delaySeconds": 0 }]
/// }
/// ```
struct AutomationDefinition: Codable {
    let name: String
    let description: String?
    let trigger: AutomationTrigger
    let conditions: [AutomationCondition]?
    let actions: [AutomationAction]
    let enabled: Bool?
}

// MARK: - Registered Automation (Stored in registry)

/// A fully validated and registered automation that has been saved to the local registry
/// and (optionally) imported into Apple Shortcuts. This is the persistent form.
///
/// Key difference from `AutomationDefinition`: includes an `id` (UUID), `shortcutName`
/// (the `HKA:` prefixed name in the Shortcuts app), `createdAt` timestamp, and mutable
/// fields for `enabled` state and `lastRun` tracking.
struct RegisteredAutomation: Codable {
    /// Unique identifier (UUID string), generated at creation time.
    var id: String
    /// Human-readable name. Must be unique across all automations (maps 1:1 to Shortcut names).
    var name: String
    /// Optional description of what the automation does.
    var description: String?
    /// When the automation fires. Immutable after creation (delete and recreate to change trigger type).
    let trigger: AutomationTrigger
    /// Optional conditions that must all be true for the automation to execute.
    let conditions: [AutomationCondition]?
    /// Ordered list of device actions to execute when triggered.
    let actions: [AutomationAction]
    /// Whether the automation is active. Disabled automations remain in the registry but won't be suggested for execution.
    var enabled: Bool
    /// The name of the corresponding Apple Shortcut (e.g., "HKA: Morning Routine").
    let shortcutName: String
    /// ISO 8601 timestamp of when the automation was created.
    let createdAt: String
    /// ISO 8601 timestamp of the most recent execution, or nil if never run.
    var lastRun: String?
}

// MARK: - Trigger

/// Defines when an automation fires. Exactly one trigger per automation.
///
/// The `type` field determines which other fields are relevant:
/// - `"schedule"`: Uses `cron` and `timezone` (5-field cron expression)
/// - `"solar"`: Uses `event` ("sunrise"/"sunset") and `offsetMinutes`
/// - `"manual"`: Uses `keyword` (the LLM matches this from conversation)
/// - `"device_state"`: Uses `deviceUuid`, `characteristic`, `operator`, `value`
///
/// The `humanReadable` field is always present and used for display purposes
/// (e.g., "weekdays at 6:45 AM", "30 minutes before sunset").
struct AutomationTrigger: Codable {
    /// Trigger type: "schedule", "solar", "manual", or "device_state"
    let type: String
    /// Human-readable description of the trigger for display to the user.
    let humanReadable: String

    // -- Schedule trigger fields --
    /// Standard 5-field cron expression: minute hour dayOfMonth month dayOfWeek
    let cron: String?
    /// IANA timezone identifier (e.g., "America/New_York"). Defaults to system timezone.
    let timezone: String?

    // -- Solar trigger fields --
    /// Solar event: "sunrise" or "sunset"
    let event: String?
    /// Minutes offset from the solar event. Negative = before, positive = after, 0 = at the event.
    let offsetMinutes: Int?

    // -- Manual trigger fields --
    /// Keyword the LLM listens for to trigger this automation (e.g., "bedtime").
    let keyword: String?

    // -- Device state trigger fields --
    /// UUID of the device whose state to monitor.
    let deviceUuid: String?
    /// Human-readable name of the monitored device.
    let deviceName: String?
    /// The characteristic to watch (e.g., "lockState", "motionDetected").
    let characteristic: String?
    /// Comparison operator: "equals", "notEquals", "greaterThan", "lessThan", "greaterOrEqual", "lessOrEqual"
    let `operator`: String?
    /// The value to compare against.
    let value: AnyCodableValue?

    init(type: String, humanReadable: String,
         cron: String? = nil, timezone: String? = nil,
         event: String? = nil, offsetMinutes: Int? = nil,
         keyword: String? = nil,
         deviceUuid: String? = nil, deviceName: String? = nil,
         characteristic: String? = nil, operator: String? = nil,
         value: AnyCodableValue? = nil) {
        self.type = type
        self.humanReadable = humanReadable
        self.cron = cron
        self.timezone = timezone
        self.event = event
        self.offsetMinutes = offsetMinutes
        self.keyword = keyword
        self.deviceUuid = deviceUuid
        self.deviceName = deviceName
        self.characteristic = characteristic
        self.operator = `operator`
        self.value = value
    }
}

// MARK: - Condition

/// Optional guard that must evaluate to `true` for an automation to execute.
/// Multiple conditions are ANDed together — all must pass.
///
/// The `type` field determines which fields are relevant:
/// - `"time"`: Uses `after` and `before` (HH:MM format)
/// - `"dayOfWeek"`: Uses `days` array (0=Sunday through 6=Saturday)
/// - `"deviceState"`: Uses `deviceUuid`, `characteristic`, `operator`, `value`
/// - `"solar"`: Uses `requirement` ("after_sunset", "before_sunrise", etc.)
struct AutomationCondition: Codable {
    /// Condition type: "time", "dayOfWeek", "deviceState", or "solar"
    let type: String
    /// Human-readable description (e.g., "only after dark").
    let humanReadable: String

    // -- Time condition fields --
    /// Start time in HH:MM format (24-hour). The condition passes if current time is after this.
    let after: String?
    /// End time in HH:MM format (24-hour). The condition passes if current time is before this.
    let before: String?

    // -- Day of week condition fields --
    /// Array of day numbers. 0=Sunday, 1=Monday, ..., 6=Saturday.
    let days: [Int]?

    // -- Device state condition fields --
    /// UUID of the device to check.
    let deviceUuid: String?
    /// Human-readable device name.
    let deviceName: String?
    /// Characteristic to check (e.g., "currentTemperature").
    let characteristic: String?
    /// Comparison operator: "equals", "notEquals", "greaterThan", "lessThan", "greaterOrEqual", "lessOrEqual"
    let `operator`: String?
    /// Value to compare against.
    let value: AnyCodableValue?

    // -- Solar condition fields --
    /// Solar requirement: "after_sunset", "before_sunset", "after_sunrise", "before_sunrise"
    let requirement: String?
}

// MARK: - Action

/// A single device control action within an automation. Actions are executed in order.
///
/// For regular device actions, provide `deviceUuid`, `deviceName`, `characteristic`, and `value`.
/// For scene triggers, set `type` to `"scene"` and provide `sceneName` and `sceneUuid`.
/// The `delaySeconds` field introduces a pause before this action executes (0 for immediate).
///
/// Example: Turn on kitchen lights after a 5-second delay:
/// ```json
/// { "deviceUuid": "abc", "deviceName": "Kitchen Lights", "characteristic": "power", "value": true, "delaySeconds": 5 }
/// ```
struct AutomationAction: Codable {
    /// Action type: nil or absent for device control, "scene" for triggering an Apple Home scene.
    let type: String?
    /// UUID of the target device (from HomeKit discovery). Empty string for scene actions.
    let deviceUuid: String
    /// Human-readable device name. Used for display and error messages.
    let deviceName: String
    /// Room the device belongs to. Optional, used for context in summaries.
    let room: String?
    /// The characteristic to set (e.g., "power", "brightness", "targetTemperature"). Empty for scene actions.
    let characteristic: String
    /// The target value. Type varies by characteristic: Bool for power/locks, Int for brightness, Float for temperature.
    let value: AnyCodableValue
    /// Seconds to wait before executing this action. 0 for immediate. Max 3600 (1 hour).
    let delaySeconds: Int
    /// Name of the scene to trigger (only when `type` is "scene").
    let sceneName: String?
    /// UUID of the scene to trigger (only when `type` is "scene").
    let sceneUuid: String?

    /// Convenience accessor for the value in its Codable form (identity — value is already AnyCodableValue).
    var codableValue: AnyCodableValue { value }

    init(type: String? = nil,
         deviceUuid: String = "",
         deviceName: String = "",
         room: String? = nil,
         characteristic: String = "",
         value: AnyCodableValue = .null,
         delaySeconds: Int = 0,
         sceneName: String? = nil,
         sceneUuid: String? = nil) {
        self.type = type
        self.deviceUuid = deviceUuid
        self.deviceName = deviceName
        self.room = room
        self.characteristic = characteristic
        self.value = value
        self.delaySeconds = delaySeconds
        self.sceneName = sceneName
        self.sceneUuid = sceneUuid
    }
}

// MARK: - Suggestion

/// A suggested automation generated by the HomeAnalyzer based on the user's device map
/// and existing automations. Suggestions identify gaps — useful automations the user
/// hasn't created yet — and provide a human-readable explanation of why they'd be helpful.
struct AutomationSuggestion: Codable {
    /// Suggested automation name (e.g., "Auto-lock at Night").
    let name: String
    /// Why this suggestion is relevant (e.g., "You have 2 smart locks but no nighttime locking automation").
    let reason: String
    /// When it would trigger (e.g., "daily at 10:00 PM").
    let trigger: String
    /// Human-readable action descriptions (e.g., ["Front Door Lock -> locked"]).
    let actions: [String]
    /// Focus category: "security", "comfort", "convenience", or "energy".
    let category: String
}

// MARK: - Automation Log Entry

/// Records a single execution of an automation. Stored in `~/.config/homekit-automator/logs/automation-log.json`.
/// The log is capped at 1000 entries (oldest entries are pruned). Used by the energy summary
/// tool to report automation activity over time.
struct AutomationLogEntry: Codable {
    /// ID of the automation that was executed.
    let automationId: String
    /// Name of the automation (denormalized for readability in logs).
    let automationName: String
    /// ISO 8601 timestamp of execution.
    let timestamp: String
    /// Total number of actions attempted.
    let actionsExecuted: Int
    /// Number of actions that completed successfully.
    let succeeded: Int
    /// Number of actions that failed.
    let failed: Int
    /// Error messages from failed actions, if any.
    let errors: [String]?
}
