// HomeAnalyzerTests.swift
// Tests for HomeAnalyzer suggestion generation and energy insights.
// swiftlint:disable type_body_length

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

    // MARK: - Energy Insights Edge Cases

    // swiftlint:disable:next line_length
    typealias RoomFixture = (name: String, accessories: [(name: String, category: String, characteristics: [(type: String, value: AnyCodableValue)])])

    func testEnergyInsightsManyActiveDevices() {
        // >5 active devices should trigger the "consider if they all need to be on" warning
        let rooms: [RoomFixture] = (1...7).map { i in
            (
                name: "Room \(i)",
                accessories: [
                    (name: "Light \(i)", category: "light", characteristics: [
                        (type: "power", value: .bool(true))
                    ])
                ]
            )
        }

        let deviceMap = makeDeviceMap(rooms: rooms)
        let analyzer = HomeAnalyzer(deviceMap: deviceMap, existingAutomations: [], focus: nil)
        let insights = analyzer.generateEnergyInsights(log: [], period: "last 24 hours")

        let devicesOn = insights["devicesCurrentlyOn"]?.arrayValue
        XCTAssertEqual(devicesOn?.count, 7)

        let insightStrings = insights["insights"]?.arrayValue?.compactMap { $0.stringValue } ?? []
        XCTAssertTrue(insightStrings.contains { $0.contains("7 devices currently active") },
                      "Should warn about many active devices: \(insightStrings)")
    }

    func testEnergyInsightsAllOff() {
        // All devices off → "great for energy savings"
        let deviceMap = makeDeviceMap(rooms: [
            (name: "Room 1", accessories: [
                (name: "Light 1", category: "light", characteristics: [
                    (type: "power", value: .bool(false))
                ])
            ])
        ])

        let analyzer = HomeAnalyzer(deviceMap: deviceMap, existingAutomations: [], focus: nil)
        let insights = analyzer.generateEnergyInsights(log: [], period: "today")

        let devicesOn = insights["devicesCurrentlyOn"]?.arrayValue
        XCTAssertEqual(devicesOn?.count, 0)

        let insightStrings = insights["insights"]?.arrayValue?.compactMap { $0.stringValue } ?? []
        XCTAssertTrue(insightStrings.contains { $0.contains("energy savings") },
                      "Should congratulate when all devices are off: \(insightStrings)")
    }

    func testEnergyInsightsEmptyLog() {
        let deviceMap = makeDeviceMap(rooms: [])
        let analyzer = HomeAnalyzer(deviceMap: deviceMap, existingAutomations: [], focus: nil)
        let insights = analyzer.generateEnergyInsights(log: [], period: "last 7 days")

        XCTAssertEqual(insights["automationRuns"]?.intValue, 0)
        XCTAssertEqual(insights["mostActiveAutomation"]?.stringValue, "none")
    }

    func testEnergyInsightsThermostatCooling() {
        // Test cooling mode detection (value = 2)
        let deviceMap = makeDeviceMap(rooms: [
            (name: "Living Room", accessories: [
                (name: "AC Unit", category: "thermostat", characteristics: [
                    (type: "currentHeatingCoolingState", value: .int(2))
                ])
            ])
        ])

        let analyzer = HomeAnalyzer(deviceMap: deviceMap, existingAutomations: [], focus: nil)
        let insights = analyzer.generateEnergyInsights(log: [], period: "today")

        let deviceNames = insights["devicesCurrentlyOn"]?.arrayValue?.compactMap { $0.stringValue } ?? []
        XCTAssertTrue(deviceNames.contains { $0.contains("cooling") },
                      "Should detect cooling mode: \(deviceNames)")
    }

    // MARK: - Suggestion Deduplication

    func testSuggestionsExcludeExisting() {
        // If an automation named "Auto-lock at Night" already exists, it should not be re-suggested
        let deviceMap = makeDeviceMap(rooms: [
            (name: "Entry", accessories: [
                (name: "Front Door Lock", category: "lock", characteristics: [])
            ])
        ])

        let existingAutomation = RegisteredAutomation(
            id: "existing-1",
            name: "Auto-lock at Night",
            description: "Already configured",
            trigger: AutomationTrigger(type: "schedule", humanReadable: "nightly", cron: "0 22 * * *"),
            conditions: nil,
            actions: [AutomationAction(deviceUuid: "dev-1", deviceName: "Lock", characteristic: "lockState", value: .int(1), delaySeconds: 0)],
            enabled: true,
            shortcutName: "HKA: Auto-lock at Night",
            createdAt: ISO8601DateFormatter().string(from: Date())
        )

        let analyzer = HomeAnalyzer(
            deviceMap: deviceMap,
            existingAutomations: [existingAutomation],
            focus: "security"
        )
        let suggestions = analyzer.generateSuggestions()

        // "Auto-lock at Night" should be filtered out since it already exists
        XCTAssertFalse(suggestions.contains { $0.name == "Auto-lock at Night" },
                       "Should not suggest automations that already exist")
    }

    // MARK: - Focus Filter

    func testFocusFilterReturnsOnlyCategory() {
        let deviceMap = makeDeviceMap(rooms: [
            (name: "Entry", accessories: [
                (name: "Lock", category: "lock", characteristics: [])
            ]),
            (name: "Living", accessories: [
                (name: "Thermostat", category: "thermostat", characteristics: []),
                (name: "Light", category: "light", characteristics: [])
            ])
        ])

        // With security focus, should not get comfort/convenience/energy suggestions
        let analyzer = HomeAnalyzer(deviceMap: deviceMap, existingAutomations: [], focus: "security")
        let suggestions = analyzer.generateSuggestions()
        XCTAssertTrue(suggestions.allSatisfy { $0.category == "security" },
                      "Security focus should only return security suggestions")
    }

    func testNilFocusReturnsAllCategories() {
        let deviceMap = makeDeviceMap(rooms: [
            (name: "Entry", accessories: [
                (name: "Lock", category: "lock", characteristics: [])
            ]),
            (name: "Living", accessories: [
                (name: "Thermostat", category: "thermostat", characteristics: []),
                (name: "Light", category: "light", characteristics: []),
                (name: "Sensor", category: "motionSensor", characteristics: [])
            ])
        ])

        let analyzer = HomeAnalyzer(deviceMap: deviceMap, existingAutomations: [], focus: nil)
        let suggestions = analyzer.generateSuggestions()

        // Without focus, should get suggestions from multiple categories
        let categories = Swift.Set(suggestions.map { $0.category })
        XCTAssertTrue(categories.count >= 2,
                      "Nil focus should return suggestions from multiple categories, got: \(categories)")
    }

    // MARK: - Seasonal Suggestion Tests

    func testSeasonalSuggestionsWithThermostats() {
        let deviceMap = makeDeviceMap(rooms: [
            (name: "Living Room", accessories: [
                (name: "Main Thermostat", category: "thermostat", characteristics: [])
            ])
        ])

        let analyzer = HomeAnalyzer(deviceMap: deviceMap, existingAutomations: [], focus: nil)
        let suggestions = analyzer.generateSeasonalSuggestions()

        // Should have at least one seasonal suggestion when thermostats are present
        XCTAssertFalse(suggestions.isEmpty, "Should generate seasonal suggestions with thermostats")

        // Verify season-appropriate suggestion exists based on current month
        let month = Calendar.current.component(.month, from: Date())
        switch month {
        case 12, 1, 2:
            XCTAssertTrue(suggestions.contains { $0.name == "Winter Heating Schedule" })
        case 3, 4, 5:
            XCTAssertTrue(suggestions.contains { $0.name == "Spring Ventilation Reminder" })
        case 6, 7, 8:
            XCTAssertTrue(suggestions.contains { $0.name == "Summer Cooling Schedule" })
        case 9, 10, 11:
            XCTAssertTrue(suggestions.contains { $0.name == "Fall Transition Schedule" })
        default:
            break
        }
    }

    func testSeasonalSuggestionsWithLights() {
        let deviceMap = makeDeviceMap(rooms: [
            (name: "Living Room", accessories: [
                (name: "Living Light", category: "light", characteristics: [])
            ])
        ])

        let analyzer = HomeAnalyzer(deviceMap: deviceMap, existingAutomations: [], focus: nil)
        let suggestions = analyzer.generateSeasonalSuggestions()

        let month = Calendar.current.component(.month, from: Date())
        switch month {
        case 12, 1, 2:
            XCTAssertTrue(suggestions.contains { $0.name == "Holiday Lighting" })
        case 9, 10, 11:
            XCTAssertTrue(suggestions.contains { $0.name == "Early Darkness Lights" })
        default:
            // Lights don't generate suggestions in spring/summer
            break
        }
    }

    func testSeasonalSuggestionsWithWindowCoverings() {
        let deviceMap = makeDeviceMap(rooms: [
            (name: "Bedroom", accessories: [
                (name: "Bedroom Blinds", category: "windowCovering", characteristics: [])
            ])
        ])

        let analyzer = HomeAnalyzer(deviceMap: deviceMap, existingAutomations: [], focus: nil)
        let suggestions = analyzer.generateSeasonalSuggestions()

        let month = Calendar.current.component(.month, from: Date())
        switch month {
        case 3, 4, 5:
            XCTAssertTrue(suggestions.contains { $0.name == "Allergy-Aware Windows" })
        case 6, 7, 8:
            XCTAssertTrue(suggestions.contains { $0.name == "Summer Shade Control" })
        default:
            // Window coverings don't generate suggestions in winter/fall
            break
        }
    }

    func testSeasonalSuggestionsDeduplication() {
        let deviceMap = makeDeviceMap(rooms: [
            (name: "Living Room", accessories: [
                (name: "Thermostat", category: "thermostat", characteristics: []),
                (name: "Light", category: "light", characteristics: []),
                (name: "Blinds", category: "windowCovering", characteristics: [])
            ])
        ])

        // Create existing automations that match all seasonal suggestion names
        let seasonalNames = [
            "Winter Heating Schedule", "Holiday Lighting",
            "Spring Ventilation Reminder", "Allergy-Aware Windows",
            "Summer Cooling Schedule", "Summer Shade Control",
            "Fall Transition Schedule", "Early Darkness Lights"
        ]
        let existingAutomations = seasonalNames.map { name in
            RegisteredAutomation(
                id: UUID().uuidString,
                name: name,
                trigger: AutomationTrigger(type: "manual", humanReadable: "manual"),
                conditions: nil,
                actions: [AutomationAction(deviceUuid: "dev-1", deviceName: "Dev", characteristic: "power", value: .bool(true), delaySeconds: 0)],
                enabled: true,
                shortcutName: "HKA: \(name)",
                createdAt: ISO8601DateFormatter().string(from: Date())
            )
        }

        let analyzer = HomeAnalyzer(deviceMap: deviceMap, existingAutomations: existingAutomations, focus: nil)
        let suggestions = analyzer.generateSeasonalSuggestions()

        XCTAssertTrue(suggestions.isEmpty, "Should not suggest automations that already exist, got: \(suggestions.map(\.name))")
    }

    func testSeasonalSuggestionsNoDevices() {
        let deviceMap = makeDeviceMap(rooms: [])

        let analyzer = HomeAnalyzer(deviceMap: deviceMap, existingAutomations: [], focus: nil)
        let suggestions = analyzer.generateSeasonalSuggestions()

        XCTAssertTrue(suggestions.isEmpty, "Should not suggest anything with no devices")
    }

    func testSeasonalSuggestionsNilDeviceMap() {
        let analyzer = HomeAnalyzer(deviceMap: nil, existingAutomations: [], focus: nil)
        let suggestions = analyzer.generateSeasonalSuggestions()

        XCTAssertTrue(suggestions.isEmpty, "Should return empty for nil device map")
    }

    // MARK: - Pattern Suggestion Tests

    func testPatternSuggestionsFrequentTrigger() {
        let formatter = ISO8601DateFormatter()
        let now = Date()

        // Create 10+ runs for "Morning Routine" → should suggest schedule optimization
        var logEntries: [AutomationLogEntry] = []
        for i in 0..<12 {
            logEntries.append(AutomationLogEntry(
                automationId: "auto-1",
                automationName: "Morning Routine",
                timestamp: formatter.string(from: now.addingTimeInterval(Double(-i * 3600))),
                actionsExecuted: 2,
                succeeded: 2,
                failed: 0,
                errors: nil
            ))
        }

        let analyzer = HomeAnalyzer(deviceMap: nil, existingAutomations: [], focus: nil)
        let suggestions = analyzer.generatePatternSuggestions(from: logEntries)

        XCTAssertTrue(
            suggestions.contains { $0.name == "Optimize Morning Routine Schedule" },
            "Should suggest optimizing frequently triggered automation, got: \(suggestions.map(\.name))"
        )

        let optimizeSuggestion = suggestions.first { $0.name == "Optimize Morning Routine Schedule" }
        XCTAssertEqual(optimizeSuggestion?.category, "energy")
    }

    func testPatternSuggestionsHighFailureRate() {
        let formatter = ISO8601DateFormatter()
        let now = Date()

        // Create entries with >30% failure rate and ≥3 runs
        let logEntries = (0..<5).map { i in
            AutomationLogEntry(
                automationId: "auto-2",
                automationName: "Flaky Automation",
                timestamp: formatter.string(from: now.addingTimeInterval(Double(-i * 3600))),
                actionsExecuted: 3,
                succeeded: 2,
                failed: 1,  // 1 failure per run → 100% failure ratio (5 fails / 5 runs)
                errors: ["Device unreachable"]
            )
        }

        let analyzer = HomeAnalyzer(deviceMap: nil, existingAutomations: [], focus: nil)
        let suggestions = analyzer.generatePatternSuggestions(from: logEntries)

        XCTAssertTrue(
            suggestions.contains { $0.name == "Troubleshoot Flaky Automation" },
            "Should suggest troubleshooting high-failure automation, got: \(suggestions.map(\.name))"
        )

        let troubleshoot = suggestions.first { $0.name == "Troubleshoot Flaky Automation" }
        XCTAssertEqual(troubleshoot?.category, "convenience")
    }

    func testPatternSuggestionsTimeOfDay() {
        let formatter = ISO8601DateFormatter()
        let calendar = Calendar.current

        // Create 6 entries, 4+ at 8 AM (>50% at same hour with ≥5 entries)
        var logEntries: [AutomationLogEntry] = []
        let baseDate = calendar.startOfDay(for: Date())

        for i in 0..<5 {
            // 8 AM entry
            let date8am = calendar.date(byAdding: .day, value: -i, to:
                calendar.date(bySettingHour: 8, minute: 0, second: 0, of: baseDate)!)!
            logEntries.append(AutomationLogEntry(
                automationId: "auto-3",
                automationName: "Consistent Task",
                timestamp: formatter.string(from: date8am),
                actionsExecuted: 1,
                succeeded: 1,
                failed: 0,
                errors: nil
            ))
        }
        // Add 1 entry at a different hour
        let date3pm = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: baseDate)!
        logEntries.append(AutomationLogEntry(
            automationId: "auto-3",
            automationName: "Consistent Task",
            timestamp: formatter.string(from: date3pm),
            actionsExecuted: 1,
            succeeded: 1,
            failed: 0,
            errors: nil
        ))

        let analyzer = HomeAnalyzer(deviceMap: nil, existingAutomations: [], focus: nil)
        let suggestions = analyzer.generatePatternSuggestions(from: logEntries)

        XCTAssertTrue(
            suggestions.contains { $0.name.hasPrefix("Schedule Consistent Task at") },
            "Should suggest scheduling at peak hour, got: \(suggestions.map(\.name))"
        )
    }

    func testPatternSuggestionsEmptyLog() {
        let analyzer = HomeAnalyzer(deviceMap: nil, existingAutomations: [], focus: nil)
        let suggestions = analyzer.generatePatternSuggestions(from: [])

        XCTAssertTrue(suggestions.isEmpty, "Empty log should produce no suggestions")
    }

    func testPatternSuggestionsDeduplication() {
        let formatter = ISO8601DateFormatter()
        let now = Date()

        // Create frequent runs
        var logEntries: [AutomationLogEntry] = []
        for i in 0..<15 {
            logEntries.append(AutomationLogEntry(
                automationId: "auto-1",
                automationName: "Morning Routine",
                timestamp: formatter.string(from: now.addingTimeInterval(Double(-i * 3600))),
                actionsExecuted: 2,
                succeeded: 2,
                failed: 0,
                errors: nil
            ))
        }

        // Existing automation with the exact suggestion name
        let existing = RegisteredAutomation(
            id: "existing-1",
            name: "Optimize Morning Routine Schedule",
            trigger: AutomationTrigger(type: "manual", humanReadable: "manual"),
            conditions: nil,
            actions: [AutomationAction(deviceUuid: "dev-1", deviceName: "Dev", characteristic: "power", value: .bool(true), delaySeconds: 0)],
            enabled: true,
            shortcutName: "HKA: Optimize Morning Routine Schedule",
            createdAt: ISO8601DateFormatter().string(from: Date())
        )

        let analyzer = HomeAnalyzer(deviceMap: nil, existingAutomations: [existing], focus: nil)
        let suggestions = analyzer.generatePatternSuggestions(from: logEntries)

        XCTAssertFalse(
            suggestions.contains { $0.name == "Optimize Morning Routine Schedule" },
            "Should not suggest if already exists"
        )
    }

    func testPatternSuggestionsBelowThresholds() {
        let formatter = ISO8601DateFormatter()
        let now = Date()

        // Only 5 runs (below ≥10 threshold for frequency suggestion)
        // 0 failures (below >30% failure threshold)
        let logEntries = (0..<5).map { i in
            AutomationLogEntry(
                automationId: "auto-1",
                automationName: "Infrequent",
                timestamp: formatter.string(from: now.addingTimeInterval(Double(-i * 86400))),
                actionsExecuted: 1,
                succeeded: 1,
                failed: 0,
                errors: nil
            )
        }

        let analyzer = HomeAnalyzer(deviceMap: nil, existingAutomations: [], focus: nil)
        let suggestions = analyzer.generatePatternSuggestions(from: logEntries)

        XCTAssertFalse(
            suggestions.contains { $0.name.hasPrefix("Optimize") },
            "Should not suggest optimization for <10 runs"
        )
        XCTAssertFalse(
            suggestions.contains { $0.name.hasPrefix("Troubleshoot") },
            "Should not suggest troubleshooting for 0% failure rate"
        )
    }
}
