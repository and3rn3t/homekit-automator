// AutomationRegistryCRUDTests.swift
// Comprehensive CRUD tests for AutomationRegistry with isolated temp directories.

import XCTest
@testable import homekitauto

final class AutomationRegistryCRUDTests: XCTestCase {

    var tempDir: URL!
    var registry: AutomationRegistry!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hka-crud-test-\(UUID().uuidString)")
        registry = AutomationRegistry(configDir: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeSampleAutomation(
        id: String = UUID().uuidString,
        name: String = "Test Automation",
        enabled: Bool = true
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
            enabled: enabled,
            shortcutName: "HKA: \(name)",
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    // MARK: - CRUD Tests

    func testSaveAndLoadAll() throws {
        let automation = makeSampleAutomation(id: "save-load-1", name: "Save Load Test")
        try registry.save(automation)

        let all = try registry.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].id, "save-load-1")
        XCTAssertEqual(all[0].name, "Save Load Test")
        XCTAssertEqual(all[0].shortcutName, "HKA: Save Load Test")
        XCTAssertTrue(all[0].enabled)
    }

    func testSaveMultiple() throws {
        let a1 = makeSampleAutomation(id: "id-1", name: "Auto 1")
        let a2 = makeSampleAutomation(id: "id-2", name: "Auto 2")
        let a3 = makeSampleAutomation(id: "id-3", name: "Auto 3")

        try registry.save(a1)
        try registry.save(a2)
        try registry.save(a3)

        let all = try registry.loadAll()
        XCTAssertEqual(all.count, 3)
        // Verify order matches insertion order
        XCTAssertEqual(all[0].name, "Auto 1")
        XCTAssertEqual(all[1].name, "Auto 2")
        XCTAssertEqual(all[2].name, "Auto 3")
    }

    func testFindById() throws {
        let automation = makeSampleAutomation(id: "find-by-id", name: "Findable")
        try registry.save(automation)

        let found = try registry.find("find-by-id")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, "find-by-id")
        XCTAssertEqual(found?.name, "Findable")
    }

    func testFindByName() throws {
        let automation = makeSampleAutomation(id: "name-search", name: "Evening Routine")
        try registry.save(automation)

        // Case-insensitive name lookup
        let found = try registry.find("evening routine")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, "name-search")
        XCTAssertEqual(found?.name, "Evening Routine")

        // Mixed case
        let found2 = try registry.find("EVENING ROUTINE")
        XCTAssertNotNil(found2)
        XCTAssertEqual(found2?.id, "name-search")
    }

    func testUpdate() throws {
        let id = "update-me"
        var automation = makeSampleAutomation(id: id, name: "Original Name", enabled: true)
        try registry.save(automation)

        // Modify fields
        automation.name = "Updated Name"
        automation.enabled = false
        try registry.update(automation)

        // Verify changes persisted
        let found = try registry.find(id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "Updated Name")
        XCTAssertEqual(found?.enabled, false)

        // Verify total count unchanged
        let all = try registry.loadAll()
        XCTAssertEqual(all.count, 1)
    }

    func testDelete() throws {
        let automation = makeSampleAutomation(id: "delete-me", name: "To Be Deleted")
        try registry.save(automation)
        XCTAssertEqual(try registry.loadAll().count, 1)

        try registry.delete("delete-me")

        let all = try registry.loadAll()
        XCTAssertTrue(all.isEmpty)
    }

    func testDeleteNonExistent() throws {
        // Registry is empty — deleting a non-existent ID should throw .notFound
        XCTAssertThrowsError(try registry.delete("nonexistent-id")) { error in
            guard case RegistryError.notFound(let id) = error else {
                XCTFail("Expected RegistryError.notFound, got \(error)")
                return
            }
            XCTAssertEqual(id, "nonexistent-id")
        }
    }

    // MARK: - Log Tests

    func testAppendAndLoadLog() throws {
        let now = Date()
        let formatter = ISO8601DateFormatter()

        let entry1 = AutomationLogEntry(
            automationId: "auto-1",
            automationName: "Morning Routine",
            timestamp: formatter.string(from: now),
            actionsExecuted: 3,
            succeeded: 3,
            failed: 0,
            errors: nil
        )
        let entry2 = AutomationLogEntry(
            automationId: "auto-2",
            automationName: "Night Lock",
            timestamp: formatter.string(from: now),
            actionsExecuted: 1,
            succeeded: 1,
            failed: 0,
            errors: nil
        )

        try registry.appendLog(entry1)
        try registry.appendLog(entry2)

        // Load all (no period filter)
        let allEntries = try registry.loadLog()
        XCTAssertEqual(allEntries.count, 2)

        // Load with "today" filter
        let todayEntries = try registry.loadLog(period: "today")
        XCTAssertEqual(todayEntries.count, 2)
        XCTAssertEqual(todayEntries[0].automationId, "auto-1")
        XCTAssertEqual(todayEntries[1].automationName, "Night Lock")
    }

    func testLogCapping() throws {
        let formatter = ISO8601DateFormatter()
        let now = Date()

        // Append more than 1000 entries
        for i in 0..<1005 {
            let entry = AutomationLogEntry(
                automationId: "auto-\(i)",
                automationName: "Auto \(i)",
                timestamp: formatter.string(from: now),
                actionsExecuted: 1,
                succeeded: 1,
                failed: 0,
                errors: nil
            )
            try registry.appendLog(entry)
        }

        let entries = try registry.loadLog()
        XCTAssertEqual(entries.count, 1000)

        // Verify the oldest entries were pruned (entries 0-4 should be gone)
        // The first entry should be "Auto 5" (the 6th one appended)
        XCTAssertEqual(entries[0].automationName, "Auto 5")
        XCTAssertEqual(entries[999].automationName, "Auto 1004")
    }
}
