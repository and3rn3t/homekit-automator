// EnergyHistoryTests.swift
// Tests for the generateEnergyHistory function in IntelligenceCommands.

import XCTest
@testable import homekitauto
import HomeKitCore

final class EnergyHistoryTests: XCTestCase {

    // MARK: - Helpers

    private let formatter = ISO8601DateFormatter()

    private func makeAutomation(
        name: String,
        actions: [AutomationAction]
    ) -> RegisteredAutomation {
        RegisteredAutomation(
            id: UUID().uuidString,
            name: name,
            trigger: AutomationTrigger(type: "manual", humanReadable: "manual"),
            conditions: nil,
            actions: actions,
            enabled: true,
            shortcutName: "HKA: \(name)",
            createdAt: formatter.string(from: Date())
        )
    }

    private func makeLogEntry(
        name: String,
        daysAgo: Int = 0,
        hour: Int = 12
    ) -> AutomationLogEntry {
        let date = Calendar.current.date(
            bySettingHour: hour, minute: 0, second: 0,
            of: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        )!
        return AutomationLogEntry(
            automationId: UUID().uuidString,
            automationName: name,
            timestamp: formatter.string(from: date),
            actionsExecuted: 1,
            succeeded: 1,
            failed: 0,
            errors: nil
        )
    }

    private func makeDeviceMap(
        devices: [(name: String, category: String)]
    ) -> AnyCodableValue {
        let accessories: [AnyCodableValue] = devices.map { device in
            .dictionary([
                "name": .string(device.name),
                "category": .string(device.category)
            ])
        }
        return .dictionary([
            "homes": .array([
                .dictionary([
                    "rooms": .array([
                        .dictionary([
                            "name": .string("Main"),
                            "accessories": .array(accessories)
                        ])
                    ])
                ])
            ])
        ])
    }

    // MARK: - Tests

    func testEnergyRelatedAutomationsDetected() {
        let energy = Energy()
        let automations = [
            makeAutomation(name: "Lights On", actions: [
                AutomationAction(deviceUuid: "dev-1", deviceName: "Light", characteristic: "power", value: .bool(true), delaySeconds: 0)
            ]),
            makeAutomation(name: "Temp Up", actions: [
                AutomationAction(deviceUuid: "dev-2", deviceName: "Therm", characteristic: "targetTemperature", value: .double(72.0), delaySeconds: 0)
            ]),
            makeAutomation(name: "Lock Door", actions: [
                AutomationAction(deviceUuid: "dev-3", deviceName: "Lock", characteristic: "lockState", value: .int(1), delaySeconds: 0)
            ])
        ]

        let result = energy.generateEnergyHistory(log: [], automations: automations, deviceMap: nil)

        let related = result["energyRelatedAutomations"]?.arrayValue?.compactMap { $0.stringValue } ?? []
        XCTAssertTrue(related.contains("Lights On"), "Power characteristic should be energy-related")
        XCTAssertTrue(related.contains("Temp Up"), "targetTemperature should be energy-related")
        XCTAssertFalse(related.contains("Lock Door"), "lockState should NOT be energy-related")
    }

    func testWeekOverWeekChangeCalculated() {
        let energy = Energy()

        // 5 runs this week, 3 runs last week → +66%
        var log: [AutomationLogEntry] = []
        for i in 0..<5 {
            log.append(makeLogEntry(name: "Auto", daysAgo: i))
        }
        for i in 8..<11 {
            log.append(makeLogEntry(name: "Auto", daysAgo: i))
        }

        let automations = [
            makeAutomation(name: "Auto", actions: [
                AutomationAction(deviceUuid: "dev-1", deviceName: "Light", characteristic: "power", value: .bool(true), delaySeconds: 0)
            ])
        ]

        let result = energy.generateEnergyHistory(log: log, automations: automations, deviceMap: nil)

        let change = result["weekOverWeekChange"]?.stringValue ?? ""
        XCTAssertTrue(change.contains("->"), "Should show run count transition: \(change)")
    }

    func testWeekOverWeekNoPreviousData() {
        let energy = Energy()

        // Only this week runs, no last week data
        let log = [makeLogEntry(name: "Auto", daysAgo: 0)]
        let automations = [
            makeAutomation(name: "Auto", actions: [
                AutomationAction(deviceUuid: "dev-1", deviceName: "Light", characteristic: "power", value: .bool(true), delaySeconds: 0)
            ])
        ]

        let result = energy.generateEnergyHistory(log: log, automations: automations, deviceMap: nil)

        let change = result["weekOverWeekChange"]?.stringValue ?? ""
        XCTAssertTrue(change.contains("No data"), "Should indicate no previous week data: \(change)")
    }

