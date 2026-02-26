/// ConditionEvaluator.swift
/// Evaluates automation conditions at runtime against live device state, time, and calendar data.
///
/// Used by AutomationTest to check whether an automation's preconditions are met before
/// executing actions. Each condition (time range, device state, day of week, home mode)
/// is evaluated independently and all must pass for the overall result to be `allMet`.
///
/// Condition types:
/// - `time` / `time_range`: Checks if the current time falls within a start/end window (HH:MM format)
/// - `deviceState` / `device_state`: Queries a device via SocketClient and compares a characteristic value
/// - `dayOfWeek` / `day_of_week`: Checks if the current day number matches the allowed set
/// - `solar`: Checks solar-based requirements (approximated by time of day)
///
/// Data flow:
///   AutomationTest → ConditionEvaluator.evaluate() → ConditionResult
///   If allMet == false and --force is not set, test execution stops with a report.

import Foundation

/// Evaluates automation conditions against live state and environment.
struct ConditionEvaluator {

    // MARK: - Result Types

    /// Result of evaluating a single condition.
    struct SingleResult {
        /// The condition that was evaluated.
        let condition: AutomationCondition
        /// Whether the condition was met.
        let met: Bool
        /// Human-readable explanation of why the condition passed or failed.
        let reason: String
    }

    /// Aggregate result of evaluating all conditions for an automation.
    struct ConditionResult {
        /// True only if every condition was met (logical AND).
        let allMet: Bool
        /// Per-condition evaluation results with explanations.
        let results: [SingleResult]
    }

    // MARK: - Evaluation

    /// Evaluates all conditions against current environment and device states.
    ///
    /// Each condition is evaluated independently. The overall result is `allMet == true`
    /// only when every condition passes. Device state conditions require a live socket
    /// connection to the HomeKitHelper.
    ///
    /// - Parameters:
    ///   - conditions: The conditions to evaluate (from an automation's `conditions` array).
    ///   - client: A connected SocketClient for querying device state.
    /// - Returns: A `ConditionResult` with per-condition details and an aggregate pass/fail.
    func evaluate(conditions: [AutomationCondition], using client: SocketClient) async throws -> ConditionResult {
        var results: [SingleResult] = []

        for condition in conditions {
            let result: SingleResult
            switch condition.type {
            case "time", "time_range":
                result = evaluateTimeRange(condition)
            case "deviceState", "device_state":
                result = await evaluateDeviceState(condition, using: client)
            case "dayOfWeek", "day_of_week":
                result = evaluateDayOfWeek(condition)
            case "solar":
                result = evaluateSolar(condition)
            default:
                result = SingleResult(
                    condition: condition,
                    met: false,
                    reason: "Unknown condition type: \(condition.type)"
                )
            }
            results.append(result)
        }

        let allMet = results.allSatisfy { $0.met }
        return ConditionResult(allMet: allMet, results: results)
    }

    // MARK: - Time Range

    /// Evaluates a time-range condition by checking if the current time falls between `after` and `before`.
    ///
    /// Supports overnight ranges (e.g., after 22:00, before 06:00). If only `after` is provided,
    /// checks that the current time is past that point. If only `before`, checks that it is before.
    ///
    /// - Parameter condition: A condition with type "time" or "time_range", using `after` and/or `before` fields.
    /// - Returns: SingleResult indicating pass/fail with an explanatory reason.
    private func evaluateTimeRange(_ condition: AutomationCondition) -> SingleResult {
        let now = Date()
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let currentMinutes = currentHour * 60 + currentMinute

        let afterMinutes = parseTimeToMinutes(condition.after)
        let beforeMinutes = parseTimeToMinutes(condition.before)

        let timeStr = String(format: "%02d:%02d", currentHour, currentMinute)

        if let after = afterMinutes, let before = beforeMinutes {
            let met: Bool
            if after <= before {
                // Same-day range: e.g., 08:00 – 18:00
                met = currentMinutes >= after && currentMinutes < before
            } else {
                // Overnight range: e.g., 22:00 – 06:00
                met = currentMinutes >= after || currentMinutes < before
            }
            return SingleResult(
                condition: condition,
                met: met,
                reason: met
                    ? "Current time \(timeStr) is within \(condition.after ?? "?")–\(condition.before ?? "?")"
                    : "Current time \(timeStr) is outside \(condition.after ?? "?")–\(condition.before ?? "?")"
            )
        } else if let after = afterMinutes {
            let met = currentMinutes >= after
            return SingleResult(
                condition: condition,
                met: met,
                reason: met
                    ? "Current time \(timeStr) is after \(condition.after ?? "?")"
                    : "Current time \(timeStr) is before \(condition.after ?? "?")"
            )
        } else if let before = beforeMinutes {
            let met = currentMinutes < before
            return SingleResult(
                condition: condition,
                met: met,
                reason: met
                    ? "Current time \(timeStr) is before \(condition.before ?? "?")"
                    : "Current time \(timeStr) is after \(condition.before ?? "?")"
            )
        } else {
            return SingleResult(
                condition: condition,
                met: false,
                reason: "Time condition missing 'after' and/or 'before' fields"
            )
        }
    }

