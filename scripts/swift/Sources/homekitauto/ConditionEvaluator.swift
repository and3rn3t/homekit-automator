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
/// - `solar`: Checks solar-based requirements using calculated sunrise/sunset times
///
/// Data flow:
///   AutomationTest → ConditionEvaluator.evaluate() → ConditionResult
///   If allMet == false and --force is not set, test execution stops with a report.

import Foundation

/// Simple sunrise/sunset calculator using a simplified NOAA Solar Calculator algorithm.
///
/// Calculates approximate sunrise and sunset times based on latitude, longitude, and date.
/// The approximation uses solar declination and hour angle calculations.
/// Accuracy: ±5 minutes for most populated areas (latitudes between 60°S and 60°N).
/// At extreme latitudes (>65°), accuracy decreases; midnight sun and polar night
/// conditions are handled with clamped hour angles.
///
/// Reference: NOAA Solar Calculator (simplified)
/// https://gml.noaa.gov/grad/solcalc/
struct SolarCalculator {
    let latitude: Double
    let longitude: Double

    /// Calculate sunrise and sunset decimal hours for a given date.
    ///
    /// The returned decimal hours represent local time adjusted for the system timezone.
    /// Values may fall outside [0, 24) if the system timezone does not match the location.
    /// Use `calculate(for:)` for DateComponents with proper wrapping.
    ///
    /// - Parameter date: The date to calculate for (defaults to now).
    /// - Returns: A tuple of raw decimal hours for sunrise and sunset.
    func calculateRaw(for date: Date = Date()) -> (sunriseDecimal: Double, sunsetDecimal: Double) {
        let calendar = Calendar.current
        let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)

        // Solar declination (simplified)
        let declination = -23.45 * cos(2.0 * .pi / 365.0 * (dayOfYear + 10))
        let declinationRad = declination * .pi / 180.0
        let latRad = latitude * .pi / 180.0

        // Hour angle at sunrise/sunset
        let cosHourAngle = -tan(latRad) * tan(declinationRad)
        let hourAngle: Double
        if cosHourAngle < -1 { hourAngle = .pi }       // Midnight sun
        else if cosHourAngle > 1 { hourAngle = 0 }     // Polar night
        else { hourAngle = acos(cosHourAngle) }

        let hourAngleDegrees = hourAngle * 180.0 / .pi

        // Solar noon (approximate, adjusted for longitude and timezone)
        let timezone = Double(TimeZone.current.secondsFromGMT(for: date)) / 3600.0
        let solarNoon = 12.0 - longitude / 15.0 + timezone

        let sunriseDecimal = solarNoon - hourAngleDegrees / 15.0
        let sunsetDecimal = solarNoon + hourAngleDegrees / 15.0

        return (sunriseDecimal, sunsetDecimal)
    }

    /// Calculate sunrise and sunset for a given date as DateComponents (hour + minute).
    ///
    /// - Parameter date: The date to calculate for (defaults to now).
    /// - Returns: A tuple of DateComponents for sunrise and sunset.
    func calculate(for date: Date = Date()) -> (sunrise: DateComponents, sunset: DateComponents) {
        let raw = calculateRaw(for: date)
        return (toComponents(raw.sunriseDecimal), toComponents(raw.sunsetDecimal))
    }

    /// Converts a decimal hour (e.g., 6.5 = 06:30) to DateComponents with hour and minute.
    /// Wraps values outside [0, 24) using modular arithmetic.
    func toComponents(_ decimal: Double) -> DateComponents {
        var wrapped = decimal.truncatingRemainder(dividingBy: 24.0)
        if wrapped < 0 { wrapped += 24.0 }
        var components = DateComponents()
        components.hour = Int(wrapped)
        components.minute = Int((wrapped - Double(Int(wrapped))) * 60)
        return components
    }

    /// Default location (San Francisco, CA) used as a fallback when the user has not
    /// configured their latitude/longitude. Users can set their coordinates via:
    ///   homekitauto config --set latitude 40.7128 --set longitude -74.0060
    static let `default` = SolarCalculator(latitude: 37.7749, longitude: -122.4194)
}

/// Evaluates automation conditions against live state and environment.
struct ConditionEvaluator {

    /// Latitude for solar calculations (defaults to San Francisco).
    let latitude: Double
    /// Longitude for solar calculations (defaults to San Francisco).
    let longitude: Double

