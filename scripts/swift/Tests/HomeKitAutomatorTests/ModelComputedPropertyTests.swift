// ModelComputedPropertyTests.swift
// Tests for computed properties on AutomationLogEntry: date, isSuccess, successRate, id.

import XCTest
import HomeKitCore

final class ModelComputedPropertyTests: XCTestCase {

    private let formatter = ISO8601DateFormatter()

    private func makeEntry(
        automationId: String = "auto-1",
        timestamp: String? = nil,
        actionsExecuted: Int = 3,
        succeeded: Int = 2,
        failed: Int = 1
    ) -> AutomationLogEntry {
        AutomationLogEntry(
            automationId: automationId,
            automationName: "Test",
            timestamp: timestamp ?? formatter.string(from: Date()),
            actionsExecuted: actionsExecuted,
            succeeded: succeeded,
            failed: failed,
            errors: nil
        )
    }

    // MARK: - date

    func testDateParsesValidISO8601() {
        let now = Date()
        let timestamp = formatter.string(from: now)
        let entry = makeEntry(timestamp: timestamp)

        XCTAssertNotNil(entry.date)
        // Should be within 1 second of the original date
        if let parsed = entry.date {
            XCTAssertTrue(abs(parsed.timeIntervalSince(now)) < 1.0,
                          "Parsed date should be close to original")
        }
    }

    func testDateReturnsNilForInvalidTimestamp() {
        let entry = makeEntry(timestamp: "not-a-date")
        XCTAssertNil(entry.date, "Invalid timestamp should return nil date")
    }

    func testDateReturnsNilForEmptyTimestamp() {
        let entry = makeEntry(timestamp: "")
        XCTAssertNil(entry.date, "Empty timestamp should return nil date")
    }

    // MARK: - isSuccess

    func testIsSuccessWhenNoFailures() {
        let entry = makeEntry(actionsExecuted: 3, succeeded: 3, failed: 0)
        XCTAssertTrue(entry.isSuccess)
    }

    func testIsNotSuccessWhenFailures() {
        let entry = makeEntry(actionsExecuted: 3, succeeded: 2, failed: 1)
        XCTAssertFalse(entry.isSuccess)
    }

    func testIsSuccessWhenZeroActions() {
        let entry = makeEntry(actionsExecuted: 0, succeeded: 0, failed: 0)
        XCTAssertTrue(entry.isSuccess, "Zero failures means success even with zero actions")
    }

    // MARK: - successRate

    func testSuccessRateFullSuccess() {
        let entry = makeEntry(actionsExecuted: 5, succeeded: 5, failed: 0)
        XCTAssertEqual(entry.successRate, 100.0, accuracy: 0.01)
    }

    func testSuccessRatePartialSuccess() {
        let entry = makeEntry(actionsExecuted: 4, succeeded: 3, failed: 1)
        XCTAssertEqual(entry.successRate, 75.0, accuracy: 0.01)
    }

    func testSuccessRateZeroActions() {
        let entry = makeEntry(actionsExecuted: 0, succeeded: 0, failed: 0)
        XCTAssertEqual(entry.successRate, 100.0, accuracy: 0.01,
                       "Zero actionsExecuted should default to 100%")
    }

    func testSuccessRateAllFailures() {
        let entry = makeEntry(actionsExecuted: 3, succeeded: 0, failed: 3)
        XCTAssertEqual(entry.successRate, 0.0, accuracy: 0.01)
    }

    // MARK: - id

    func testIdCompositeFormat() {
        let entry = makeEntry(automationId: "abc-123", timestamp: "2024-01-15T10:30:00Z")
        XCTAssertEqual(entry.id, "abc-123-2024-01-15T10:30:00Z")
    }

    func testIdUniqueness() {
        let entry1 = makeEntry(automationId: "auto-1", timestamp: "2024-01-15T10:00:00Z")
        let entry2 = makeEntry(automationId: "auto-1", timestamp: "2024-01-15T11:00:00Z")
        let entry3 = makeEntry(automationId: "auto-2", timestamp: "2024-01-15T10:00:00Z")

        XCTAssertNotEqual(entry1.id, entry2.id, "Different timestamps should produce different IDs")
        XCTAssertNotEqual(entry1.id, entry3.id, "Different automation IDs should produce different IDs")
    }

    // MARK: - AutomationAction.value

    func testValueIdentity() {
        let action = AutomationAction(
            deviceUuid: "dev-1",
            deviceName: "Light",
            characteristic: "brightness",
            value: .int(75),
            delaySeconds: 0
        )
        XCTAssertEqual(action.value, .int(75))
    }

    // MARK: - AutomationSuggestion Codable Round-Trip

    func testAutomationSuggestionRoundTrip() throws {
        let suggestion = AutomationSuggestion(
            name: "Test Suggestion",
            reason: "Testing",
            trigger: "daily at 7 AM",
            actions: ["Light -> on"],
            category: "convenience"
        )

        let data = try JSONEncoder().encode(suggestion)
        let decoded = try JSONDecoder().decode(AutomationSuggestion.self, from: data)

        XCTAssertEqual(decoded.name, suggestion.name)
        XCTAssertEqual(decoded.reason, suggestion.reason)
        XCTAssertEqual(decoded.trigger, suggestion.trigger)
        XCTAssertEqual(decoded.actions, suggestion.actions)
        XCTAssertEqual(decoded.category, suggestion.category)
    }
}