    /// Parses an "HH:MM" time string into total minutes since midnight.
    /// Returns nil if the string is nil or malformed.
    private func parseTimeToMinutes(_ time: String?) -> Int? {
        guard let time = time else { return nil }
        let parts = time.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else { return nil }
        return hour * 60 + minute
    }

    // MARK: - Device State

    /// Evaluates a device-state condition by querying the device via the socket client
    /// and comparing the characteristic value using the specified operator.
    ///
    /// Supported operators: equals, notEquals, greaterThan, lessThan, greaterOrEqual, lessOrEqual.
    ///
    /// - Parameters:
    ///   - condition: A condition with type "deviceState" and fields deviceUuid/deviceName,
    ///     characteristic, operator, and value.
    ///   - client: SocketClient for querying the device.
    /// - Returns: SingleResult with comparison result or failure reason.
    private func evaluateDeviceState(_ condition: AutomationCondition, using client: SocketClient) async -> SingleResult {
        let deviceName = condition.deviceName ?? condition.deviceUuid ?? "unknown"
        guard let characteristic = condition.characteristic else {
            return SingleResult(condition: condition, met: false, reason: "Missing characteristic in device state condition")
        }
        guard let expectedValue = condition.value else {
            return SingleResult(condition: condition, met: false, reason: "Missing value in device state condition")
        }

        do {
            let response = try await client.send(
                command: "get_device",
                params: ["name": .string(deviceName)]
            )
            guard response.isOk,
                  let state = response.data?.dictionaryValue?["state"]?.dictionaryValue,
                  let actualValue = state[characteristic] else {
                return SingleResult(
                    condition: condition,
                    met: false,
                    reason: "Could not read '\(characteristic)' from \(deviceName)"
                )
            }

            let op = condition.operator ?? "equals"
            let met = compareValues(actual: actualValue, expected: expectedValue, operator: op)

            return SingleResult(
                condition: condition,
                met: met,
                reason: met
                    ? "\(deviceName).\(characteristic) = \(actualValue) (\(op) \(expectedValue) ✓)"
                    : "\(deviceName).\(characteristic) = \(actualValue) (expected \(op) \(expectedValue) ✗)"
            )
        } catch {
            return SingleResult(
                condition: condition,
                met: false,
                reason: "Failed to query device \(deviceName): \(error.localizedDescription)"
            )
        }
    }

    /// Compares two AnyCodableValue instances using the specified operator.
    /// Supports numeric comparisons (int/double) and equality for bools/strings.
    private func compareValues(actual: AnyCodableValue, expected: AnyCodableValue, operator op: String) -> Bool {
        switch op {
        case "equals":
            return valuesEqual(actual, expected)
        case "notEquals":
            return !valuesEqual(actual, expected)
        case "greaterThan":
            return numericCompare(actual, expected) == .orderedDescending
        case "lessThan":
            return numericCompare(actual, expected) == .orderedAscending
        case "greaterOrEqual":
            let result = numericCompare(actual, expected)
            return result == .orderedDescending || result == .orderedSame
        case "lessOrEqual":
            let result = numericCompare(actual, expected)
            return result == .orderedAscending || result == .orderedSame
        default:
            return false
        }
    }