    func testPeakUsageHours() {
        let energy = Energy()

        // Create entries at specific hours: 3 at 8AM, 2 at 9AM, 1 at 14PM
        var log: [AutomationLogEntry] = []
        for _ in 0..<3 { log.append(makeLogEntry(name: "Auto", daysAgo: 0, hour: 8)) }
        for _ in 0..<2 { log.append(makeLogEntry(name: "Auto", daysAgo: 0, hour: 9)) }
        log.append(makeLogEntry(name: "Auto", daysAgo: 0, hour: 14))

        let automations = [
            makeAutomation(name: "Auto", actions: [
                AutomationAction(deviceUuid: "dev-1", deviceName: "Light", characteristic: "power", value: .bool(true), delaySeconds: 0)
            ])
        ]

        let result = energy.generateEnergyHistory(log: log, automations: automations, deviceMap: nil)

        let peakHours = result["peakUsageHours"]?.arrayValue?.compactMap { $0.stringValue } ?? []
        XCTAssertFalse(peakHours.isEmpty, "Should have peak usage hours")
        // First peak should be 8 AM (most runs)
        XCTAssertTrue(peakHours[0].contains("AM"), "Peak should be in AM: \(peakHours[0])")
        XCTAssertTrue(peakHours[0].contains("3 runs"), "Peak should show 3 runs: \(peakHours[0])")
    }

    func testDeviceEnergyEstimates() {
        let energy = Energy()

        let deviceMap = makeDeviceMap(devices: [
            ("Kitchen Light", "light"),
            ("Smart Plug", "outlet")
        ])

        let automations = [
            makeAutomation(name: "Lights On", actions: [
                AutomationAction(deviceUuid: "dev-1", deviceName: "Kitchen Light", characteristic: "power", value: .bool(true), delaySeconds: 0)
            ]),
            makeAutomation(name: "Plug On", actions: [
                AutomationAction(deviceUuid: "dev-2", deviceName: "Smart Plug", characteristic: "power", value: .bool(true), delaySeconds: 0)
            ])
        ]

        // 2 runs for each automation
        let log = [
            makeLogEntry(name: "Lights On", daysAgo: 0),
            makeLogEntry(name: "Lights On", daysAgo: 1),
            makeLogEntry(name: "Plug On", daysAgo: 0),
            makeLogEntry(name: "Plug On", daysAgo: 1)
        ]

        let result = energy.generateEnergyHistory(log: log, automations: automations, deviceMap: deviceMap)

        let estimates = result["deviceEnergyEstimates"]?.arrayValue ?? []
        XCTAssertFalse(estimates.isEmpty, "Should have device energy estimates")

        // Find the light estimate
        let lightEstimate = estimates.first { $0.dictionaryValue?["device"]?.stringValue == "Kitchen Light" }
        XCTAssertNotNil(lightEstimate, "Should have an estimate for Kitchen Light")
        XCTAssertEqual(lightEstimate?.dictionaryValue?["category"]?.stringValue, "light")

        // Find the outlet estimate  
        let plugEstimate = estimates.first { $0.dictionaryValue?["device"]?.stringValue == "Smart Plug" }
        XCTAssertNotNil(plugEstimate, "Should have an estimate for Smart Plug")
        XCTAssertEqual(plugEstimate?.dictionaryValue?["category"]?.stringValue, "outlet")
    }

    func testEmptyLogReturnsDefaults() {
        let energy = Energy()

        let result = energy.generateEnergyHistory(log: [], automations: [], deviceMap: nil)

        let related = result["energyRelatedAutomations"]?.arrayValue ?? []
        XCTAssertTrue(related.isEmpty, "No automations → no energy-related automations")

        let peakHours = result["peakUsageHours"]?.arrayValue ?? []
        XCTAssertTrue(peakHours.isEmpty, "No log → no peak hours")

        let estimates = result["deviceEnergyEstimates"]?.arrayValue ?? []
        XCTAssertTrue(estimates.isEmpty, "No automations → no estimates")
    }

    func testSceneActionsAreEnergyRelated() {
        let energy = Energy()

        let automations = [
            makeAutomation(name: "Night Scene", actions: [
                AutomationAction(type: "scene", sceneName: "Good Night", sceneUuid: "scene-1")
            ])
        ]

        let result = energy.generateEnergyHistory(log: [], automations: automations, deviceMap: nil)

        let related = result["energyRelatedAutomations"]?.arrayValue?.compactMap { $0.stringValue } ?? []
        XCTAssertTrue(related.contains("Night Scene"), "Scene actions should be energy-related")
    }
}
