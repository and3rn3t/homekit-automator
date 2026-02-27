// Models.swift
// HomeKitCore — Canonical data models for automations, triggers, conditions, and actions.
//
// This is the single source of truth for all shared HomeKit Automator model types.
// All targets (CLI, Helper, GUI) should use or mirror this file. Do not create independent copies.
//
// These models define the JSON schema that flows between the LLM (via SKILL.md guidance),
// the MCP server, the CLI tool, and the automation registry on disk. All models conform
// to Codable for JSON serialization over the Unix socket protocol and for persistence
// in the automation registry file at ~/Library/Application Support/homekit-automator/automations.json.
//
// Data flow:
//   LLM parses user intent → AutomationDefinition (JSON) → CLI validates → RegisteredAutomation (saved)
//   RegisteredAutomation → ShortcutGenerator → .shortcut file → Apple Shortcuts app

import Foundation

// MARK: - Shared Formatters

/// A shared ISO 8601 date formatter for efficient reuse across the codebase.
///
/// `ISO8601DateFormatter` is expensive to create but thread-safe once initialized.
/// Use this shared instance instead of allocating a new formatter in loops or
/// computed properties.
///
/// Marked `nonisolated(unsafe)` because ISO8601DateFormatter is thread-safe for
/// formatting/parsing when its options are not mutated after creation.
public nonisolated(unsafe) let sharedISO8601Formatter = ISO8601DateFormatter()

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
public struct AutomationDefinition: Codable, Sendable {
    public let name: String
    public let description: String?
    public let trigger: AutomationTrigger
    public let conditions: [AutomationCondition]?
    public let actions: [AutomationAction]
    public let enabled: Bool?

    public init(name: String, description: String? = nil, trigger: AutomationTrigger,
                conditions: [AutomationCondition]? = nil, actions: [AutomationAction],
                enabled: Bool? = nil) {
        self.name = name
        self.description = description
        self.trigger = trigger
        self.conditions = conditions
        self.actions = actions
        self.enabled = enabled
    }
}

// MARK: - Registered Automation (Stored in registry)

/// A fully validated and registered automation that has been saved to the local registry
/// and (optionally) imported into Apple Shortcuts. This is the persistent form.
///
/// Key difference from `AutomationDefinition`: includes an `id` (UUID), `shortcutName`
/// (the `HKA:` prefixed name in the Shortcuts app), `createdAt` timestamp, and mutable
/// fields for `enabled` state and `lastRun` tracking.
public struct RegisteredAutomation: Codable, Identifiable, Sendable {
    /// Unique identifier (UUID string), generated at creation time.
    public var id: String
    /// Human-readable name. Must be unique across all automations (maps 1:1 to Shortcut names).
    public var name: String
    /// Optional description of what the automation does.
    public var description: String?
    /// When the automation fires. Immutable after creation (delete and recreate to change trigger type).
    public let trigger: AutomationTrigger
    /// Optional conditions that must all be true for the automation to execute.
    public let conditions: [AutomationCondition]?
    /// Ordered list of device actions to execute when triggered.
    public let actions: [AutomationAction]
    /// Whether the automation is active. Disabled automations remain in the registry but won't be suggested for execution.
    public var enabled: Bool
    /// The name of the corresponding Apple Shortcut (e.g., "HKA: Morning Routine").
    public let shortcutName: String
    /// ISO 8601 timestamp of when the automation was created.
    public let createdAt: String
    /// ISO 8601 timestamp of the most recent execution, or nil if never run.
    public var lastRun: String?

    public init(id: String, name: String, description: String? = nil,
                trigger: AutomationTrigger, conditions: [AutomationCondition]? = nil,
                actions: [AutomationAction], enabled: Bool, shortcutName: String,
                createdAt: String, lastRun: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.trigger = trigger
        self.conditions = conditions
        self.actions = actions
        self.enabled = enabled
        self.shortcutName = shortcutName
        self.createdAt = createdAt
        self.lastRun = lastRun
    }
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
public struct AutomationTrigger: Codable, Sendable {
    /// Trigger type: "schedule", "solar", "manual", or "device_state"
    public let type: String
    /// Human-readable description of the trigger for display to the user.
    public let humanReadable: String

    // -- Schedule trigger fields --
    /// Standard 5-field cron expression: minute hour dayOfMonth month dayOfWeek
    public let cron: String?
    /// IANA timezone identifier (e.g., "America/New_York"). Defaults to system timezone.
    public let timezone: String?

    // -- Solar trigger fields --
    /// Solar event: "sunrise" or "sunset"
    public let event: String?
    /// Minutes offset from the solar event. Negative = before, positive = after, 0 = at the event.
    public let offsetMinutes: Int?

    // -- Manual trigger fields --
    /// Keyword the LLM listens for to trigger this automation (e.g., "bedtime").
    public let keyword: String?

    // -- Device state trigger fields --
    /// UUID of the device whose state to monitor.
    public let deviceUuid: String?
    /// Human-readable name of the monitored device.
    public let deviceName: String?
    /// The characteristic to watch (e.g., "lockState", "motionDetected").
    public let characteristic: String?
    /// Comparison operator: "equals", "notEquals", "greaterThan", "lessThan", "greaterOrEqual", "lessOrEqual"
    public let `operator`: String?
    /// The value to compare against.
    public let value: AnyCodableValue?

