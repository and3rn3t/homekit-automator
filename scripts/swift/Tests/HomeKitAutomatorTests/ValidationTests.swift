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

    func testDuplicateNameOnSave() async throws {
        setUpRegistry()
        defer { tearDownRegistry() }

        let first = makeSampleAutomation(name: "Morning Routine")
        try await registry.save(first)

        let second = makeSampleAutomation(name: "Morning Routine")
        do {
            try await registry.save(second)
            XCTFail("Expected RegistryError.duplicateName")
        } catch let error as RegistryError {
            guard case .duplicateName(let name) = error else {
                XCTFail("Expected RegistryError.duplicateName, got \(error)")
                return
            }
            XCTAssertEqual(name, "Morning Routine")
        }
    }

    func testDuplicateNameCaseInsensitive() async throws {
        setUpRegistry()
        defer { tearDownRegistry() }

        let first = makeSampleAutomation(name: "Morning")
        try await registry.save(first)

        // "morning" (lowercase) should conflict with "Morning"
        let second = makeSampleAutomation(name: "morning")
        do {
            try await registry.save(second)
            XCTFail("Expected RegistryError.duplicateName")
        } catch let error as RegistryError {
            guard case .duplicateName = error else {
                XCTFail("Expected RegistryError.duplicateName, got \(error)")
                return
            }
        }
    }

    func testDuplicateNameOnUpdate() async throws {
        setUpRegistry()
        defer { tearDownRegistry() }

        let first = makeSampleAutomation(id: "id-1", name: "Morning")
        let second = makeSampleAutomation(id: "id-2", name: "Evening")
        try await registry.save(first)
        try await registry.save(second)

        // Updating "Evening" to "Morning" should conflict
        var updated = second
        updated.name = "Morning"
        do {
            try await registry.update(updated)
            XCTFail("Expected RegistryError.duplicateName")
        } catch let error as RegistryError {
            guard case .duplicateName(let name) = error else {
                XCTFail("Expected RegistryError.duplicateName, got \(error)")
                return
            }
            XCTAssertEqual(name, "Morning")
        }
    }

    func testUpdateSameNameAllowed() async throws {
        setUpRegistry()
        defer { tearDownRegistry() }

        var automation = makeSampleAutomation(id: "id-1", name: "Morning")
        try await registry.save(automation)

        // Updating the same automation without changing its name should succeed
        automation.description = "Updated description"
        try await registry.update(automation)

        let found = try await registry.find("id-1")
        XCTAssertEqual(found?.description, "Updated description")
    }

    // MARK: - HVAC Mode Tests

    func testHvacModeValidInt() throws {
        // 0 (off), 1 (heat), 2 (cool), 3 (auto) are all valid
        for value in 0...3 {
            XCTAssertNoThrow(
                try validator.validateValueRange(characteristic: "hvacMode", value: .int(value)),
                "hvacMode \(value) should be valid"
            )
        }
    }

    func testHvacModeInvalidInt() throws {
        XCTAssertThrowsError(
            try validator.validateValueRange(characteristic: "hvacMode", value: .int(5))
        ) { error in
            guard case AutomationValidator.AutomationValidationError.valueOutOfRange(
                let characteristic, let value, _
            ) = error else {
                XCTFail("Expected .valueOutOfRange, got \(error)")
                return
            }
            XCTAssertEqual(characteristic, "hvacMode")
            XCTAssertEqual(value, "5")
        }
    }

    func testHvacModeValidStrings() throws {
        for alias in ["off", "heat", "cool", "auto"] {
            XCTAssertNoThrow(
                try validator.validateValueRange(characteristic: "hvacMode", value: .string(alias)),
                "hvacMode '\(alias)' should be valid"
            )
        }
    }

    func testHvacModeInvalidString() throws {
        XCTAssertThrowsError(
            try validator.validateValueRange(characteristic: "hvacMode", value: .string("turbo"))
        ) { error in
            guard case AutomationValidator.AutomationValidationError.valueOutOfRange = error else {
                XCTFail("Expected .valueOutOfRange, got \(error)")
                return
            }
        }
    }

    func testHvacModeInvalidType() throws {
        XCTAssertThrowsError(
            try validator.validateValueRange(characteristic: "hvacMode", value: .bool(true))
        ) { error in
            guard case AutomationValidator.AutomationValidationError.invalidValueType = error else {
                XCTFail("Expected .invalidValueType, got \(error)")
                return
            }
        }
    }

    // MARK: - Hue/Saturation Tests

    func testHueInRange() throws {
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "hue", value: .double(0.0))
        )
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "hue", value: .double(180.0))
        )
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "hue", value: .double(360.0))
        )
    }

    func testHueOutOfRange() throws {
        XCTAssertThrowsError(
            try validator.validateValueRange(characteristic: "hue", value: .double(361.0))
        ) { error in
            guard case AutomationValidator.AutomationValidationError.valueOutOfRange = error else {
                XCTFail("Expected .valueOutOfRange, got \(error)")
                return
            }
        }
    }

    func testHueNegative() throws {
        XCTAssertThrowsError(
            try validator.validateValueRange(characteristic: "hue", value: .double(-1.0))
        )
    }

    func testSaturationInRange() throws {
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "saturation", value: .double(50.0))
        )
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "saturation", value: .double(0.0))
        )
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "saturation", value: .double(100.0))
        )
    }

    func testSaturationOutOfRange() throws {
        XCTAssertThrowsError(
            try validator.validateValueRange(characteristic: "saturation", value: .double(101.0))
        )
    }

    // MARK: - Color Temperature Tests

    func testColorTemperatureInRange() throws {
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "colorTemperature", value: .int(50))
        )
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "colorTemperature", value: .int(200))
        )
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "colorTemperature", value: .int(400))
        )
    }

    func testColorTemperatureOutOfRange() throws {
        XCTAssertThrowsError(
            try validator.validateValueRange(characteristic: "colorTemperature", value: .int(401))
        ) { error in
            guard case AutomationValidator.AutomationValidationError.valueOutOfRange = error else {
                XCTFail("Expected .valueOutOfRange, got \(error)")
                return
            }
        }
        XCTAssertThrowsError(
            try validator.validateValueRange(characteristic: "colorTemperature", value: .int(49))
        )
    }

    // MARK: - Target Position Tests

    func testTargetPositionValidInt() throws {
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "targetPosition", value: .int(0))
        )
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "targetPosition", value: .int(50))
        )
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "targetPosition", value: .int(100))
        )
    }

    func testTargetPositionOutOfRange() throws {
        XCTAssertThrowsError(
            try validator.validateValueRange(characteristic: "targetPosition", value: .int(101))
        )
    }

    func testTargetPositionStringAliases() throws {
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "targetPosition", value: .string("open"))
        )
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "targetPosition", value: .string("closed"))
        )
    }

    func testTargetPositionInvalidString() throws {
        XCTAssertThrowsError(
            try validator.validateValueRange(characteristic: "targetPosition", value: .string("halfway"))
        )
    }

    // MARK: - Rotation/Swing Tests

    func testRotationDirectionValid() throws {
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "rotationDirection", value: .int(0))
        )
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "rotationDirection", value: .int(1))
        )
    }

    func testRotationDirectionInvalid() throws {
        XCTAssertThrowsError(
            try validator.validateValueRange(characteristic: "rotationDirection", value: .int(2))
        )
    }

    func testSwingModeValid() throws {
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "swingMode", value: .int(0))
        )
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "swingMode", value: .int(1))
        )
    }

    func testSwingModeInvalid() throws {
        XCTAssertThrowsError(
            try validator.validateValueRange(characteristic: "swingMode", value: .int(2))
        )
    }

    // MARK: - Rotation Speed / Target Humidity Tests

    func testRotationSpeedInRange() throws {
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "rotationSpeed", value: .double(50.0))
        )
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "rotationSpeed", value: .double(0.0))
        )
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "rotationSpeed", value: .double(100.0))
        )
    }

    func testRotationSpeedOutOfRange() throws {
        XCTAssertThrowsError(
            try validator.validateValueRange(characteristic: "rotationSpeed", value: .double(101.0))
        )
    }

    func testTargetHumidityInRange() throws {
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "targetHumidity", value: .double(45.0))
        )
    }

    func testTargetHumidityOutOfRange() throws {
        XCTAssertThrowsError(
            try validator.validateValueRange(characteristic: "targetHumidity", value: .double(101.0))
        )
    }

    // MARK: - Lock State (binaryOrStrings) Tests

    func testLockStateStringAliases() throws {
        for alias in ["locked", "unlocked", "on", "off"] {
            XCTAssertNoThrow(
                try validator.validateValueRange(characteristic: "lockState", value: .string(alias)),
                "lockState '\(alias)' should be valid"
            )
        }
    }

    func testLockStateInvalidString() throws {
        XCTAssertThrowsError(
            try validator.validateValueRange(characteristic: "lockState", value: .string("jammed"))
        )
    }

    func testLockStateBoolAccepted() throws {
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "lockState", value: .bool(true))
        )
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "lockState", value: .bool(false))
        )
    }

    // MARK: - Double Coercion for Int Range

    func testBrightnessDoubleCoercion() throws {
        // .double(50.0) should be accepted for brightness (intRange 0-100) when it's a whole number
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "brightness", value: .double(50.0))
        )
    }

    func testBrightnessDoubleCoercionOutOfRange() throws {
        XCTAssertThrowsError(
            try validator.validateValueRange(characteristic: "brightness", value: .double(150.0))
        )
    }

    // MARK: - Int coercion for Double Range

    func testHueIntCoercion() throws {
        // .int(180) should be accepted for hue (doubleRange 0-360) via int→double coercion
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "hue", value: .int(180))
        )
    }

    // MARK: - Power Boolean Edge Cases

    func testPowerIntZeroOneAccepted() throws {
        // 0 and 1 should be accepted for boolean power
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "power", value: .int(0))
        )
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "power", value: .int(1))
        )
    }

    func testPowerIntOutOfRange() throws {
        XCTAssertThrowsError(
            try validator.validateValueRange(characteristic: "power", value: .int(5))
        )
    }

    // MARK: - Unknown Characteristic Passthrough

    func testUnknownCharacteristicSkipsValidation() throws {
        // Unknown characteristics should pass validation (extensibility)
        XCTAssertNoThrow(
            try validator.validateValueRange(characteristic: "unknownFutureChar", value: .string("whatever"))
        )
    }

    // MARK: - Trigger Validation Tests

    func testValidateScheduleTrigger() throws {
        let trigger = AutomationTrigger(
            type: "schedule",
            humanReadable: "daily at 7 AM",
            cron: "0 7 * * *"
        )
        XCTAssertNoThrow(try validator.validateTrigger(trigger))
    }

    func testValidateScheduleTriggerInvalidCron() throws {
        let trigger = AutomationTrigger(
            type: "schedule",
            humanReadable: "bad cron",
            cron: "0 25 * * *"
        )
        XCTAssertThrowsError(try validator.validateTrigger(trigger)) { error in
            guard case AutomationValidator.AutomationValidationError.invalidCronExpression = error else {
                XCTFail("Expected .invalidCronExpression, got \(error)")
                return
            }
        }
    }

    func testValidateManualTriggerSkipsCron() throws {
        // Manual trigger has no cron — should pass without error
        let trigger = AutomationTrigger(
            type: "manual",
            humanReadable: "say 'goodnight'",
            keyword: "goodnight"
        )
        XCTAssertNoThrow(try validator.validateTrigger(trigger))
    }

    func testValidateSolarTriggerSkipsCron() throws {
        let trigger = AutomationTrigger(
            type: "solar",
            humanReadable: "at sunset",
            event: "sunset",
            offsetMinutes: 0
        )
        XCTAssertNoThrow(try validator.validateTrigger(trigger))
    }

    // MARK: - Levenshtein Distance Edge Cases

    func testLevenshteinIdenticalStrings() {
        XCTAssertEqual(validator.levenshteinDistance("hello", "hello"), 0)
    }

    func testLevenshteinEmptyVsNonEmpty() {
        XCTAssertEqual(validator.levenshteinDistance("", "abc"), 3)
        XCTAssertEqual(validator.levenshteinDistance("abc", ""), 3)
    }

    func testLevenshteinBothEmpty() {
        XCTAssertEqual(validator.levenshteinDistance("", ""), 0)
    }

    func testLevenshteinSingleCharDiff() {
        XCTAssertEqual(validator.levenshteinDistance("cat", "hat"), 1)
    }

    func testLevenshteinDifferentLengths() {
        XCTAssertEqual(validator.levenshteinDistance("kitten", "sitting"), 3)
    }

    // MARK: - Error Description Tests

    func testErrorDescriptionDeviceNotFound() {
        let error = AutomationValidator.AutomationValidationError.deviceNotFound(
            name: "Kitchen Light", suggestion: "Kitchen Lights"
        )
        let desc = error.errorDescription!
        XCTAssertTrue(desc.contains("Kitchen Light"))
        XCTAssertTrue(desc.contains("Kitchen Lights"))
        XCTAssertTrue(desc.contains("Did you mean"))
    }

    func testErrorDescriptionDeviceNotFoundNoSuggestion() {
        let error = AutomationValidator.AutomationValidationError.deviceNotFound(
            name: "Nonexistent", suggestion: nil
        )
        let desc = error.errorDescription!
        XCTAssertTrue(desc.contains("Nonexistent"))
        XCTAssertFalse(desc.contains("Did you mean"))
    }

    func testErrorDescriptionReadOnly() {
        let error = AutomationValidator.AutomationValidationError.readOnlyCharacteristic(
            characteristic: "currentTemperature", deviceName: "Thermostat"
        )
        let desc = error.errorDescription!
        XCTAssertTrue(desc.contains("currentTemperature"))
        XCTAssertTrue(desc.contains("read-only"))
    }

    func testErrorDescriptionUnsupported() {
        let error = AutomationValidator.AutomationValidationError.unsupportedCharacteristic(
            characteristic: "brightness", category: "lock", supported: ["lockState"]
        )
        let desc = error.errorDescription!
        XCTAssertTrue(desc.contains("brightness"))
        XCTAssertTrue(desc.contains("lock"))
        XCTAssertTrue(desc.contains("lockState"))
    }

    func testErrorDescriptionValueOutOfRange() {
        let error = AutomationValidator.AutomationValidationError.valueOutOfRange(
            characteristic: "brightness", value: "150", validRange: "0–100"
        )
        let desc = error.errorDescription!
        XCTAssertTrue(desc.contains("150"))
        XCTAssertTrue(desc.contains("0–100"))
    }

    func testErrorDescriptionInvalidValueType() {
        let error = AutomationValidator.AutomationValidationError.invalidValueType(
            characteristic: "power", expected: "boolean", got: "string"
        )
        let desc = error.errorDescription!
        XCTAssertTrue(desc.contains("boolean"))
        XCTAssertTrue(desc.contains("string"))
    }

    func testErrorDescriptionEmptyActions() {
        let error = AutomationValidator.AutomationValidationError.emptyActions
        XCTAssertTrue(error.errorDescription!.contains("at least one action"))
    }

    func testErrorDescriptionInvalidDelay() {
        let error = AutomationValidator.AutomationValidationError.invalidDelaySeconds(5000)
        let desc = error.errorDescription!
        XCTAssertTrue(desc.contains("5000"))
        XCTAssertTrue(desc.contains("0") && desc.contains("3600"))
    }

    // MARK: - extractDeviceMap Tests

    func testExtractDeviceMapFromArray() {
        let response = SocketClient.Response(
            id: "test-1",
            status: "ok",
            data: .array([
                .dictionary(["name": .string("Device 1"), "uuid": .string("uuid-1")]),
                .dictionary(["name": .string("Device 2"), "uuid": .string("uuid-2")])
            ]),
            error: nil
        )
        let devices = extractDeviceMap(from: response)
        XCTAssertEqual(devices.count, 2)
        XCTAssertEqual(devices[0]["name"]?.stringValue, "Device 1")
    }

    func testExtractDeviceMapFromDictionaryWithDevicesKey() {
        let response = SocketClient.Response(
            id: "test-2",
            status: "ok",
            data: .dictionary([
                "devices": .array([
                    .dictionary(["name": .string("Device A")])
                ])
            ]),
            error: nil
        )
        let devices = extractDeviceMap(from: response)
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices[0]["name"]?.stringValue, "Device A")
    }

    func testExtractDeviceMapFromNilData() {
        let response = SocketClient.Response(id: "test-3", status: "ok", data: nil, error: nil)
        let devices = extractDeviceMap(from: response)
        XCTAssertTrue(devices.isEmpty)
    }

    // MARK: - Cron Human Readable Additional Tests

    func testCronEveryNMinutes() {
        let desc = validator.humanReadableCron("*/15 * * * *")
        XCTAssertTrue(desc.contains("15"), "Should mention 15: \(desc)")
        XCTAssertTrue(desc.lowercased().contains("minute"), "Should mention minutes: \(desc)")
    }

    func testCronEveryNHours() {
        let desc = validator.humanReadableCron("0 */2 * * *")
        XCTAssertTrue(desc.contains("2"), "Should mention 2: \(desc)")
        XCTAssertTrue(desc.lowercased().contains("hour"), "Should mention hours: \(desc)")
    }

    func testCronWeekend() {
        let desc = validator.humanReadableCron("0 9 * * 0,6")
        XCTAssertTrue(desc.lowercased().contains("weekend"), "Should mention weekend: \(desc)")
    }

    func testCronSpecificDayOfMonth() {
        let desc = validator.humanReadableCron("0 8 1 * *")
        XCTAssertTrue(desc.contains("1"), "Should mention day 1: \(desc)")
        XCTAssertTrue(desc.lowercased().contains("month"), "Should mention month: \(desc)")
    }

    func testCronInvalidFieldCount() {
        let desc = validator.humanReadableCron("0 7")
        // Should fall through and return the original string
        XCTAssertEqual(desc, "0 7")
    }

    // MARK: - Full Definition Validation Tests

    func testValidateDefinitionEmptyActions() throws {
        let def = AutomationDefinition(
            name: "Empty",
            trigger: AutomationTrigger(type: "manual", humanReadable: "manual"),
            actions: []
        )
        XCTAssertThrowsError(try validator.validateDefinition(def, deviceMap: deviceMap)) { error in
            guard case AutomationValidator.AutomationValidationError.emptyActions = error else {
                XCTFail("Expected .emptyActions, got \(error)")
                return
            }
        }
    }

    func testValidateDefinitionInvalidDelay() throws {
        let def = AutomationDefinition(
            name: "Bad Delay",
            trigger: AutomationTrigger(type: "manual", humanReadable: "manual"),
            actions: [
                AutomationAction(
                    deviceUuid: "light-001",
                    deviceName: "Living Room Light",
                    characteristic: "power",
                    value: .bool(true),
                    delaySeconds: 5000
                )
            ]
        )
        XCTAssertThrowsError(try validator.validateDefinition(def, deviceMap: deviceMap)) { error in
            guard case AutomationValidator.AutomationValidationError.invalidDelaySeconds(let s) = error else {
                XCTFail("Expected .invalidDelaySeconds, got \(error)")
                return
            }
            XCTAssertEqual(s, 5000)
        }
    }

    func testValidateDefinitionSceneActionSkipped() throws {
        // Scene actions should skip device validation
        let def = AutomationDefinition(
            name: "Scene Test",
            trigger: AutomationTrigger(type: "manual", humanReadable: "manual"),
            actions: [
                AutomationAction(
                    type: "scene",
                    sceneName: "Good Night",
                    sceneUuid: "scene-001"
                )
            ]
        )
        XCTAssertNoThrow(try validator.validateDefinition(def, deviceMap: deviceMap))
    }
}
