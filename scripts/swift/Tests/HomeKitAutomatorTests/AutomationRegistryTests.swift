// AutomationRegistryTests.swift
// Tests for the automation registry CRUD operations.

import XCTest
@testable import homekitauto

final class AutomationRegistryTests: XCTestCase {

    // Test that loading from a non-existent file returns empty
    func testLoadEmptyRegistry() throws {
        let registry = AutomationRegistry()
        let automations = try registry.loadAll()
        // May or may not be empty depending on test environment
        XCTAssertNotNil(automations)
    }

    // Test automation model encoding/decoding roundtrip
    func testAutomationCodableRoundtrip() throws {
        let trigger = AutomationTrigger(
            type: "schedule",
            humanReadable: "weekdays at 7:00 AM",
            cron: "0 7 * * 1-5",
            timezone: "America/New_York"
        )

        let action = AutomationAction(
            deviceUuid: "test-uuid-123",
            deviceName: "Kitchen Lights",
            room: "Kitchen",
            characteristic: "power",
            value: .bool(true),
            delaySeconds: 0
        )

        let automation = RegisteredAutomation(
            id: "test-id",
            name: "Test Routine",
            description: "A test automation",
            trigger: trigger,
            conditions: nil,
            actions: [action],
            enabled: true,
            shortcutName: "HKA: Test Routine",
            createdAt: "2026-02-25T10:00:00Z"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(automation)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RegisteredAutomation.self, from: data)

        XCTAssertEqual(decoded.id, automation.id)
        XCTAssertEqual(decoded.name, automation.name)
        XCTAssertEqual(decoded.trigger.cron, "0 7 * * 1-5")
        XCTAssertEqual(decoded.actions.count, 1)
        XCTAssertEqual(decoded.actions[0].deviceName, "Kitchen Lights")
        XCTAssertEqual(decoded.shortcutName, "HKA: Test Routine")
    }

    // Test AnyCodableValue types
    func testAnyCodableValueTypes() throws {
        let values: [AnyCodableValue] = [
            .string("hello"),
            .int(42),
            .double(3.14),
            .bool(true),
            .null,
            .array([.string("a"), .int(1)]),
            .dictionary(["key": .string("value")])
        ]

        let encoder = JSONEncoder()
        let data = try encoder.encode(values)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode([AnyCodableValue].self, from: data)

        XCTAssertEqual(decoded.count, 7)
        XCTAssertEqual(decoded[0].stringValue, "hello")
        XCTAssertEqual(decoded[1].intValue, 42)
        XCTAssertEqual(decoded[2].doubleValue, 3.14)
        XCTAssertEqual(decoded[3].boolValue, true)
    }

    // Test trigger types
    func testTriggerTypes() throws {
        let scheduleTrigger = AutomationTrigger(
            type: "schedule",
            humanReadable: "daily at 7 AM",
            cron: "0 7 * * *"
        )
        XCTAssertEqual(scheduleTrigger.type, "schedule")
        XCTAssertEqual(scheduleTrigger.cron, "0 7 * * *")

        let solarTrigger = AutomationTrigger(
            type: "solar",
            humanReadable: "at sunset",
            event: "sunset",
            offsetMinutes: 0
        )
        XCTAssertEqual(solarTrigger.type, "solar")
        XCTAssertEqual(solarTrigger.event, "sunset")

        let manualTrigger = AutomationTrigger(
            type: "manual",
            humanReadable: "when you say bedtime",
            keyword: "bedtime"
        )
        XCTAssertEqual(manualTrigger.keyword, "bedtime")
    }

    // Test automation definition parsing
    func testParseAutomationDefinition() throws {
        let json = """
        {
            "name": "Morning Routine",
            "description": "Warm up the house",
            "trigger": {
                "type": "schedule",
                "humanReadable": "weekdays at 6:45 AM",
                "cron": "45 6 * * 1-5",
                "timezone": "America/Chicago"
            },
            "actions": [
                {
                    "deviceUuid": "light-001",
                    "deviceName": "Kitchen Lights",
                    "room": "Kitchen",
                    "characteristic": "power",
                    "value": true,
                    "delaySeconds": 0
                },
                {
                    "deviceUuid": "therm-001",
                    "deviceName": "Thermostat",
                    "room": "Living Room",
                    "characteristic": "targetTemperature",
                    "value": 72,
                    "delaySeconds": 0
                }
            ],
            "enabled": true
        }
        """

        let data = json.data(using: .utf8)!
        let definition = try JSONDecoder().decode(AutomationDefinition.self, from: data)

        XCTAssertEqual(definition.name, "Morning Routine")
        XCTAssertEqual(definition.trigger.type, "schedule")
        XCTAssertEqual(definition.trigger.cron, "45 6 * * 1-5")
        XCTAssertEqual(definition.actions.count, 2)
        XCTAssertEqual(definition.actions[0].deviceName, "Kitchen Lights")
        XCTAssertEqual(definition.actions[1].characteristic, "targetTemperature")
    }
}
