// AutomationModels.swift
// HomeKitAutomator — This file should match HomeKitCore/Models.swift and
// HomeKitCore/AnyCodableValue.swift — do not edit independently.
//
// This is a copy of the canonical models from Sources/HomeKitCore/.
// HomeKitAutomator is built via Xcode/XcodeGen and cannot import the SPM HomeKitCore
// module directly. Keep this file in sync with the canonical versions.
//
// ⚠️ IMPORTANT: This file was renamed from Models.swift to AutomationModels.swift
// to avoid conflicts with the Swift Package Manager's HomeKitCore/Models.swift

import Foundation

// MARK: - Shared Formatters

/// A shared ISO 8601 date formatter for efficient reuse. Thread-safe once created.
nonisolated(unsafe) let sharedISO8601Formatter = ISO8601DateFormatter()

// MARK: - Automation Definition (Input from LLM)

/// The raw automation definition as constructed by the LLM from the user's natural language request.
/// This is the input format for `automation create`. The engine validates it against the live device
/// map and transforms it into a `RegisteredAutomation` upon successful creation.
struct AutomationDefinition: Codable, Sendable {
    let name: String
    let description: String?
    let trigger: AutomationTrigger
    let conditions: [AutomationCondition]?
    let actions: [AutomationAction]
    let enabled: Bool?

    init(name: String, description: String? = nil, trigger: AutomationTrigger,
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

// MARK: - Registered Automation

/// A fully validated and registered automation persisted in the local registry.
struct RegisteredAutomation: Codable, Identifiable, Sendable {
    var id: String
    var name: String
    var description: String?
    let trigger: AutomationTrigger
    let conditions: [AutomationCondition]?
    let actions: [AutomationAction]
    var enabled: Bool
    let shortcutName: String
    let createdAt: String
    var lastRun: String?

    init(id: String, name: String, description: String? = nil,
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

/// Defines when an automation fires.
struct AutomationTrigger: Codable, Sendable {
    let type: String
    let humanReadable: String
    let cron: String?
    let timezone: String?
    let event: String?
    let offsetMinutes: Int?
    let keyword: String?
    let deviceUuid: String?
    let deviceName: String?
    let characteristic: String?
    let `operator`: String?
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

/// Optional guard that must evaluate to true for an automation to execute.
struct AutomationCondition: Codable, Sendable {
    let type: String
    let humanReadable: String
    let after: String?
    let before: String?
    let days: [Int]?
    let deviceUuid: String?
    let deviceName: String?
    let characteristic: String?
    let `operator`: String?
    let value: AnyCodableValue?
    let requirement: String?

    init(type: String, humanReadable: String,
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

/// A single device control action within an automation.
struct AutomationAction: Codable, Sendable {
    let type: String?
    let deviceUuid: String
    let deviceName: String
    let room: String?
    let characteristic: String
    let value: AnyCodableValue
    let delaySeconds: Int
    let sceneName: String?
    let sceneUuid: String?

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

/// A suggested automation generated by the HomeAnalyzer based on the user's device map.
struct AutomationSuggestion: Codable, Sendable {
    let name: String
    let reason: String
    let trigger: String
    let actions: [String]
    let category: String

    init(name: String, reason: String, trigger: String, actions: [String], category: String) {
        self.name = name
        self.reason = reason
        self.trigger = trigger
        self.actions = actions
        self.category = category
    }
}

// MARK: - Log Entry

/// Records a single execution of an automation.
struct AutomationLogEntry: Codable, Identifiable, Sendable {
    let automationId: String
    let automationName: String
    let timestamp: String
    let actionsExecuted: Int
    let succeeded: Int
    let failed: Int
    let errors: [String]?

    /// Synthesized identifier for SwiftUI list usage.
    var id: String { "\(automationId)-\(timestamp)" }

    /// Parsed date from the ISO 8601 timestamp.
    var date: Date? {
        sharedISO8601Formatter.date(from: timestamp)
    }

    /// Whether all actions succeeded.
    var isSuccess: Bool {
        failed == 0
    }

    /// Success rate as a percentage (0–100).
    var successRate: Double {
        guard actionsExecuted > 0 else { return 100.0 }
        return Double(succeeded) / Double(actionsExecuted) * 100.0
    }

    init(automationId: String, automationName: String, timestamp: String,
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

// MARK: - AnyCodableValue

/// A type-erased Codable value supporting JSON primitives.
/// This should match the canonical version in HomeKitCore/AnyCodableValue.swift.
enum AnyCodableValue: Codable, Equatable, Sendable, CustomStringConvertible {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null

    // MARK: - CustomStringConvertible

    var description: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return "\(i)"
        case .double(let d): return "\(d)"
        case .bool(let b): return "\(b)"
        case .array(let a): return "\(a)"
        case .dictionary(let d): return "\(d)"
        case .null: return "null"
        }
    }

    // MARK: - Display String

    /// Returns a human-readable string representation of the value.
    var displayString: String {
        switch self {
        case .string(let val): return val
        case .int(let val): return "\(val)"
        case .double(let val): return String(format: "%.1f", val)
        case .bool(let val): return val ? "true" : "false"
        case .null: return "null"
        case .array(let val): return "[\(val.map(\.displayString).joined(separator: ", "))]"
        case .dictionary(let val): return val.map { "\($0.key): \($0.value.displayString)" }.joined(separator: ", ")
        }
    }

    // MARK: - Typed Accessors

    /// Extracts the string value, or returns nil if this value is not a string.
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// Extracts the integer value, or returns nil if this value is not an integer.
    var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }

    /// Extracts the double value, or returns nil if this value is not numeric.
    var doubleValue: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }

    /// Extracts the boolean value, or returns nil if this value is not a boolean.
    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    /// Extracts the array value, or returns nil if this value is not an array.
    var arrayValue: [AnyCodableValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    /// Extracts the dictionary value, or returns nil if this value is not a dictionary.
    var dictionaryValue: [String: AnyCodableValue]? {
        if case .dictionary(let d) = self { return d }
        return nil
    }

    // MARK: - Raw Value

    /// Extracts the underlying Swift value (not AnyCodableValue).
    /// Useful for passing to HomeKit characteristic writers that expect Any type.
    var rawValue: Any {
        switch self {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .array(let a): return a.map { $0.rawValue }
        case .dictionary(let d): return d.mapValues { $0.rawValue }
        case .null: return NSNull()
        }
    }

    // MARK: - Codable

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([AnyCodableValue].self) {
            self = .array(a)
        } else if let d = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(d)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode AnyCodableValue"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .array(let a): try container.encode(a)
        case .dictionary(let d): try container.encode(d)
        case .null: try container.encodeNil()
        }
    }
}
