/// AutomationValidator.swift
/// Validation pipeline for automation creation and editing.
///
/// Validates device existence, characteristic support/writability, value ranges,
/// and cron expressions before an automation is persisted to the registry.

import Foundation

/// Validates automation definitions against the live device map and known HomeKit constraints.
///
/// The validator performs four categories of checks:
/// 1. **Device existence** — ensures every referenced device exists in the discovered device map
/// 2. **Characteristic support** — ensures the device category supports the target characteristic and it is writable
/// 3. **Value range** — ensures numeric values fall within the characteristic's valid range
/// 4. **Cron expression** — ensures schedule triggers use valid 5-field cron syntax
struct AutomationValidator {

    // MARK: - Validation Errors

    /// Errors thrown during automation validation.
    enum AutomationValidationError: LocalizedError {
        case deviceNotFound(name: String, suggestion: String?)
        case readOnlyCharacteristic(characteristic: String, deviceName: String)
        case unsupportedCharacteristic(
            characteristic: String, category: String, supported: [String])
        case valueOutOfRange(characteristic: String, value: String, validRange: String)
        case invalidValueType(characteristic: String, expected: String, got: String)
        case invalidCronExpression(reason: String)
        case emptyActions
        case invalidDelaySeconds(Int)

        var errorDescription: String? {
            switch self {
            case .deviceNotFound(let name, let suggestion):
                var msg = "Device not found: \"\(name)\"."
                if let suggestion = suggestion {
                    msg += " Did you mean \"\(suggestion)\"?"
                }
                return msg
            case .readOnlyCharacteristic(let characteristic, let deviceName):
                return
                    "Cannot set \"\(characteristic)\" on \"\(deviceName)\" — it is a read-only characteristic."
            case .unsupportedCharacteristic(let characteristic, let category, let supported):
                return
                    "Characteristic \"\(characteristic)\" is not supported by category \"\(category)\". "
                    + "Supported: \(supported.joined(separator: ", "))."
            case .valueOutOfRange(let characteristic, let value, let validRange):
                return
                    "Value \(value) is out of range for \"\(characteristic)\". Valid range: \(validRange)."
            case .invalidValueType(let characteristic, let expected, let got):
                return
                    "Invalid value type for \"\(characteristic)\": expected \(expected), got \(got)."
            case .invalidCronExpression(let reason):
                return "Invalid cron expression: \(reason)."
            case .emptyActions:
                return "Automation must have at least one action."
            case .invalidDelaySeconds(let seconds):
                return "Invalid delay \(seconds)s — must be between 0 and 3600."
            }
        }
    }

    // MARK: - Known Device Categories & Characteristics

    /// Maps device categories to their supported writable characteristics.
    /// Derived from references/device-categories.md.
    static let categoryCharacteristics: [String: [String]] = [
        "light": ["power", "brightness", "hue", "saturation", "colorTemperature"],
        "thermostat": ["targetTemperature", "hvacMode", "targetHumidity"],
        "lock": ["lockState"],
        "door": ["targetPosition"],
        "garageDoor": ["targetPosition"],
        "fan": ["active", "rotationSpeed", "rotationDirection", "swingMode"],
        "windowCovering": ["targetPosition"],
        "switch": ["power"],
        "outlet": ["power"],
        "sensor": [],  // sensors are all read-only
    ]

    /// All read-only characteristics. Attempting to write to any of these is an error.
    static let readOnlyCharacteristics: Swift.Set<String> = [
        "currentTemperature",
        "currentHumidity",
        "currentHeatingCoolingState",
        "currentLockState",
        "currentPosition",
        "positionState",
        "obstructionDetected",
        "outletInUse",
        "motionDetected",
        "contactState",
        "lightLevel",
        "batteryLevel",
    ]

    // MARK: - PR5: Device Existence Validation

    /// Validates that a device with the given name exists in the device map.
    ///
    /// Performs case-insensitive matching. If no exact match is found, computes Levenshtein
    /// distance against all device names and includes the closest match in the error message.
    ///
    /// - Parameters:
    ///   - deviceName: The device name referenced in the automation action.
    ///   - deviceMap: Array of device dictionaries from the discovery response.
    /// - Throws: `AutomationValidationError.deviceNotFound` if no match is found.
    func validateDeviceExists(deviceName: String, deviceMap: [[String: AnyCodableValue]]) throws {
        let lowered = deviceName.lowercased()
        let found = deviceMap.contains { device in
            guard let name = device["name"]?.stringValue else { return false }
            return name.lowercased() == lowered
        }

        if !found {
            // Find closest match using Levenshtein distance
            let allNames = deviceMap.compactMap { $0["name"]?.stringValue }
            let suggestion = closestMatch(to: deviceName, in: allNames)
            throw AutomationValidationError.deviceNotFound(name: deviceName, suggestion: suggestion)
        }
    }