    init(latitude: Double = SolarCalculator.default.latitude,
         longitude: Double = SolarCalculator.default.longitude) {
        self.latitude = latitude
        self.longitude = longitude
    }

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
    func evaluate(conditions: [AutomationCondition], using client: SocketClient, at date: Date = Date()) async throws -> ConditionResult {
        var results: [SingleResult] = []

        for condition in conditions {
            let result: SingleResult
            switch condition.type {
            case "time", "time_range":
                result = evaluateTimeRange(condition, at: date)
            case "deviceState", "device_state":
                result = await evaluateDeviceState(condition, using: client)
            case "dayOfWeek", "day_of_week":
                result = evaluateDayOfWeek(condition, at: date)
            case "solar":
                result = evaluateSolar(condition, at: date)
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
    /// - Parameters:
    ///   - condition: A condition with type "time" or "time_range", using `after` and/or `before` fields.
    ///   - date: The reference date/time to evaluate against (defaults to now).
    /// - Returns: SingleResult indicating pass/fail with an explanatory reason.
    func evaluateTimeRange(_ condition: AutomationCondition, at date: Date = Date()) -> SingleResult {
        let now = date
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
    func parseTimeToMinutes(_ time: String?) -> Int? {
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
    /// Returns false for numeric operators when values are non-numeric.
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
            guard let result = numericCompare(actual, expected) else { return false }
            return result == .orderedDescending || result == .orderedSame
        case "lessOrEqual":
            guard let result = numericCompare(actual, expected) else { return false }
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
    /// Returns nil if either value is non-numeric (callers must handle the nil case).
    private func numericCompare(_ a: AnyCodableValue, _ b: AnyCodableValue) -> ComparisonResult? {
        guard let aNum = a.doubleValue, let bNum = b.doubleValue else {
            return nil
        }
        if aNum < bNum { return .orderedAscending }
        if aNum > bNum { return .orderedDescending }
        return .orderedSame
    }

    // MARK: - Day of Week

    /// Evaluates a day-of-week condition by checking if the current day number
    /// is in the condition's `days` array (0=Sunday, 1=Monday, ..., 6=Saturday).
    ///
    /// - Parameters:
    ///   - condition: A condition with type "dayOfWeek" and a `days` array.
    ///   - date: The reference date to evaluate against (defaults to now).
    /// - Returns: SingleResult indicating whether today matches.
    func evaluateDayOfWeek(_ condition: AutomationCondition, at date: Date = Date()) -> SingleResult {
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
        let todayWeekday = calendar.component(.weekday, from: date) - 1
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

    /// Evaluates a solar condition using calculated sunrise/sunset times based on latitude and longitude.
    ///
    /// Uses `SolarCalculator` with the evaluator's configured coordinates to compute
    /// approximate sunrise and sunset for the given date. Accuracy is ±5 minutes for
    /// most populated areas (latitudes between 60°S and 60°N).
    ///
    /// Supported requirements: "after_sunset", "before_sunset", "after_sunrise", "before_sunrise".
    ///
    /// - Parameters:
    ///   - condition: A condition with type "solar" and a `requirement` field.
    ///   - date: The reference date/time to evaluate against (defaults to now).
    /// - Returns: SingleResult indicating pass/fail.
    func evaluateSolar(_ condition: AutomationCondition, at date: Date = Date()) -> SingleResult {
        guard let requirement = condition.requirement else {
            return SingleResult(
                condition: condition,
                met: false,
                reason: "Solar condition missing 'requirement' field"
            )
        }

        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: date)
        let currentMinute = calendar.component(.minute, from: date)
        let currentMinutes = currentHour * 60 + currentMinute

        let calculator = SolarCalculator(latitude: latitude, longitude: longitude)
        let solar = calculator.calculate(for: date)

        let sunriseMinutes = (solar.sunrise.hour ?? 6) * 60 + (solar.sunrise.minute ?? 30)
        let sunsetMinutes = (solar.sunset.hour ?? 18) * 60 + (solar.sunset.minute ?? 30)

        let sunriseStr = String(format: "%02d:%02d", solar.sunrise.hour ?? 6, solar.sunrise.minute ?? 30)
        let sunsetStr = String(format: "%02d:%02d", solar.sunset.hour ?? 18, solar.sunset.minute ?? 30)

        let met: Bool
        let explanation: String
        switch requirement {
        case "after_sunset":
            met = currentMinutes >= sunsetMinutes
            explanation = "Current time is \(met ? "after" : "before") ~sunset (\(sunsetStr))"
        case "before_sunset":
            met = currentMinutes < sunsetMinutes
            explanation = "Current time is \(met ? "before" : "after") ~sunset (\(sunsetStr))"
        case "after_sunrise":
            met = currentMinutes >= sunriseMinutes
            explanation = "Current time is \(met ? "after" : "before") ~sunrise (\(sunriseStr))"
        case "before_sunrise":
            met = currentMinutes < sunriseMinutes
            explanation = "Current time is \(met ? "before" : "after") ~sunrise (\(sunriseStr))"
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
