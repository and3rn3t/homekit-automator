// HomeAnalyzerTests.swift
// Tests for HomeAnalyzer suggestion generation and energy insights.

import XCTest
@testable import homekitauto

final class HomeAnalyzerTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a mock device map matching the HomeKit discovery format:
    /// `{ "homes": [{ "rooms": [{ "name": ..., "accessories": [...] }] }] }`
    private func makeDeviceMap(
        rooms: [(name: String, accessories: [(name: String, category: String, characteristics: [(type: String, value: AnyCodableValue)])])]
    ) -> AnyCodableValue {
        let roomValues: [AnyCodableValue] = rooms.map { room in
            let accessoryValues: [AnyCodableValue] = room.accessories.map { acc in
                let charValues: [AnyCodableValue] = acc.characteristics.map { char in
                    .dictionary([
                        "type": .string(char.type),
                        "value": char.value
                    ])
                }
                return .dictionary([
                    "name": .string(acc.name),
                    "category": .string(acc.category),
                    "characteristics": .array(charValues)
                ])
            }
            return .dictionary([
                "name": .string(room.name),
                "accessories": .array(accessoryValues)
            ])
        }

        return .dictionary([
            "homes": .array([
                .dictionary([
                    "rooms": .array(roomValues)
                ])
            ])
        ])
    }

    // MARK: - Suggestion Tests

    func testSecuritySuggestions() {
        let deviceMap = makeDeviceMap(rooms: [
            (name: "Entry", accessories: [
                (name: "Front Door Lock", category: "lock", characteristics: []),
                (name: "Back Door Lock", category: "lock", characteristics: [])
            ]),
            (name: "Garage", accessories: [
                (name: "Garage Door", category: "garageDoorOpener", characteristics: [])
            ])
        ])

        let analyzer = HomeAnalyzer(deviceMap: deviceMap, existingAutomations: [], focus: "security")
        let suggestions = analyzer.generateSuggestions()

        XCTAssertFalse(suggestions.isEmpty)
        XCTAssertTrue(suggestions.allSatisfy { $0.category == "security" })

        // Should suggest auto-lock (2 locks) and garage close
        XCTAssertTrue(suggestions.contains { $0.name == "Auto-lock at Night" })
        XCTAssertTrue(suggestions.contains { $0.name == "Close Garage at Night" })

        // Verify lock suggestion mentions both locks
        let lockSuggestion = suggestions.first { $0.name == "Auto-lock at Night" }
        XCTAssertNotNil(lockSuggestion)
        XCTAssertEqual(lockSuggestion?.actions.count, 2)
        XCTAssertTrue(lockSuggestion?.reason.contains("2 smart lock") ?? false)
    }

    func testComfortSuggestions() {
        let deviceMap = makeDeviceMap(rooms: [
            (name: "Living Room", accessories: [
                (name: "Main Thermostat", category: "thermostat", characteristics: [])
            ]),
            (name: "Bedroom", accessories: [
                (name: "Bedroom Thermostat", category: "thermostat", characteristics: [])
            ])
        ])

        let analyzer = HomeAnalyzer(deviceMap: deviceMap, existingAutomations: [], focus: "comfort")
        let suggestions = analyzer.generateSuggestions()

        XCTAssertFalse(suggestions.isEmpty)
        XCTAssertTrue(suggestions.allSatisfy { $0.category == "comfort" })
        XCTAssertTrue(suggestions.contains { $0.name == "Morning Warmup" })
        XCTAssertTrue(suggestions.contains { $0.name == "Sleep Temperature" })

        // Verify warmup has actions for both thermostats
        let warmup = suggestions.first { $0.name == "Morning Warmup" }
        XCTAssertEqual(warmup?.actions.count, 2)
        XCTAssertEqual(warmup?.trigger, "weekdays at 6:30 AM")
    }

    func testConvenienceSuggestions() {
        let deviceMap = makeDeviceMap(rooms: [
            (name: "Hallway", accessories: [
                (name: "Hallway Sensor", category: "motionSensor", characteristics: []),
                (name: "Hallway Light", category: "light", characteristics: [])
            ]),
            (name: "Kitchen", accessories: [
                (name: "Kitchen Light", category: "light", characteristics: [])
            ]),
            (name: "Bedroom", accessories: [
                (name: "Bedroom Light", category: "light", characteristics: [])
            ])
        ])

        let analyzer = HomeAnalyzer(deviceMap: deviceMap, existingAutomations: [], focus: "convenience")
        let suggestions = analyzer.generateSuggestions()

        XCTAssertFalse(suggestions.isEmpty)
        XCTAssertTrue(suggestions.allSatisfy { $0.category == "convenience" })

        // Should suggest motion-activated hallway lights
        XCTAssertTrue(suggestions.contains { $0.name == "Motion-Activated Hallway Lights" })

        // Should suggest all lights off (3 lights total)
        XCTAssertTrue(suggestions.contains { $0.name == "All Lights Off" })

        // Verify motion suggestion uses the sensor and room lights
        let motionSuggestion = suggestions.first { $0.name == "Motion-Activated Hallway Lights" }
        XCTAssertNotNil(motionSuggestion)
        XCTAssertTrue(motionSuggestion?.trigger.contains("Hallway Sensor") ?? false)
    }

    func testEnergySuggestions() {
        let deviceMap = makeDeviceMap(rooms: [
            (name: "Living Room", accessories: [
                (name: "Thermostat", category: "thermostat", characteristics: []),
                (name: "Living Light", category: "light", characteristics: [])
            ]),
            (name: "Entry", accessories: [
                (name: "Front Lock", category: "lock", characteristics: [])
            ])
        ])

        let analyzer = HomeAnalyzer(deviceMap: deviceMap, existingAutomations: [], focus: "energy")
        let suggestions = analyzer.generateSuggestions()

        XCTAssertFalse(suggestions.isEmpty)
        XCTAssertTrue(suggestions.allSatisfy { $0.category == "energy" })
        XCTAssertTrue(suggestions.contains { $0.name == "Away Mode" })

        // Away mode should combine thermostat, light, and lock actions
        let awayMode = suggestions.first { $0.name == "Away Mode" }
        XCTAssertNotNil(awayMode)
        // thermostat eco + light off + lock locked = 3 actions
        XCTAssertEqual(awayMode?.actions.count, 3)
    }

    func testNoDevicesNoSuggestions() {
        // Empty device map with no rooms/accessories
        let emptyMap = makeDeviceMap(rooms: [])

        let analyzer = HomeAnalyzer(deviceMap: emptyMap, existingAutomations: [], focus: nil)
        let suggestions = analyzer.generateSuggestions()

        XCTAssertTrue(suggestions.isEmpty)
    }

    // MARK: - Energy Insights Tests

    func testEnergyInsights() {
        let deviceMap = makeDeviceMap(rooms: [
            (name: "Kitchen", accessories: [
                (name: "Kitchen Light", category: "light", characteristics: [
                    (type: "power", value: .bool(true))
                ])
            ]),
            (name: "Living Room", accessories: [
                (name: "Main Thermostat", category: "thermostat", characteristics: [
                    (type: "currentHeatingCoolingState", value: .int(1))
                ])
            ]),
            (name: "Bedroom", accessories: [
                (name: "Bedroom Light", category: "light", characteristics: [
                    (type: "power", value: .bool(false))
                ])
            ])
        ])

        let formatter = ISO8601DateFormatter()
        let now = Date()
        let logEntries = [
            AutomationLogEntry(
                automationId: "auto-1",
                automationName: "Morning Routine",
                timestamp: formatter.string(from: now),
                actionsExecuted: 3,
                succeeded: 3,
                failed: 0,
                errors: nil
            ),
            AutomationLogEntry(
                automationId: "auto-1",
                automationName: "Morning Routine",
                timestamp: formatter.string(from: now),
                actionsExecuted: 3,
                succeeded: 3,
                failed: 0,
                errors: nil
            ),
            AutomationLogEntry(
                automationId: "auto-2",
                automationName: "Night Lock",
                timestamp: formatter.string(from: now),
                actionsExecuted: 1,
                succeeded: 1,
                failed: 0,
                errors: nil
            ),
        ]

        let analyzer = HomeAnalyzer(deviceMap: deviceMap, existingAutomations: [], focus: nil)
        let insights = analyzer.generateEnergyInsights(log: logEntries, period: "last 7 days")

        // Verify period
        XCTAssertEqual(insights["period"]?.stringValue, "last 7 days")

        // Verify automation run count
        XCTAssertEqual(insights["automationRuns"]?.intValue, 3)

        // Verify most active automation
        let mostActive = insights["mostActiveAutomation"]?.stringValue
        XCTAssertNotNil(mostActive)
        XCTAssertTrue(mostActive?.contains("Morning Routine") ?? false)
        XCTAssertTrue(mostActive?.contains("2 runs") ?? false)

        // Verify devices currently on
        let devicesOn = insights["devicesCurrentlyOn"]?.arrayValue
        XCTAssertNotNil(devicesOn)
        // Kitchen Light (power=true) and Main Thermostat (heating state=1) should be on
        XCTAssertEqual(devicesOn?.count, 2)

        let deviceNames = devicesOn?.compactMap { $0.stringValue } ?? []
        XCTAssertTrue(deviceNames.contains { $0.contains("Kitchen Light") })
        XCTAssertTrue(deviceNames.contains { $0.contains("Main Thermostat") })

        // Verify insights array exists
        XCTAssertNotNil(insights["insights"]?.arrayValue)
    }
}