    /// Finds the device info dictionary for a device by name (case-insensitive).
    ///
    /// - Parameters:
    ///   - deviceName: The device name to look up.
    ///   - deviceMap: Array of device dictionaries from discovery.
    /// - Returns: The matching device dictionary, or nil if not found.
    func findDevice(named deviceName: String, in deviceMap: [[String: AnyCodableValue]]) -> [String:
        AnyCodableValue]?
    {
        let lowered = deviceName.lowercased()
        return deviceMap.first { device in
            guard let name = device["name"]?.stringValue else { return false }
            return name.lowercased() == lowered
        }
    }

    /// Finds the closest string match using Levenshtein distance.
    ///
    /// - Parameters:
    ///   - target: The string to match against.
    ///   - candidates: Array of candidate strings.
    /// - Returns: The closest match, or nil if candidates is empty.
    func closestMatch(to target: String, in candidates: [String]) -> String? {
        guard !candidates.isEmpty else { return nil }
        let loweredTarget = target.lowercased()
        var bestMatch: String?
        var bestDistance = Int.max

        for candidate in candidates {
            let dist = levenshteinDistance(loweredTarget, candidate.lowercased())
            if dist < bestDistance {
                bestDistance = dist
                bestMatch = candidate
            }
        }
        return bestMatch
    }

    /// Computes the Levenshtein (edit) distance between two strings.
    ///
    /// The Levenshtein distance is the minimum number of single-character insertions,
    /// deletions, or substitutions required to transform one string into the other.
    ///
    /// - Parameters:
    ///   - a: First string.
    ///   - b: Second string.
    /// - Returns: The edit distance between the two strings.
    func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count

        if m == 0 { return n }
        if n == 0 { return m }

