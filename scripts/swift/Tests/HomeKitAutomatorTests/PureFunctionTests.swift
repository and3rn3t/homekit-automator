// PureFunctionTests.swift
// Tests for pure/stateless functions: temperature conversion, humanReadableCron, compareValues.

import XCTest
@testable import homekitauto

final class PureFunctionTests: XCTestCase {

    // MARK: - Temperature Conversion

    func testCelsiusToFahrenheitKnownValues() {
        // Water freezing point
        XCTAssertEqual(celsiusToFahrenheit(0), 32.0, accuracy: 0.001)
        // Water boiling point
        XCTAssertEqual(celsiusToFahrenheit(100), 212.0, accuracy: 0.001)
        // Human body temperature
        XCTAssertEqual(celsiusToFahrenheit(37.0), 98.6, accuracy: 0.001)
        // Negative
        XCTAssertEqual(celsiusToFahrenheit(-40), -40.0, accuracy: 0.001)
        // Room temperature
        XCTAssertEqual(celsiusToFahrenheit(22.0), 71.6, accuracy: 0.001)
    }

    func testFahrenheitToCelsiusKnownValues() {
        XCTAssertEqual(fahrenheitToCelsius(32), 0.0, accuracy: 0.001)
        XCTAssertEqual(fahrenheitToCelsius(212), 100.0, accuracy: 0.001)
        XCTAssertEqual(fahrenheitToCelsius(98.6), 37.0, accuracy: 0.001)
        XCTAssertEqual(fahrenheitToCelsius(-40), -40.0, accuracy: 0.001)
        XCTAssertEqual(fahrenheitToCelsius(71.6), 22.0, accuracy: 0.001)
    }

    func testTemperatureRoundtrip() {
        // Converting C→F→C should return the original value
        let values: [Double] = [-20, 0, 10, 22, 37, 100]
        for c in values {
            let roundtrip = fahrenheitToCelsius(celsiusToFahrenheit(c))
            XCTAssertEqual(roundtrip, c, accuracy: 0.0001,
                           "Roundtrip failed for \(c)°C")
        }
    }

    // MARK: - humanReadableCron

    func testHumanReadableCronDaily() {
        let validator = AutomationValidator()
        let desc = validator.humanReadableCron("0 7 * * *")
        XCTAssertEqual(desc, "Every day at 7:00 AM")
    }

    func testHumanReadableCronWeekdays() {
        let validator = AutomationValidator()
        let desc = validator.humanReadableCron("45 6 * * 1-5")
        XCTAssertEqual(desc, "Every weekday at 6:45 AM")
    }

    func testHumanReadableCronWeekend() {
        let validator = AutomationValidator()
        let desc = validator.humanReadableCron("0 22 * * 0,6")
        XCTAssertEqual(desc, "Every weekend at 10:00 PM")
    }

    func testHumanReadableCronEveryNMinutes() {
        let validator = AutomationValidator()
        let desc = validator.humanReadableCron("*/15 * * * *")
        XCTAssertEqual(desc, "Every 15 minutes")
    }

    func testHumanReadableCronEveryNHours() {
        let validator = AutomationValidator()
        let desc = validator.humanReadableCron("0 */2 * * *")
        XCTAssertEqual(desc, "Every 2 hours")
    }

    func testHumanReadableCronDayOfMonth() {
        let validator = AutomationValidator()
        let desc = validator.humanReadableCron("0 8 1 * *")
        XCTAssertTrue(desc.contains("day 1"), "Should mention day 1: \(desc)")
        XCTAssertTrue(desc.contains("8:00 AM"), "Should mention 8:00 AM: \(desc)")
    }

    func testHumanReadableCronMidnight() {
        let validator = AutomationValidator()
        let desc = validator.humanReadableCron("0 0 * * *")
        XCTAssertTrue(desc.contains("12:00 AM"), "Midnight should be 12:00 AM: \(desc)")
    }

    func testHumanReadableCronAfternoon() {
        let validator = AutomationValidator()
        let desc = validator.humanReadableCron("30 14 * * *")
        XCTAssertTrue(desc.contains("2:30 PM"), "14:30 should be 2:30 PM: \(desc)")
    }

    func testHumanReadableCronInvalidInput() {
        let validator = AutomationValidator()
        // Not enough fields — should return the raw input
        let desc = validator.humanReadableCron("0 7")
        XCTAssertEqual(desc, "0 7")
    }

    // MARK: - compareValues (via ConditionEvaluator)
    //
    // compareValues is private, so we test it indirectly through
    // a device_state condition with a mock. Since the socket call
    // is async, we test the underlying comparison helpers that are
    // also exercised by compareValues.

    // MARK: - valuesEqual Smoke Tests

