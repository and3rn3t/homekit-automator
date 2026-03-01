// Models.swift
// HomeKitCore — Canonical model types shared by the CLI, HomeKitHelper, and the Xcode app.
//
// All targets import these types via HomeKitCore. The Xcode app maintains a mirrored
// copy in AutomationModels.swift because it cannot import SPM modules directly.
// Keep both files in sync.

import Foundation

// MARK: - Shared Formatters

/// A shared ISO 8601 date formatter for efficient reuse. Thread-safe once created.
nonisolated(unsafe) public let sharedISO8601Formatter = ISO8601DateFormatter()

// MARK: - Automation Definition (Input from LLM)

/// The raw automation definition as constructed by the LLM from the user's natural language request.
/// This is the input format for `automation create`. The engine validates it against the live device
/// map and transforms it into a `RegisteredAutomation` upon successful creation.
public struct AutomationDefinition: Codable, Sendable {
    public let name: String
    public let description: String?
    public let trigger: AutomationTrigger
    public let conditions: [AutomationCondition]?
    public let actions: [AutomationAction]
    public let enabled: Bool?

    public init(
        name: String, description: String? = nil, trigger: AutomationTrigger,
        conditions: [AutomationCondition]? = nil, actions: [AutomationAction],
        enabled: Bool? = nil
    ) {
        self.name = name
        self.description = description
        self.trigger = trigger
        self.conditions = conditions
        self.actions = actions
        self.enabled = enabled
    }
}

// MARK: - Registered Automation

/// A fully validated and registered automation persisted in the local registry.
public struct RegisteredAutomation: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var description: String?
    public let trigger: AutomationTrigger
    public let conditions: [AutomationCondition]?
    public let actions: [AutomationAction]
    public var enabled: Bool
    public let shortcutName: String
    public let createdAt: String
    public var lastRun: String?

    public init(
        id: String, name: String, description: String? = nil,
        trigger: AutomationTrigger, conditions: [AutomationCondition]? = nil,
        actions: [AutomationAction], enabled: Bool, shortcutName: String,
        createdAt: String, lastRun: String? = nil
    ) {
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

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Trigger

/// Defines when an automation fires.
public struct AutomationTrigger: Codable, Sendable, Hashable {
    public let type: String
    public let humanReadable: String
    public let cron: String?
    public let timezone: String?
    public let event: String?
    public let offsetMinutes: Int?
    public let keyword: String?
    public let deviceUuid: String?
    public let deviceName: String?
    public let characteristic: String?
    public let `operator`: String?
    public let value: AnyCodableValue?

    public init(
        type: String, humanReadable: String,
        cron: String? = nil, timezone: String? = nil,
        event: String? = nil, offsetMinutes: Int? = nil,
        keyword: String? = nil,
        deviceUuid: String? = nil, deviceName: String? = nil,
        characteristic: String? = nil, operator: String? = nil,
        value: AnyCodableValue? = nil
    ) {
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

/// Optional guard that must evaluate to true for an automation to execute.
public struct AutomationCondition: Codable, Sendable, Hashable {
    public let type: String
    public let humanReadable: String
    public let after: String?
    public let before: String?
    public let days: [Int]?
    public let deviceUuid: String?
    public let deviceName: String?
    public let characteristic: String?
    public let `operator`: String?
    public let value: AnyCodableValue?
    public let requirement: String?

    public init(
        type: String, humanReadable: String,
        after: String? = nil, before: String? = nil,
        days: [Int]? = nil,
        deviceUuid: String? = nil, deviceName: String? = nil,
        characteristic: String? = nil, operator: String? = nil,
        value: AnyCodableValue? = nil,
        requirement: String? = nil
    ) {
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

/// A single device control action within an automation.
public struct AutomationAction: Codable, Sendable, Hashable {
    public let type: String?
    public let deviceUuid: String
    public let deviceName: String
    public let room: String?
    public let characteristic: String
    public let value: AnyCodableValue
    public let delaySeconds: Int
    public let sceneName: String?
    public let sceneUuid: String?

    public init(
        type: String? = nil,
        deviceUuid: String = "",
        deviceName: String = "",
        room: String? = nil,
        characteristic: String = "",
        value: AnyCodableValue = .null,
        delaySeconds: Int = 0,
        sceneName: String? = nil,
        sceneUuid: String? = nil
    ) {
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

/// A suggested automation generated by the HomeAnalyzer based on the user's device map.
public struct AutomationSuggestion: Codable, Sendable {
    public let name: String
    public let reason: String
    public let trigger: String
    public let actions: [String]
    public let category: String

    public init(name: String, reason: String, trigger: String, actions: [String], category: String)
    {
        self.name = name
        self.reason = reason
        self.trigger = trigger
        self.actions = actions
        self.category = category
    }
}

// MARK: - Log Entry

/// Records a single execution of an automation.
public struct AutomationLogEntry: Codable, Identifiable, Sendable {
    public let automationId: String
    public let automationName: String
    public let timestamp: String
    public let actionsExecuted: Int
    public let succeeded: Int
    public let failed: Int
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

    public init(
        automationId: String, automationName: String, timestamp: String,
        actionsExecuted: Int, succeeded: Int, failed: Int, errors: [String]? = nil
    ) {
        self.automationId = automationId
        self.automationName = automationName
        self.timestamp = timestamp
        self.actionsExecuted = actionsExecuted
        self.succeeded = succeeded
        self.failed = failed
        self.errors = errors
    }
}
