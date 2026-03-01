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

    func testSaveAndLoadAll() async throws {
        let automation = makeSampleAutomation(id: "save-load-1", name: "Save Load Test")
        try await registry.save(automation)

        let all = try await registry.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].id, "save-load-1")
        XCTAssertEqual(all[0].name, "Save Load Test")
        XCTAssertEqual(all[0].shortcutName, "HKA: Save Load Test")
        XCTAssertTrue(all[0].enabled)
    }

    func testSaveMultiple() async throws {
        let a1 = makeSampleAutomation(id: "id-1", name: "Auto 1")
        let a2 = makeSampleAutomation(id: "id-2", name: "Auto 2")
        let a3 = makeSampleAutomation(id: "id-3", name: "Auto 3")

        try await registry.save(a1)
        try await registry.save(a2)
        try await registry.save(a3)

        let all = try await registry.loadAll()
        XCTAssertEqual(all.count, 3)
        // Verify order matches insertion order
        XCTAssertEqual(all[0].name, "Auto 1")
        XCTAssertEqual(all[1].name, "Auto 2")
        XCTAssertEqual(all[2].name, "Auto 3")
    }

    func testFindById() async throws {
        let automation = makeSampleAutomation(id: "find-by-id", name: "Findable")
        try await registry.save(automation)

        let found = try await registry.find("find-by-id")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, "find-by-id")
        XCTAssertEqual(found?.name, "Findable")
    }

    func testFindByName() async throws {
        let automation = makeSampleAutomation(id: "name-search", name: "Evening Routine")
        try await registry.save(automation)

        // Case-insensitive name lookup
        let found = try await registry.find("evening routine")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, "name-search")
        XCTAssertEqual(found?.name, "Evening Routine")

        // Mixed case
        let found2 = try await registry.find("EVENING ROUTINE")
        XCTAssertNotNil(found2)
        XCTAssertEqual(found2?.id, "name-search")
    }

    func testUpdate() async throws {
        let id = "update-me"
        var automation = makeSampleAutomation(id: id, name: "Original Name", enabled: true)
        try await registry.save(automation)

        // Modify fields
        automation.name = "Updated Name"
        automation.enabled = false
        try await registry.update(automation)

        // Verify changes persisted
        let found = try await registry.find(id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "Updated Name")
        XCTAssertEqual(found?.enabled, false)

        // Verify total count unchanged
        let all = try await registry.loadAll()
        XCTAssertEqual(all.count, 1)
    }

    func testDelete() async throws {
        let automation = makeSampleAutomation(id: "delete-me", name: "To Be Deleted")
        try await registry.save(automation)
        let beforeDelete = try await registry.loadAll()
        XCTAssertEqual(beforeDelete.count, 1)

        try await registry.delete("delete-me")

        let all = try await registry.loadAll()
        XCTAssertTrue(all.isEmpty)
    }

    func testDeleteNonExistent() async throws {
        // Registry is empty — deleting a non-existent ID should throw .notFound
        do {
            try await registry.delete("nonexistent-id")
            XCTFail("Expected RegistryError.notFound")
        } catch let error as RegistryError {
            guard case .notFound(let id) = error else {
                XCTFail("Expected RegistryError.notFound, got \(error)")
                return
            }
            XCTAssertEqual(id, "nonexistent-id")
        }
    }

    // MARK: - Log Tests

    func testAppendAndLoadLog() async throws {
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

        try await registry.appendLog(entry1)
        try await registry.appendLog(entry2)

        // Load all (no period filter)
        let allEntries = try await registry.loadLog()
        XCTAssertEqual(allEntries.count, 2)

        // Load with "today" filter
        let todayEntries = try await registry.loadLog(period: "today")
        XCTAssertEqual(todayEntries.count, 2)
        XCTAssertEqual(todayEntries[0].automationId, "auto-1")
        XCTAssertEqual(todayEntries[1].automationName, "Night Lock")
    }

    func testLogCapping() async throws {
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
            try await registry.appendLog(entry)
        }

        let entries = try await registry.loadLog()
        XCTAssertEqual(entries.count, 1000)

        // Verify the oldest entries were pruned (entries 0-4 should be gone)
        // The first entry should be "Auto 5" (the 6th one appended)
        XCTAssertEqual(entries[0].automationName, "Auto 5")
        XCTAssertEqual(entries[999].automationName, "Auto 1004")
    }

    // MARK: - Concurrent Write Tests

    func testConcurrentSavesDontLoseData() async throws {
        // Simulate concurrent saves using TaskGroup
        let saveCount = 20
        let registry = self.registry!

        // Pre-create automations to avoid capturing self in task closures
        let automations = (0..<saveCount).map { i in
            makeSampleAutomation(id: "concurrent-\(i)", name: "Concurrent Auto \(i)")
        }

        let successCount = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for i in 0..<saveCount {
                let automation = automations[i]
                group.addTask {
                    do {
                        try await registry.save(automation)
                        return true
                    } catch {
                        // Duplicate name errors are expected under concurrency — that's fine
                        if case RegistryError.duplicateName = error {
                            return false
                        }
                        XCTFail("Unexpected error on save \(i): \(error)")
                        return false
                    }
                }
            }

            var count = 0
            for await succeeded in group {
                if succeeded { count += 1 }
            }
            return count
        }

        // At minimum, some saves should have succeeded and the file should be readable
        let all = try await registry.loadAll()
        XCTAssertFalse(all.isEmpty, "At least some concurrent saves should succeed")
        XCTAssertTrue(all.count <= saveCount, "Should not exceed total save attempts")
        XCTAssertEqual(all.count, successCount, "Loaded count should match successful saves")
    }

    func testRapidSaveDeleteCycle() async throws {
        // Save and delete rapidly to test file system state consistency
        for i in 0..<10 {
            let automation = makeSampleAutomation(id: "cycle-\(i)", name: "Cycle \(i)")
            try await registry.save(automation)
            try await registry.delete("cycle-\(i)")
        }

        let all = try await registry.loadAll()
        XCTAssertTrue(all.isEmpty, "All saved automations should be deleted")
    }

    func testUpdateNonExistent() async throws {
        let automation = makeSampleAutomation(id: "ghost", name: "Ghost")
        do {
            try await registry.update(automation)
            XCTFail("Expected RegistryError.notFound")
        } catch let error as RegistryError {
            guard case .notFound(let id) = error else {
                XCTFail("Expected RegistryError.notFound, got \(error)")
                return
            }
            XCTAssertEqual(id, "ghost")
        }
    }

    // MARK: - Log Period Filter Tests

    func testLoadLogWeekFilter() async throws {
        let formatter = ISO8601DateFormatter()
        let now = Date()

        // Entry from 3 days ago (within week)
        let recentEntry = AutomationLogEntry(
            automationId: "auto-recent",
            automationName: "Recent",
            timestamp: formatter.string(from: Calendar.current.date(byAdding: .day, value: -3, to: now)!),
            actionsExecuted: 1,
            succeeded: 1,
            failed: 0,
            errors: nil
        )

        // Entry from 10 days ago (outside week)
        let oldEntry = AutomationLogEntry(
            automationId: "auto-old",
            automationName: "Old",
            timestamp: formatter.string(from: Calendar.current.date(byAdding: .day, value: -10, to: now)!),
            actionsExecuted: 1,
            succeeded: 1,
            failed: 0,
            errors: nil
        )

        try await registry.appendLog(oldEntry)
        try await registry.appendLog(recentEntry)

        let weekEntries = try await registry.loadLog(period: "week")
        XCTAssertEqual(weekEntries.count, 1)
        XCTAssertEqual(weekEntries[0].automationName, "Recent")
    }

    func testLoadLogMonthFilter() async throws {
        let formatter = ISO8601DateFormatter()
        let now = Date()

        // Entry from 15 days ago (within month)
        let withinMonth = AutomationLogEntry(
            automationId: "auto-month",
            automationName: "Within Month",
            timestamp: formatter.string(from: Calendar.current.date(byAdding: .day, value: -15, to: now)!),
            actionsExecuted: 1,
            succeeded: 1,
            failed: 0,
            errors: nil
        )

        // Entry from 40 days ago (outside month)
        let outsideMonth = AutomationLogEntry(
            automationId: "auto-outside",
            automationName: "Outside Month",
            timestamp: formatter.string(from: Calendar.current.date(byAdding: .day, value: -40, to: now)!),
            actionsExecuted: 1,
            succeeded: 1,
            failed: 0,
            errors: nil
        )

        try await registry.appendLog(outsideMonth)
        try await registry.appendLog(withinMonth)

        let monthEntries = try await registry.loadLog(period: "month")
        XCTAssertEqual(monthEntries.count, 1)
        XCTAssertEqual(monthEntries[0].automationName, "Within Month")

        // loadLog with no filter should return both
        let allEntries = try await registry.loadLog()
        XCTAssertEqual(allEntries.count, 2)
    }

    func testLoadLogTodayFilter() async throws {
        let formatter = ISO8601DateFormatter()
        let now = Date()

        // Entry from right now (today)
        let todayEntry = AutomationLogEntry(
            automationId: "auto-today",
            automationName: "Today",
            timestamp: formatter.string(from: now),
            actionsExecuted: 1,
            succeeded: 1,
            failed: 0,
            errors: nil
        )

        // Entry from yesterday
        let yesterdayEntry = AutomationLogEntry(
            automationId: "auto-yesterday",
            automationName: "Yesterday",
            timestamp: formatter.string(from: Calendar.current.date(byAdding: .day, value: -1, to: now)!),
            actionsExecuted: 1,
            succeeded: 1,
            failed: 0,
            errors: nil
        )

        try await registry.appendLog(yesterdayEntry)
        try await registry.appendLog(todayEntry)

        let todayEntries = try await registry.loadLog(period: "today")
        XCTAssertEqual(todayEntries.count, 1)
        XCTAssertEqual(todayEntries[0].automationName, "Today")
    }

    func testLoadLogUnknownPeriodDefaultsToWeek() async throws {
        let formatter = ISO8601DateFormatter()
        let now = Date()

        // Entry from 3 days ago (within week)
        let recentEntry = AutomationLogEntry(
            automationId: "auto-r",
            automationName: "Recent",
            timestamp: formatter.string(from: Calendar.current.date(byAdding: .day, value: -3, to: now)!),
            actionsExecuted: 1,
            succeeded: 1,
            failed: 0,
            errors: nil
        )

        // Entry from 10 days ago (outside week)
        let oldEntry = AutomationLogEntry(
            automationId: "auto-o",
            automationName: "Old",
            timestamp: formatter.string(from: Calendar.current.date(byAdding: .day, value: -10, to: now)!),
            actionsExecuted: 1,
            succeeded: 1,
            failed: 0,
            errors: nil
        )

        try await registry.appendLog(oldEntry)
        try await registry.appendLog(recentEntry)

        // Unknown period string should default to week behavior
        let entries = try await registry.loadLog(period: "custom-unknown")
        XCTAssertEqual(entries.count, 1, "Unknown period should default to week filter")
        XCTAssertEqual(entries[0].automationName, "Recent")
    }
}