    func testCompareValuesEqualsInts() {
        // Use the ConditionEvaluator's equals path via numericCompare indirectly:
        // We can test the exposed numericCompare behavior via the AnyCodableValue
        // doubleValue extraction which is what compareValues uses.
        //
        // Direct equality: int == int
        XCTAssertEqual(AnyCodableValue.int(42).doubleValue, 42.0)
        XCTAssertEqual(AnyCodableValue.double(42.0).doubleValue, 42.0)
        // Cross-type: int and double are numerically equal
        XCTAssertEqual(AnyCodableValue.int(42).doubleValue, AnyCodableValue.double(42.0).doubleValue)
    }

    func testCompareValuesNonNumericReturnsNilDouble() {
        // Non-numeric types should return nil from doubleValue
        XCTAssertNil(AnyCodableValue.string("hello").doubleValue)
        XCTAssertNil(AnyCodableValue.bool(true).doubleValue)
        XCTAssertNil(AnyCodableValue.null.doubleValue)
        XCTAssertNil(AnyCodableValue.array([]).doubleValue)
        XCTAssertNil(AnyCodableValue.dictionary([:]).doubleValue)
    }

    func testCompareValuesMixedIntDouble() {
        // int(75) has doubleValue 75.0 — this is the path numericCompare uses
        let intVal = AnyCodableValue.int(75)
        let doubleVal = AnyCodableValue.double(75.0)
        XCTAssertEqual(intVal.doubleValue, doubleVal.doubleValue)

        let intSmaller = AnyCodableValue.int(50)
        XCTAssertTrue(intSmaller.doubleValue! < doubleVal.doubleValue!)
    }

    // MARK: - validateActions Batch Validation

    func testValidateActionsEmpty() {
        let validator = AutomationValidator()
        XCTAssertThrowsError(try validator.validateActions([], deviceMap: [])) { error in
            guard case AutomationValidator.AutomationValidationError.emptyActions = error else {
                XCTFail("Expected .emptyActions, got \(error)")
                return
            }
        }
    }

    func testValidateActionsNegativeDelay() {
        let validator = AutomationValidator()
        let action = AutomationAction(
            deviceUuid: "dev-001",
            deviceName: "Test Light",
            characteristic: "power",
            value: .bool(true),
            delaySeconds: -1
        )
        XCTAssertThrowsError(try validator.validateActions([action], deviceMap: [])) { error in
            guard case AutomationValidator.AutomationValidationError.invalidDelaySeconds(let secs) = error else {
                XCTFail("Expected .invalidDelaySeconds, got \(error)")
                return
            }
            XCTAssertEqual(secs, -1)
        }
    }

    func testValidateActionsExcessiveDelay() {
        let validator = AutomationValidator()
        let action = AutomationAction(
            deviceUuid: "dev-001",
            deviceName: "Test Light",
            characteristic: "power",
            value: .bool(true),
            delaySeconds: 7200
        )
        XCTAssertThrowsError(try validator.validateActions([action], deviceMap: [])) { error in
            guard case AutomationValidator.AutomationValidationError.invalidDelaySeconds(let secs) = error else {
                XCTFail("Expected .invalidDelaySeconds, got \(error)")
                return
            }
            XCTAssertEqual(secs, 7200)
        }
    }

    func testValidateActionsSceneTypeSkipsValidation() {
        let validator = AutomationValidator()
        // Scene actions should skip all device/characteristic validation
        let sceneAction = AutomationAction(
            type: "scene",
            deviceUuid: "",
            deviceName: "",
            characteristic: "",
            value: .null,
            delaySeconds: 0
        )
        XCTAssertNoThrow(try validator.validateActions([sceneAction], deviceMap: []))
    }

    func testValidateActionsDeviceNotFound() {
        let validator = AutomationValidator()
        let action = AutomationAction(
            deviceUuid: "dev-001",
            deviceName: "Nonexistent Light",
            characteristic: "power",
            value: .bool(true),
            delaySeconds: 0
        )
        XCTAssertThrowsError(try validator.validateActions([action], deviceMap: [])) { error in
            guard case AutomationValidator.AutomationValidationError.deviceNotFound(let name, _) = error else {
                XCTFail("Expected .deviceNotFound, got \(error)")
                return
            }
            XCTAssertEqual(name, "Nonexistent Light")
        }
    }

    func testValidateActionsMaxDelay() {
        let validator = AutomationValidator()
        // Exactly 3600 seconds is the maximum allowed
        let action = AutomationAction(
            deviceUuid: "dev-001",
            deviceName: "Test Light",
            characteristic: "power",
            value: .bool(true),
            delaySeconds: 3600
        )
        // Device doesn't exist, so it'll throw deviceNotFound rather than invalidDelay
        // which confirms the delay check passed
        XCTAssertThrowsError(try validator.validateActions([action], deviceMap: [])) { error in
            guard case AutomationValidator.AutomationValidationError.deviceNotFound = error else {
                XCTFail("Expected .deviceNotFound (delay passed), got \(error)")
                return
            }
        }
    }
}
