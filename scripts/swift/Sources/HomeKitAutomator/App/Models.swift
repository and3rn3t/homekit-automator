// Models.swift
// HomeKitAutomator — This file should match HomeKitCore/Models.swift and
// HomeKitCore/AnyCodableValue.swift — do not edit independently.
//
// This is a copy of the canonical models from Sources/HomeKitCore/.
// HomeKitAutomator is built via Xcode/XcodeGen and cannot import the SPM HomeKitCore
// module directly. Keep this file in sync with the canonical versions.

import Foundation

// MARK: - Registered Automation

/// A fully validated and registered automation persisted in the local registry.
struct RegisteredAutomation: Codable, Identifiable {
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
}

// MARK: - Trigger

/// Defines when an automation fires.
struct AutomationTrigger: Codable {
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
struct AutomationCondition: Codable {
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
}

// MARK: - Action

/// A single device control action within an automation.
struct AutomationAction: Codable {
    let type: String?
    let deviceUuid: String
    let deviceName: String
    let room: String?
    let characteristic: String
    let value: AnyCodableValue
    let delaySeconds: Int
    let sceneName: String?
    let sceneUuid: String?

    /// Convenience accessor for the value in its Codable form.
    var codableValue: AnyCodableValue { value }
}

// MARK: - Log Entry

/// Records a single execution of an automation.
struct AutomationLogEntry: Codable, Identifiable {
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
        ISO8601DateFormatter().date(from: timestamp)
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
        } else if let val = try? container.decode(Bool.self) {
            self = .bool(val)
        } else if let val = try? container.decode(Int.self) {
            self = .int(val)
        } else if let val = try? container.decode(Double.self) {
            self = .double(val)
        } else if let val = try? container.decode(String.self) {
            self = .string(val)
        } else if let val = try? container.decode([AnyCodableValue].self) {
            self = .array(val)
        } else if let val = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(val)
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
        case .string(let val): try container.encode(val)
        case .int(let val): try container.encode(val)
        case .double(let val): try container.encode(val)
        case .bool(let val): try container.encode(val)
        case .null: try container.encodeNil()
        case .array(let val): try container.encode(val)
        case .dictionary(let val): try container.encode(val)
        }
    }
}