        // Use two-row optimization for O(min(m,n)) space
        var previousRow = Array(0...n)
        var currentRow = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            currentRow[0] = i
            for j in 1...n {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                currentRow[j] = min(
                    previousRow[j] + 1,  // deletion
                    currentRow[j - 1] + 1,  // insertion
                    previousRow[j - 1] + cost  // substitution
                )
            }
            swap(&previousRow, &currentRow)
        }

        return previousRow[n]
    }

    // MARK: - PR6: Characteristic Support & Writability Validation

    /// Validates that a characteristic is supported by the device and is writable.
    ///
    /// Checks two things:
    /// 1. The characteristic is not in the read-only list.
    /// 2. The device's category supports the characteristic (if category is known).
    ///
    /// - Parameters:
    ///   - characteristic: The characteristic to validate (e.g., "brightness", "power").
    ///   - deviceName: The device name (for error messages).
    ///   - deviceInfo: The device dictionary from discovery, expected to contain a "category" key.
    /// - Throws: `AutomationValidationError.readOnlyCharacteristic` or `.unsupportedCharacteristic`.
    func validateCharacteristic(
        characteristic: String, deviceName: String, deviceInfo: [String: AnyCodableValue]
    ) throws {
        // Check read-only
        if Self.readOnlyCharacteristics.contains(characteristic) {
            throw AutomationValidationError.readOnlyCharacteristic(
                characteristic: characteristic,
                deviceName: deviceName
            )
        }

        // Check category support
        if let categoryValue = deviceInfo["category"]?.stringValue {
            let category = categoryValue.lowercased()
            if let supported = Self.categoryCharacteristics[category] {
                if !supported.contains(characteristic) {
                    throw AutomationValidationError.unsupportedCharacteristic(
                        characteristic: characteristic,
                        category: categoryValue,
                        supported: supported
                    )
                }
            }
            // If category is not in our map, allow it (unknown category — don't block)
        }
    }

    // MARK: - PR7: Value Range Validation

    /// Defines the validation specification for a characteristic's value.
    private enum ValueSpec {
        /// Boolean value, also accepts 0/1 as integers
        case boolean
        /// Integer within a closed range
        case intRange(min: Int, max: Int)
        /// Integer within a closed range, also accepts specific string aliases
        case intRangeOrStrings(min: Int, max: Int, aliases: [String])
        /// Double (or int coerced to double) within a closed range
        case doubleRange(min: Double, max: Double, unit: String)
        /// Integer 0 or 1, also accepts string aliases and booleans
        case binaryOrStrings(aliases: [String])
    }

    /// Table mapping each characteristic to its validation spec.
    /// Derived from references/device-categories.md.
    private static let valueSpecs: [String: ValueSpec] = [
        "power": .boolean,
        "active": .boolean,
        "brightness": .intRange(min: 0, max: 100),
        "colorTemperature": .intRange(min: 50, max: 400),
        "hue": .doubleRange(min: 0, max: 360, unit: ""),
        "saturation": .doubleRange(min: 0, max: 100, unit: ""),
        "targetTemperature": .doubleRange(min: 10, max: 38, unit: " °C"),
        "targetHumidity": .doubleRange(min: 0, max: 100, unit: ""),
        "rotationSpeed": .doubleRange(min: 0, max: 100, unit: ""),
        "hvacMode": .intRangeOrStrings(min: 0, max: 3, aliases: ["off", "heat", "cool", "auto"]),
        "lockState": .binaryOrStrings(aliases: ["locked", "unlocked", "on", "off"]),
        "targetPosition": .intRangeOrStrings(min: 0, max: 100, aliases: ["open", "closed"]),
        "rotationDirection": .intRange(min: 0, max: 1),
        "swingMode": .intRange(min: 0, max: 1),
    ]

    /// Validates that a value is within the acceptable range for a given characteristic.
    ///
    /// Uses a table-driven approach: each characteristic maps to a `ValueSpec` that defines
    /// the accepted types and ranges. Unknown characteristics are silently allowed to
    /// preserve extensibility.
    ///
    /// - Parameters:
    ///   - characteristic: The characteristic name.
    ///   - value: The value to validate.
    /// - Throws: `AutomationValidationError.valueOutOfRange` or `.invalidValueType`.
    func validateValueRange(characteristic: String, value: AnyCodableValue) throws {
        guard let spec = Self.valueSpecs[characteristic] else {
            // Unknown characteristic — skip range validation (don't block extensibility)
            return
        }

        switch spec {
        case .boolean:
            guard value.boolValue != nil else {
                if let intVal = value.intValue, intVal == 0 || intVal == 1 { return }
                throw AutomationValidationError.invalidValueType(
                    characteristic: characteristic, expected: "boolean",
                    got: describeValueType(value))
            }

        case .intRange(let min, let max):
            guard let intVal = value.intValue else {
                if let d = value.doubleValue, d >= Double(min), d <= Double(max), d == d.rounded() {
                    return
                }
                throw AutomationValidationError.invalidValueType(
                    characteristic: characteristic, expected: "integer (\(min)–\(max))",
                    got: describeValueType(value))
            }
            guard intVal >= min && intVal <= max else {
                throw AutomationValidationError.valueOutOfRange(
                    characteristic: characteristic, value: "\(intVal)", validRange: "\(min)–\(max)")
            }

        case .intRangeOrStrings(let min, let max, let aliases):
            if let intVal = value.intValue {
                guard intVal >= min && intVal <= max else {
                    throw AutomationValidationError.valueOutOfRange(
                        characteristic: characteristic, value: "\(intVal)",
                        validRange: "\(min)–\(max)")
                }
            } else if let str = value.stringValue {
                guard aliases.contains(str.lowercased()) else {
                    throw AutomationValidationError.valueOutOfRange(
                        characteristic: characteristic, value: str,
                        validRange: "\(min)–\(max) or \(aliases.joined(separator: "/"))")
                }
            } else {
                throw AutomationValidationError.invalidValueType(
                    characteristic: characteristic,
                    expected:
                        "integer (\(min)–\(max)) or string (\(aliases.joined(separator: "/")))",
                    got: describeValueType(value))
            }

        case .doubleRange(let min, let max, let unit):
            guard let dblVal = value.doubleValue else {
                throw AutomationValidationError.invalidValueType(
                    characteristic: characteristic, expected: "number (\(min)–\(max)\(unit))",
                    got: describeValueType(value))
            }
            guard dblVal >= min && dblVal <= max else {
                throw AutomationValidationError.valueOutOfRange(
                    characteristic: characteristic, value: "\(dblVal)",
                    validRange: "\(min)–\(max)\(unit)")
            }

        case .binaryOrStrings(let aliases):
            if let intVal = value.intValue {
                guard intVal == 0 || intVal == 1 else {
                    throw AutomationValidationError.valueOutOfRange(
                        characteristic: characteristic, value: "\(intVal)",
                        validRange: "0/1 or \(aliases.joined(separator: "/"))")
                }
            } else if let str = value.stringValue {
                guard aliases.contains(str.lowercased()) else {
                    throw AutomationValidationError.valueOutOfRange(
                        characteristic: characteristic, value: str,
                        validRange: "0/1, \(aliases.joined(separator: "/"))")
                }
            } else if value.boolValue != nil {
                return  // Boolean is accepted
            } else {
                throw AutomationValidationError.invalidValueType(
                    characteristic: characteristic,
                    expected: "0/1, \(aliases.joined(separator: "/")), or boolean",
                    got: describeValueType(value))
            }
        }
    }

    // MARK: - PR9: Cron Expression Validation

    /// Validates a 5-field cron expression.
    ///
    /// Format: `minute hour dayOfMonth month dayOfWeek`
    /// - minute: 0–59
    /// - hour: 0–23
    /// - dayOfMonth: 1–31
    /// - month: 1–12
    /// - dayOfWeek: 0–7 (0 and 7 are both Sunday)
    ///
    /// Supports wildcards (*), ranges (1-5), lists (1,3,5), and steps (*/5, 1-10/2).
    ///
    /// - Parameter cron: The cron expression string to validate.
    /// - Throws: `AutomationValidationError.invalidCronExpression` if the expression is malformed.
    func validateCronExpression(_ cron: String) throws {
        let fields = cron.trimmingCharacters(in: .whitespaces).split(separator: " ").map(
            String.init)
        guard fields.count == 5 else {
            throw AutomationValidationError.invalidCronExpression(
                reason: "Expected 5 fields (minute hour day month weekday), got \(fields.count)"
            )
        }

        let fieldNames = ["minute", "hour", "day-of-month", "month", "day-of-week"]
        let fieldRanges: [(Int, Int)] = [
            (0, 59),  // minute
            (0, 23),  // hour
            (1, 31),  // day of month
            (1, 12),  // month
            (0, 7),  // day of week (0 and 7 = Sunday)
        ]

        for (index, field) in fields.enumerated() {
            try validateCronField(
                field,
                name: fieldNames[index],
                min: fieldRanges[index].0,
                max: fieldRanges[index].1
            )
        }
    }

    /// Validates a single cron field against its allowed range.
    ///
    /// Supports: wildcard (*), step (*/N or M-N/S), list (A,B,C), range (A-B), and literal values.
    ///
    /// - Parameters:
    ///   - field: The cron field string to validate.
    ///   - name: Human-readable field name (for error messages).
    ///   - min: Minimum allowed value for this field.
    ///   - max: Maximum allowed value for this field.
    /// - Throws: `AutomationValidationError.invalidCronExpression` if the field is invalid.
    private func validateCronField(_ field: String, name: String, min: Int, max: Int) throws {
        // Handle list (e.g., "1,3,5")
        if field.contains(",") {
            let parts = field.split(separator: ",").map(String.init)
            for part in parts {
                try validateCronField(part, name: name, min: min, max: max)
            }
            return
        }

        // Handle step (e.g., "*/5" or "1-10/2")
        if field.contains("/") {
            let parts = field.split(separator: "/").map(String.init)
            guard parts.count == 2 else {
                throw AutomationValidationError.invalidCronExpression(
                    reason: "Invalid step expression \"\(field)\" in \(name)"
                )
            }
            // Validate the base part (before /)
            if parts[0] != "*" {
                try validateCronField(parts[0], name: name, min: min, max: max)
            }
            // Validate the step value
            guard let step = Int(parts[1]), step >= 1, step <= max else {
                throw AutomationValidationError.invalidCronExpression(
                    reason: "Invalid step value \"\(parts[1])\" in \(name) (must be 1–\(max))"
                )
            }
            return
        }

        // Handle wildcard
        if field == "*" {
            return
        }

        // Handle range (e.g., "1-5")
        if field.contains("-") {
            let parts = field.split(separator: "-").map(String.init)
            guard parts.count == 2,
                let start = Int(parts[0]),
                let end = Int(parts[1])
            else {
                throw AutomationValidationError.invalidCronExpression(
                    reason: "Invalid range \"\(field)\" in \(name)"
                )
            }
            guard start >= min && start <= max else {
                throw AutomationValidationError.invalidCronExpression(
                    reason: "Range start \(start) out of bounds for \(name) (\(min)–\(max))"
                )
            }
            guard end >= min && end <= max else {
                throw AutomationValidationError.invalidCronExpression(
                    reason: "Range end \(end) out of bounds for \(name) (\(min)–\(max))"
                )
            }
            guard start <= end else {
                throw AutomationValidationError.invalidCronExpression(
                    reason: "Range start \(start) is greater than end \(end) in \(name)"
                )
            }
            return
        }

        // Handle literal value
        guard let value = Int(field) else {
            throw AutomationValidationError.invalidCronExpression(
                reason: "Invalid value \"\(field)\" in \(name) — expected integer"
            )
        }
        guard value >= min && value <= max else {
            throw AutomationValidationError.invalidCronExpression(
                reason: "Value \(value) out of bounds for \(name) (\(min)–\(max))"
            )
        }
    }

    /// Returns a human-readable description of a cron schedule expression.
    ///
    /// Examples:
    /// - `"0 7 * * *"` → `"Every day at 7:00 AM"`
    /// - `"45 6 * * 1-5"` → `"Every weekday at 6:45 AM"`
    /// - `"0 22 * * 0,6"` → `"Every weekend at 10:00 PM"`
    /// - `"*/15 * * * *"` → `"Every 15 minutes"`
    /// - `"0 8 1 * *"` → `"At 8:00 AM on day 1 of every month"`
    ///
    /// - Parameter cron: A valid 5-field cron expression.
    /// - Returns: A human-readable string describing the schedule.
    func humanReadableCron(_ cron: String) -> String {
        let fields = cron.trimmingCharacters(in: .whitespaces).split(separator: " ").map(
            String.init)
        guard fields.count == 5 else { return cron }

        let minute = fields[0]
        let hour = fields[1]
        let dayOfMonth = fields[2]
        let month = fields[3]
        let dayOfWeek = fields[4]

        // Handle "every N minutes" pattern: */N * * * *
        if minute.hasPrefix("*/"), hour == "*", dayOfMonth == "*", month == "*", dayOfWeek == "*" {
            let step = String(minute.dropFirst(2))
            return "Every \(step) minutes"
        }

        // Handle "every N hours" pattern: 0 */N * * *
        if minute == "0", hour.hasPrefix("*/"), dayOfMonth == "*", month == "*", dayOfWeek == "*" {
            let step = String(hour.dropFirst(2))
            return "Every \(step) hours"
        }

        // Build time description
        let timeDesc = formatTime(minute: minute, hour: hour)

        // Build day description
        let dayDesc = formatDayDescription(
            dayOfMonth: dayOfMonth, month: month, dayOfWeek: dayOfWeek)

        if dayDesc.isEmpty {
            return timeDesc
        }

        return "\(dayDesc) at \(timeDesc)"
    }

    /// Formats a time from cron minute and hour fields into a human-readable string.
    private func formatTime(minute: String, hour: String) -> String {
        guard let h = Int(hour), let m = Int(minute) else {
            if hour == "*" && minute == "*" { return "every minute" }
            if hour == "*" { return "at minute \(minute) of every hour" }
            return "\(hour):\(minute)"
        }

        let period = h >= 12 ? "PM" : "AM"
        let displayHour = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return String(format: "%d:%02d %@", displayHour, m, period)
    }

    /// Formats the day-of-month, month, and day-of-week fields into a human-readable description.
    private func formatDayDescription(dayOfMonth: String, month: String, dayOfWeek: String)
        -> String
    {
        // Specific day-of-week patterns
        if dayOfMonth == "*" && month == "*" && dayOfWeek != "*" {
            return "Every \(describeDayOfWeek(dayOfWeek))"
        }

        // Specific day-of-month
        if dayOfMonth != "*" && month == "*" && dayOfWeek == "*" {
            return "On day \(dayOfMonth) of every month"
        }

        // Specific month and day
        if dayOfMonth != "*" && month != "*" && dayOfWeek == "*" {
            return "On \(describeMonth(month)) \(dayOfMonth)"
        }

        // Every day
        if dayOfMonth == "*" && month == "*" && dayOfWeek == "*" {
            return "Every day"
        }

        return ""
    }

    /// Converts a cron day-of-week field into a human-readable name.
    private func describeDayOfWeek(_ field: String) -> String {
        // Check for weekday pattern: 1-5
        if field == "1-5" { return "weekday" }
        // Check for weekend pattern: 0,6 or 6,0
        if field == "0,6" || field == "6,0" { return "weekend" }

        let dayNames = [
            "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
        ]

        // Handle list (e.g., "1,3,5")
        if field.contains(",") {
            let days = field.split(separator: ",").compactMap { Int($0) }.map {
                dayNames[min($0, 7)]
            }
            return days.joined(separator: ", ")
        }

        // Handle range (e.g., "1-3")
        if field.contains("-") {
            let parts = field.split(separator: "-").compactMap { Int($0) }
            if parts.count == 2 {
                return "\(dayNames[min(parts[0], 7)]) through \(dayNames[min(parts[1], 7)])"
            }
        }

        // Single day
        if let day = Int(field), day >= 0, day <= 7 {
            return dayNames[day]
        }

        return field
    }

    /// Converts a cron month field into a human-readable name.
    private func describeMonth(_ field: String) -> String {
        let monthNames = [
            "", "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December",
        ]
        if let m = Int(field), m >= 1, m <= 12 {
            return monthNames[m]
        }
        return "month \(field)"
    }

    // MARK: - Convenience: Full Definition Validation

    /// Validates an entire automation definition against the discovered device map.
    ///
    /// Runs all validation checks:
    /// 1. Non-empty actions check
    /// 2. Cron expression validation (for schedule triggers)
    /// 3. For each action: device existence, characteristic support, value range, delay bounds
    ///
    /// - Parameters:
    ///   - definition: The automation definition to validate.
    ///   - deviceMap: Array of device dictionaries from the discovery response.
    /// - Throws: The first `AutomationValidationError` encountered.
    func validateDefinition(
        _ definition: AutomationDefinition, deviceMap: [[String: AnyCodableValue]]
    ) throws {
        try validateTrigger(definition.trigger)
        try validateActions(definition.actions, deviceMap: deviceMap)
    }

    /// Validates an array of actions against the device map.
    ///
    /// Used by AutomationEdit when new actions are provided.
    ///
    /// - Parameters:
    ///   - actions: The actions to validate.
    ///   - deviceMap: Array of device dictionaries from the discovery response.
    /// - Throws: The first `AutomationValidationError` encountered.
    func validateActions(_ actions: [AutomationAction], deviceMap: [[String: AnyCodableValue]])
        throws
    {
        guard !actions.isEmpty else {
            throw AutomationValidationError.emptyActions
        }

        for action in actions {
            if action.type == "scene" { continue }

            if action.delaySeconds < 0 || action.delaySeconds > 3600 {
                throw AutomationValidationError.invalidDelaySeconds(action.delaySeconds)
            }

            try validateDeviceExists(deviceName: action.deviceName, deviceMap: deviceMap)

            if let deviceInfo = findDevice(named: action.deviceName, in: deviceMap) {
                try validateCharacteristic(
                    characteristic: action.characteristic,
                    deviceName: action.deviceName,
                    deviceInfo: deviceInfo
                )
            }

            try validateValueRange(characteristic: action.characteristic, value: action.value)
        }
    }

    /// Validates a trigger, specifically cron expressions for schedule triggers.
    ///
    /// - Parameter trigger: The trigger to validate.
    /// - Throws: `AutomationValidationError.invalidCronExpression` if the cron is malformed.
    func validateTrigger(_ trigger: AutomationTrigger) throws {
        if trigger.type == "schedule", let cron = trigger.cron {
            try validateCronExpression(cron)
        }
    }

    // MARK: - Helpers

    /// Returns a human-readable type description for an AnyCodableValue.
    private func describeValueType(_ value: AnyCodableValue) -> String {
        switch value {
        case .string: return "string"
        case .int: return "integer"
        case .double: return "double"
        case .bool: return "boolean"
        case .array: return "array"
        case .dictionary: return "dictionary"
        case .null: return "null"
        }
    }
}

/// Extracts the device map from a discovery response as an array of dictionaries.
///
/// The discover command returns its data payload in the `data` field. This helper
/// converts that payload into the `[[String: AnyCodableValue]]` format expected by
/// the validator.
///
/// - Parameter response: The socket response from the "discover" command.
/// - Returns: An array of device dictionaries, or an empty array if extraction fails.
func extractDeviceMap(from response: SocketClient.Response) -> [[String: AnyCodableValue]] {
    // The discover response data may be an array of devices directly,
    // or a dictionary with a "devices" key containing the array.
    if let arrayValue = response.data?.arrayValue {
        return arrayValue.compactMap { $0.dictionaryValue }
    }
    if let dictValue = response.data?.dictionaryValue,
        let devices = dictValue["devices"]?.arrayValue
    {
        return devices.compactMap { $0.dictionaryValue }
    }
    return []
}
