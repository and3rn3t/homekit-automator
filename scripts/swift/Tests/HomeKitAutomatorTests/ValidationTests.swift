// ValidationTests.swift
// Comprehensive tests for the validation pipeline: device existence, characteristic support,
// value ranges, cron expressions, and duplicate name enforcement.

import XCTest
@testable import homekitauto

final class ValidationTests: XCTestCase {

    private let validator = AutomationValidator()

    // MARK: - Mock Device Map

    /// A mock device map used across tests. Contains devices of various categories.
    private var deviceMap: [[String: AnyCodableValue]] {
        [
            [
                "name": .string("Living Room Light"),
                "category": .string("light"),
                "uuid": .string("light-001")
            ],
            [
                "name": .string("Bedroom Thermostat"),
                "category": .string("thermostat"),
                "uuid": .string("therm-001")
            ],
            [
                "name": .string("Front Door Lock"),
                "category": .string("lock"),
                "uuid": .string("lock-001")
            ],
            [
                "name": .string("Motion Sensor"),
                "category": .string("sensor"),
                "uuid": .string("sensor-001")
            ],
            [
                "name": .string("Ceiling Fan"),
                "category": .string("fan"),
                "uuid": .string("fan-001")
            ]
        ]
    }

    // MARK: - Device Existence Tests

    func testValidDeviceName() throws {
        // "Living Room Light" exists in the device map — should not throw
        XCTAssertNoThrow(
            try validator.validateDeviceExists(deviceName: "Living Room Light", deviceMap: deviceMap)
        )
    }

    func testInvalidDeviceName() throws {
        // "Garage Light" does not exist — should throw .deviceNotFound
        XCTAssertThrowsError(
            try validator.validateDeviceExists(deviceName: "Garage Light", deviceMap: deviceMap)
        ) { error in
            guard case AutomationValidator.AutomationValidationError.deviceNotFound(let name, _) = error else {
                XCTFail("Expected .deviceNotFound, got \(error)")
                return
            }
            XCTAssertEqual(name, "Garage Light")
        }
    }

    func testDeviceNameCaseInsensitive() throws {
        // Case-insensitive: "living room light" should match "Living Room Light"
        XCTAssertNoThrow(
            try validator.validateDeviceExists(deviceName: "living room light", deviceMap: deviceMap)
        )
        XCTAssertNoThrow(
            try validator.validateDeviceExists(deviceName: "LIVING ROOM LIGHT", deviceMap: deviceMap)
        )
    }

    func testDeviceNameSuggestion() throws {
        // Typo "Livng Room Light" should suggest "Living Room Light" in the error
        XCTAssertThrowsError(
            try validator.validateDeviceExists(deviceName: "Livng Room Light", deviceMap: deviceMap)
        ) { error in
            guard case AutomationValidator.AutomationValidationError.deviceNotFound(_, let suggestion) = error else {
                XCTFail("Expected .deviceNotFound, got \(error)")
                return
            }
            XCTAssertNotNil(suggestion)
            XCTAssertEqual(suggestion, "Living Room Light")
        }
    }

    // MARK: - Characteristic Tests

    func testValidCharacteristic() throws {
        // Brightness is a valid writable characteristic for a light
        let lightInfo: [String: AnyCodableValue] = [
            "name": .string("Living Room Light"),
            "category": .string("light")
        ]
        XCTAssertNoThrow(
            try validator.validateCharacteristic(
                characteristic: "brightness",
                deviceName: "Living Room Light",
                deviceInfo: lightInfo
            )
        )
    }

    func testReadOnlyCharacteristic() throws {
        // currentTemperature is read-only — should throw .readOnlyCharacteristic
        let thermostatInfo: [String: AnyCodableValue] = [
            "name": .string("Bedroom Thermostat"),
            "category": .string("thermostat")
        ]
        XCTAssertThrowsError(
            try validator.validateCharacteristic(
                characteristic: "currentTemperature",
                deviceName: "Bedroom Thermostat",
                deviceInfo: thermostatInfo
            )
        ) { error in
            guard case AutomationValidator.AutomationValidationError.readOnlyCharacteristic(
                let characteristic, let deviceName
            ) = error else {
                XCTFail("Expected .readOnlyCharacteristic, got \(error)")
                return
            }
            XCTAssertEqual(characteristic, "currentTemperature")
            XCTAssertEqual(deviceName, "Bedroom Thermostat")
        }
    }