    /// Checks equality between two AnyCodableValue instances.
    private func valuesEqual(_ a: AnyCodableValue, _ b: AnyCodableValue) -> Bool {
        switch (a, b) {
        case (.bool(let av), .bool(let bv)): return av == bv
        case (.int(let av), .int(let bv)): return av == bv
        case (.double(let av), .double(let bv)): return av == bv
        case (.string(let av), .string(let bv)): return av == bv
        case (.int(let av), .double(let bv)): return Double(av) == bv
        case (.double(let av), .int(let bv)): return av == Double(bv)
        default: return a.description == b.description
        }
    }

    /// Performs numeric comparison between two values, returning ComparisonResult.
    /// Returns nil if neither value is numeric.
    private func numericCompare(_ a: AnyCodableValue, _ b: AnyCodableValue) -> ComparisonResult {
        guard let aNum = a.doubleValue, let bNum = b.doubleValue else {
            return .orderedSame
        }
        if aNum < bNum { return .orderedAscending }
        if aNum > bNum { return .orderedDescending }
        return .orderedSame
    }

    // MARK: - Day of Week

    /// Evaluates a day-of-week condition by checking if the current day number
    /// is in the condition's `days` array (0=Sunday, 1=Monday, ..., 6=Saturday).
    ///
    /// - Parameter condition: A condition with type "dayOfWeek" and a `days` array.
    /// - Returns: SingleResult indicating whether today matches.
    private func evaluateDayOfWeek(_ condition: AutomationCondition) -> SingleResult {
        guard let allowedDays = condition.days, !allowedDays.isEmpty else {
            return SingleResult(
                condition: condition,
                met: false,
                reason: "Day-of-week condition has no days specified"
            )
        }

        let calendar = Calendar.current
        // Calendar.component(.weekday) returns 1=Sunday, 2=Monday, ..., 7=Saturday
        // Convert to 0-based: 0=Sunday, 1=Monday, ..., 6=Saturday
        let todayWeekday = calendar.component(.weekday, from: Date()) - 1
        let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let todayName = dayNames[todayWeekday]
        let met = allowedDays.contains(todayWeekday)

        let allowedNames = allowedDays.compactMap { $0 >= 0 && $0 < 7 ? dayNames[$0] : nil }
        return SingleResult(
            condition: condition,
            met: met,
            reason: met
                ? "Today is \(todayName), which is in the allowed days (\(allowedNames.joined(separator: ", ")))"
                : "Today is \(todayName), which is not in the allowed days (\(allowedNames.joined(separator: ", ")))"
        )
    }

    // MARK: - Solar

    /// Evaluates a solar condition using approximate sunrise/sunset times.
    ///
    /// Since exact solar calculations require location data, this uses reasonable defaults:
    /// - Sunrise ≈ 06:30
    /// - Sunset ≈ 18:30
    ///
    /// Supported requirements: "after_sunset", "before_sunset", "after_sunrise", "before_sunrise".
    ///
    /// - Parameter condition: A condition with type "solar" and a `requirement` field.
    /// - Returns: SingleResult indicating pass/fail.
    private func evaluateSolar(_ condition: AutomationCondition) -> SingleResult {
        guard let requirement = condition.requirement else {
            return SingleResult(
                condition: condition,
                met: false,
                reason: "Solar condition missing 'requirement' field"
            )
        }

        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let currentMinutes = currentHour * 60 + currentMinute

        // Approximate sunrise/sunset (these could be refined with location data)
        let sunriseMinutes = 6 * 60 + 30  // 06:30
        let sunsetMinutes = 18 * 60 + 30  // 18:30

        let met: Bool
        let explanation: String
        switch requirement {
        case "after_sunset":
            met = currentMinutes >= sunsetMinutes
            explanation = "Current time is \(met ? "after" : "before") ~sunset (18:30)"
        case "before_sunset":
            met = currentMinutes < sunsetMinutes
            explanation = "Current time is \(met ? "before" : "after") ~sunset (18:30)"
        case "after_sunrise":
            met = currentMinutes >= sunriseMinutes
            explanation = "Current time is \(met ? "after" : "before") ~sunrise (06:30)"
        case "before_sunrise":
            met = currentMinutes < sunriseMinutes
            explanation = "Current time is \(met ? "before" : "after") ~sunrise (06:30)"
        default:
            met = false
            explanation = "Unknown solar requirement: \(requirement)"
        }

        return SingleResult(
            condition: condition,
            met: met,
            reason: explanation
        )
    }
}