    public init(type: String, humanReadable: String,
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
public struct AutomationCondition: Codable, Sendable {
    /// Condition type: "time", "dayOfWeek", "deviceState", or "solar"
    public let type: String
    /// Human-readable description (e.g., "only after dark").
    public let humanReadable: String

    // -- Time condition fields --
    /// Start time in HH:MM format (24-hour). The condition passes if current time is after this.
    public let after: String?
    /// End time in HH:MM format (24-hour). The condition passes if current time is before this.
    public let before: String?

    // -- Day of week condition fields --
    /// Array of day numbers. 0=Sunday, 1=Monday, ..., 6=Saturday.
    public let days: [Int]?

    // -- Device state condition fields --
    /// UUID of the device to check.
    public let deviceUuid: String?
    /// Human-readable device name.
    public let deviceName: String?
    /// Characteristic to check (e.g., "currentTemperature").
    public let characteristic: String?
    /// Comparison operator: "equals", "notEquals", "greaterThan", "lessThan", "greaterOrEqual", "lessOrEqual"
    public let `operator`: String?
    /// Value to compare against.
    public let value: AnyCodableValue?

    // -- Solar condition fields --
    /// Solar requirement: "after_sunset", "before_sunset", "after_sunrise", "before_sunrise"
    public let requirement: String?

    public init(type: String, humanReadable: String,
                after: String? = nil, before: String? = nil,
                days: [Int]? = nil,
                deviceUuid: String? = nil, deviceName: String? = nil,
                characteristic: String? = nil, operator: String? = nil,
                value: AnyCodableValue? = nil,
                requirement: String? = nil) {
        self.type = type
        self.humanReadable = humanReadable
        self.after = after
        self.before = before
        self.days = days
        self.deviceUuid = deviceUuid
        self.deviceName = deviceName
        self.characteristic = characteristic
        self.operator = `operator`
        self.value = value
        self.requirement = requirement
    }
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
public struct AutomationAction: Codable, Sendable {
    /// Action type: nil or absent for device control, "scene" for triggering an Apple Home scene.
    public let type: String?
    /// UUID of the target device (from HomeKit discovery). Empty string for scene actions.
    public let deviceUuid: String
    /// Human-readable device name. Used for display and error messages.
    public let deviceName: String
    /// Room the device belongs to. Optional, used for context in summaries.
    public let room: String?
    /// The characteristic to set (e.g., "power", "brightness", "targetTemperature"). Empty for scene actions.
    public let characteristic: String
    /// The target value. Type varies by characteristic: Bool for power/locks, Int for brightness, Float for temperature.
    public let value: AnyCodableValue
    /// Seconds to wait before executing this action. 0 for immediate. Max 3600 (1 hour).
    public let delaySeconds: Int
    /// Name of the scene to trigger (only when `type` is "scene").
    public let sceneName: String?
    /// UUID of the scene to trigger (only when `type` is "scene").
    public let sceneUuid: String?

    public init(type: String? = nil,
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
public struct AutomationSuggestion: Codable, Sendable {
    /// Suggested automation name (e.g., "Auto-lock at Night").
    public let name: String
    /// Why this suggestion is relevant (e.g., "You have 2 smart locks but no nighttime locking automation").
    public let reason: String
    /// When it would trigger (e.g., "daily at 10:00 PM").
    public let trigger: String
    /// Human-readable action descriptions (e.g., ["Front Door Lock -> locked"]).
    public let actions: [String]
    /// Focus category: "security", "comfort", "convenience", or "energy".
    public let category: String

    public init(name: String, reason: String, trigger: String, actions: [String], category: String) {
        self.name = name
        self.reason = reason
        self.trigger = trigger
        self.actions = actions
        self.category = category
    }
}

// MARK: - Automation Log Entry

/// Records a single execution of an automation. Stored in `~/Library/Application Support/homekit-automator/logs/automation-log.json`.
/// The log is capped at 1000 entries (oldest entries are pruned). Used by the energy summary
/// tool to report automation activity over time.
public struct AutomationLogEntry: Codable, Identifiable, Sendable {
    /// ID of the automation that was executed.
    public let automationId: String
    /// Name of the automation (denormalized for readability in logs).
    public let automationName: String
    /// ISO 8601 timestamp of execution.
    public let timestamp: String
    /// Total number of actions attempted.
    public let actionsExecuted: Int
    /// Number of actions that completed successfully.
    public let succeeded: Int
    /// Number of actions that failed.
    public let failed: Int
    /// Error messages from failed actions, if any.
    public let errors: [String]?

    /// Synthesized identifier for SwiftUI list usage.
    public var id: String { "\(automationId)-\(timestamp)" }

    /// Parsed date from the ISO 8601 timestamp.
    public var date: Date? {
        sharedISO8601Formatter.date(from: timestamp)
    }

    /// Whether all actions succeeded.
    public var isSuccess: Bool {
        failed == 0
    }

    /// Success rate as a percentage (0–100).
    public var successRate: Double {
        guard actionsExecuted > 0 else { return 100.0 }
        return Double(succeeded) / Double(actionsExecuted) * 100.0
    }

    public init(automationId: String, automationName: String, timestamp: String,
                actionsExecuted: Int, succeeded: Int, failed: Int, errors: [String]? = nil) {
        self.automationId = automationId
        self.automationName = automationName
        self.timestamp = timestamp
        self.actionsExecuted = actionsExecuted
        self.succeeded = succeeded
        self.failed = failed
        self.errors = errors
    }
}