    func testUnsupportedCharacteristic() throws {
        // Brightness is not supported by a lock — should throw .unsupportedCharacteristic
        let lockInfo: [String: AnyCodableValue] = [
            "name": .string("Front Door Lock"),
            "category": .string("lock")
        ]
        XCTAssertThrowsError(
            try validator.validateCharacteristic(
                characteristic: "brightness",
                deviceName: "Front Door Lock",
                deviceInfo: lockInfo
            )
        ) { error in
            guard case AutomationValidator.AutomationValidationError.unsupportedCharacteristic(
                let characteristic, let category, let supported
            ) = error else {
                XCTFail("Expected .unsupportedCharacteristic, got \(error)")
                return
            }
            XCTAssertEqual(characteristic, "brightness")
            XCTAssertEqual(category, "lock")
            XCTAssertEqual(supported, ["lockState"])
        }
    }

    // MARK: - Value Range Tests

    func testBrightnessInRange() throws {
        // 50 is within 0–100
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "brightness", value: .int(50))
        )
    }

    func testBrightnessOutOfRange() throws {
        // 150 exceeds the 0–100 range
        XCTAssertThrowsError(
            try validator.validateValueRange(characteristic: "brightness", value: .int(150))
        ) { error in
            guard case AutomationValidator.AutomationValidationError.valueOutOfRange(
                let characteristic, let value, _
            ) = error else {
                XCTFail("Expected .valueOutOfRange, got \(error)")
                return
            }
            XCTAssertEqual(characteristic, "brightness")
            XCTAssertEqual(value, "150")
        }
    }

    func testTemperatureInRange() throws {
        // 22.0 °C is within 10–38
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "targetTemperature", value: .double(22.0))
        )
    }

    func testTemperatureOutOfRange() throws {
        // 50.0 °C exceeds the 10–38 range
        XCTAssertThrowsError(
            try validator.validateValueRange(characteristic: "targetTemperature", value: .double(50.0))
        ) { error in
            guard case AutomationValidator.AutomationValidationError.valueOutOfRange(
                let characteristic, _, _
            ) = error else {
                XCTFail("Expected .valueOutOfRange, got \(error)")
                return
            }
            XCTAssertEqual(characteristic, "targetTemperature")
        }
    }

    func testLockStateValid() throws {
        // 0 (unlocked) and 1 (locked) are both valid
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "lockState", value: .int(0))
        )
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "lockState", value: .int(1))
        )
    }

    func testLockStateInvalid() throws {
        // 5 is not a valid lock state (only 0 or 1)
        XCTAssertThrowsError(
            try validator.validateValueRange(characteristic: "lockState", value: .int(5))
        ) { error in
            guard case AutomationValidator.AutomationValidationError.valueOutOfRange(
                let characteristic, let value, _
            ) = error else {
                XCTFail("Expected .valueOutOfRange, got \(error)")
                return
            }
            XCTAssertEqual(characteristic, "lockState")
            XCTAssertEqual(value, "5")
        }
    }

    func testBooleanValue() throws {
        // true/false should pass for the "power" characteristic
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "power", value: .bool(true))
        )
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "power", value: .bool(false))
        )
    }

    // MARK: - Cron Expression Tests

    func testValidCron() throws {
        // "0 7 * * 1-5" — weekdays at 7:00 AM — should pass
        XCTAssertNoThrow(
            try validator.validateCronExpression("0 7 * * 1-5")
        )
    }

    func testInvalidCronTooFewFields() throws {
        // "0 7 *" has only 3 fields — needs 5
        XCTAssertThrowsError(
            try validator.validateCronExpression("0 7 *")
        ) { error in
            guard case AutomationValidator.AutomationValidationError.invalidCronExpression(let reason) = error else {
                XCTFail("Expected .invalidCronExpression, got \(error)")
                return
            }
            XCTAssertTrue(reason.contains("5 fields"), "Reason should mention 5 fields: \(reason)")
        }
    }

    func testInvalidCronRange() throws {
        // "0 25 * * *" — hour 25 is out of bounds (0–23)
        XCTAssertThrowsError(
            try validator.validateCronExpression("0 25 * * *")
        ) { error in
            guard case AutomationValidator.AutomationValidationError.invalidCronExpression(let reason) = error else {
                XCTFail("Expected .invalidCronExpression, got \(error)")
                return
            }
            XCTAssertTrue(reason.contains("25"), "Reason should mention the invalid value 25: \(reason)")
        }
    }

    func testCronHumanReadable() throws {
        // "0 7 * * 1-5" → should mention "7" (the hour) and weekday
        let description = validator.humanReadableCron("0 7 * * 1-5")
        XCTAssertTrue(description.contains("7"), "Description should contain the hour: \(description)")
        XCTAssertTrue(
            description.lowercased().contains("weekday"),
            "Description should mention weekday: \(description)"
        )
    }

    func testCronWithSteps() throws {
        // "*/15 * * * *" — every 15 minutes — should pass validation
        XCTAssertNoThrow(
            try validator.validateCronExpression("*/15 * * * *")
        )
    }

    // MARK: - Duplicate Name Tests

    private var tempDir: URL!
    private var registry: AutomationRegistry!

    /// Sets up an isolated temp directory and registry for duplicate name tests.
    /// Called explicitly because XCTestCase setUp/tearDown apply to all tests.
    private func setUpRegistry() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hka-validation-test-\(UUID().uuidString)")
        registry = AutomationRegistry(configDir: tempDir)
    }

    private func tearDownRegistry() {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    private func makeSampleAutomation(
        id: String = UUID().uuidString,
        name: String = "Test Automation"
    ) -> RegisteredAutomation {
        RegisteredAutomation(
            id: id,
            name: name,
            description: "A test automation",
            trigger: AutomationTrigger(
                type: "schedule",
                humanReadable: "daily at 7 AM",
                cron: "0 7 * * *"
            ),
            conditions: nil,
            actions: [
                AutomationAction(
                    deviceUuid: "dev-001",
                    deviceName: "Test Light",
                    characteristic: "power",
                    value: .bool(true),
                    delaySeconds: 0
                )
            ],
            enabled: true,
            shortcutName: "HKA: \(name)",
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    func testDuplicateNameOnSave() throws {
        setUpRegistry()
        defer { tearDownRegistry() }

        let first = makeSampleAutomation(name: "Morning Routine")
        try registry.save(first)

        let second = makeSampleAutomation(name: "Morning Routine")
        XCTAssertThrowsError(try registry.save(second)) { error in
            guard case RegistryError.duplicateName(let name) = error else {
                XCTFail("Expected RegistryError.duplicateName, got \(error)")
                return
            }
            XCTAssertEqual(name, "Morning Routine")
        }
    }

    func testDuplicateNameCaseInsensitive() throws {
        setUpRegistry()
        defer { tearDownRegistry() }

        let first = makeSampleAutomation(name: "Morning")
        try registry.save(first)

        // "morning" (lowercase) should conflict with "Morning"
        let second = makeSampleAutomation(name: "morning")
        XCTAssertThrowsError(try registry.save(second)) { error in
            guard case RegistryError.duplicateName = error else {
                XCTFail("Expected RegistryError.duplicateName, got \(error)")
                return
            }
        }
    }

    func testDuplicateNameOnUpdate() throws {
        setUpRegistry()
        defer { tearDownRegistry() }

        let first = makeSampleAutomation(id: "id-1", name: "Morning")
        let second = makeSampleAutomation(id: "id-2", name: "Evening")
        try registry.save(first)
        try registry.save(second)

        // Updating "Evening" to "Morning" should conflict
        var updated = second
        updated.name = "Morning"
        XCTAssertThrowsError(try registry.update(updated)) { error in
            guard case RegistryError.duplicateName(let name) = error else {
                XCTFail("Expected RegistryError.duplicateName, got \(error)")
                return
            }
            XCTAssertEqual(name, "Morning")
        }
    }

    func testUpdateSameNameAllowed() throws {
        setUpRegistry()
        defer { tearDownRegistry() }

        var automation = makeSampleAutomation(id: "id-1", name: "Morning")
        try registry.save(automation)

        // Updating the same automation without changing its name should succeed
        automation.description = "Updated description"
        XCTAssertNoThrow(try registry.update(automation))

        let found = try registry.find("id-1")
        XCTAssertEqual(found?.description, "Updated description")
    }
}
