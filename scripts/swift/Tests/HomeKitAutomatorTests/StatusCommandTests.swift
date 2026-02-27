// StatusCommandTests.swift
// Tests for the Status command's formatting logic (extracted as a static function).

import XCTest
@testable import homekitauto
import HomeKitCore

final class StatusCommandTests: XCTestCase {

    // MARK: - formatStatusReport

    func testFormatStatusReportConnected() {
        let data: AnyCodableValue = .dictionary([
            "connected": .bool(true),
            "homes": .array([
                .dictionary([
                    "name": .string("My Home"),
                    "accessoryCount": .int(12)
                ])
            ]),
            "automationCount": .int(3)
        ])

        let report = Status.formatStatusReport(data)

        XCTAssertTrue(report.contains("HomeKit Automator Status"))
        XCTAssertTrue(report.contains("Bridge: Connected"))
        XCTAssertTrue(report.contains("Homes: 1"))
        XCTAssertTrue(report.contains("  - My Home (12 accessories)"))
        XCTAssertTrue(report.contains("Automations: 3"))
    }

    func testFormatStatusReportDisconnected() {
        let data: AnyCodableValue = .dictionary([
            "connected": .bool(false)
        ])

        let report = Status.formatStatusReport(data)

        XCTAssertTrue(report.contains("Bridge: Disconnected"))
        XCTAssertFalse(report.contains("Homes:"))
    }

    func testFormatStatusReportMultipleHomes() {
        let data: AnyCodableValue = .dictionary([
            "connected": .bool(true),
            "homes": .array([
                .dictionary(["name": .string("Home"), "accessoryCount": .int(5)]),
                .dictionary(["name": .string("Office"), "accessoryCount": .int(8)]),
                .dictionary(["name": .string("Cabin"), "accessoryCount": .int(2)])
            ])
        ])

        let report = Status.formatStatusReport(data)

        XCTAssertTrue(report.contains("Homes: 3"))
        XCTAssertTrue(report.contains("  - Home (5 accessories)"))
        XCTAssertTrue(report.contains("  - Office (8 accessories)"))
        XCTAssertTrue(report.contains("  - Cabin (2 accessories)"))
    }

    func testFormatStatusReportEmptyHomes() {
        let data: AnyCodableValue = .dictionary([
            "connected": .bool(true),
            "homes": .array([])
        ])

        let report = Status.formatStatusReport(data)

        XCTAssertTrue(report.contains("Homes: 0"))
        XCTAssertFalse(report.contains("  - "))
    }

    func testFormatStatusReportNilData() {
        let report = Status.formatStatusReport(nil)

        // Should still show the header
        XCTAssertTrue(report.contains("HomeKit Automator Status"))
        XCTAssertTrue(report.contains("========================"))
        // But no data fields
        XCTAssertFalse(report.contains("Bridge:"))
        XCTAssertFalse(report.contains("Homes:"))
    }

    func testFormatStatusReportNullData() {
        let report = Status.formatStatusReport(.null)

        XCTAssertTrue(report.contains("HomeKit Automator Status"))
        XCTAssertFalse(report.contains("Bridge:"))
    }

    func testFormatStatusReportZeroAutomations() {
        let data: AnyCodableValue = .dictionary([
            "automationCount": .int(0)
        ])

        let report = Status.formatStatusReport(data)

        XCTAssertTrue(report.contains("Automations: 0"))
    }

    func testFormatStatusReportPartialData() {
        // Only connected field, no homes or automations
        let data: AnyCodableValue = .dictionary([
            "connected": .bool(true)
        ])

        let report = Status.formatStatusReport(data)

        XCTAssertTrue(report.contains("Bridge: Connected"))
        XCTAssertFalse(report.contains("Homes:"))
        XCTAssertFalse(report.contains("Automations:"))
    }
}
