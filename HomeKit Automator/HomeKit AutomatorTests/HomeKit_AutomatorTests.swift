// HomeKit_AutomatorTests.swift
// Unit tests for the HomeKit Automator macOS app components.
//
// Tests cover: AutomationStore (CRUD, persistence, queries),
// AutomationModels (coding roundtrips, computed properties),
// KeychainHelper (save/read/delete), and HelperAPIClient types.

import Testing
import Foundation
@testable import HomeKit_Automator

// MARK: - AutomationStore Tests

struct AutomationStoreTests {

    /// Creates a temporary directory for test isolation.
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hka-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Cleans up a temporary directory.
    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    @Test @MainActor func storeInitializesEmpty() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let store = AutomationStore(configDir: dir)
        #expect(store.automations.isEmpty)
        #expect(store.logEntries.isEmpty)
        #expect(store.lastError == nil)
    }

    @Test @MainActor func storeLoadsPersistedAutomations() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        // Write a registry file as the CLI would
        let automation = RegisteredAutomation(
            id: "test-1", name: "Test Auto", description: "Desc",
            trigger: AutomationTrigger(type: "manual", humanReadable: "Manual"),
            conditions: nil,
            actions: [AutomationAction(deviceName: "Light", characteristic: "On", value: .bool(true))],
            enabled: true, shortcutName: "HKA-Test", createdAt: "2026-02-28T00:00:00Z"
        )
        let data = try JSONEncoder().encode([automation])
        try data.write(to: dir.appendingPathComponent("automations.json"))

        let store = AutomationStore(configDir: dir)
        #expect(store.automations.count == 1)
        #expect(store.automations.first?.name == "Test Auto")
    }

    @Test @MainActor func storeDeleteRemovesAndPersists() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let automations = [
            RegisteredAutomation(
                id: "a1", name: "First", trigger: AutomationTrigger(type: "manual", humanReadable: "M"),
                actions: [AutomationAction(deviceName: "L", characteristic: "On", value: .bool(true))],
                enabled: true, shortcutName: "S1", createdAt: "2026-01-01T00:00:00Z"
            ),
            RegisteredAutomation(
                id: "a2", name: "Second", trigger: AutomationTrigger(type: "manual", humanReadable: "M"),
                actions: [AutomationAction(deviceName: "L", characteristic: "On", value: .bool(false))],
                enabled: true, shortcutName: "S2", createdAt: "2026-01-02T00:00:00Z"
            )
        ]
        try JSONEncoder().encode(automations).write(to: dir.appendingPathComponent("automations.json"))

        let store = AutomationStore(configDir: dir)
        #expect(store.automations.count == 2)

        store.delete("a1")
        #expect(store.automations.count == 1)
        #expect(store.automations.first?.id == "a2")

        // Verify persistence — reload from disk
        let store2 = AutomationStore(configDir: dir)
        #expect(store2.automations.count == 1)
    }

    @Test @MainActor func storeToggleEnabledPersists() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let automation = RegisteredAutomation(
            id: "t1", name: "Toggle Me", trigger: AutomationTrigger(type: "manual", humanReadable: "M"),
            actions: [AutomationAction(deviceName: "L", characteristic: "On", value: .bool(true))],
            enabled: true, shortcutName: "S", createdAt: "2026-01-01T00:00:00Z"
        )
        try JSONEncoder().encode([automation]).write(to: dir.appendingPathComponent("automations.json"))

        let store = AutomationStore(configDir: dir)
        #expect(store.automations.first?.enabled == true)

        store.toggleEnabled("t1")
        #expect(store.automations.first?.enabled == false)

        // Verify persistence
        let store2 = AutomationStore(configDir: dir)
        #expect(store2.automations.first?.enabled == false)
    }

    @Test @MainActor func storeLogEntriesFiltering() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let logDir = dir.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        let entries = [
            AutomationLogEntry(automationId: "a1", automationName: "First",
                               timestamp: "2026-01-01T12:00:00Z",
                               actionsExecuted: 2, succeeded: 2, failed: 0),
            AutomationLogEntry(automationId: "a2", automationName: "Second",
                               timestamp: "2026-01-01T13:00:00Z",
                               actionsExecuted: 3, succeeded: 2, failed: 1, errors: ["Timeout"]),
            AutomationLogEntry(automationId: "a1", automationName: "First",
                               timestamp: "2026-01-02T12:00:00Z",
                               actionsExecuted: 2, succeeded: 1, failed: 1, errors: ["Device offline"])
        ]
        try JSONEncoder().encode(entries).write(to: logDir.appendingPathComponent("automation-log.json"))

        let store = AutomationStore(configDir: dir)
        #expect(store.logEntries.count == 3)
        #expect(store.logEntries(for: "a1").count == 2)
        #expect(store.logEntries(for: "a2").count == 1)
    }

    @Test @MainActor func storeSuccessRateCalculation() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let logDir = dir.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        let entries = [
            AutomationLogEntry(automationId: "a1", automationName: "Test",
                               timestamp: "2026-01-01T00:00:00Z",
                               actionsExecuted: 4, succeeded: 3, failed: 1),
            AutomationLogEntry(automationId: "a1", automationName: "Test",
                               timestamp: "2026-01-02T00:00:00Z",
                               actionsExecuted: 2, succeeded: 2, failed: 0)
        ]
        try JSONEncoder().encode(entries).write(to: logDir.appendingPathComponent("automation-log.json"))

        let store = AutomationStore(configDir: dir)
        // Total: 6 actions, 5 succeeded => 83.33%
        let rate = store.successRate(for: "a1")
        #expect(abs(rate - 83.33) < 0.5)

        // Unknown automation => 100%
        #expect(store.successRate(for: "unknown") == 100.0)
    }

    @Test @MainActor func storeHandlesCorruptedFile() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        // Write invalid JSON
        try "not valid json".data(using: .utf8)!.write(to: dir.appendingPathComponent("automations.json"))

        let store = AutomationStore(configDir: dir)
        #expect(store.automations.isEmpty)
        #expect(store.lastError != nil)
    }
}

// MARK: - AutomationModels Tests

struct AutomationModelTests {

    @Test func automationDefinitionCodableRoundtrip() throws {
        let definition = AutomationDefinition(
            name: "Evening Lights",
            description: "Turn on at sunset",
            trigger: AutomationTrigger(type: "solar", humanReadable: "At sunset", event: "sunset"),
            conditions: [
                AutomationCondition(type: "time", humanReadable: "After 5pm", after: "17:00")
            ],
            actions: [
                AutomationAction(deviceName: "Living Room", characteristic: "On", value: .bool(true)),
                AutomationAction(deviceName: "Kitchen", characteristic: "Brightness", value: .int(75), delaySeconds: 5)
            ],
            enabled: true
        )

        let data = try JSONEncoder().encode(definition)
        let decoded = try JSONDecoder().decode(AutomationDefinition.self, from: data)

        #expect(decoded.name == "Evening Lights")
        #expect(decoded.trigger.type == "solar")
        #expect(decoded.trigger.event == "sunset")
        #expect(decoded.conditions?.count == 1)
        #expect(decoded.actions.count == 2)
        #expect(decoded.actions[1].delaySeconds == 5)
        #expect(decoded.enabled == true)
    }

    @Test func registeredAutomationIdentity() {
        let a = RegisteredAutomation(
            id: "same-id", name: "A", trigger: AutomationTrigger(type: "manual", humanReadable: "M"),
            actions: [], enabled: true, shortcutName: "S", createdAt: "2026-01-01T00:00:00Z"
        )
        let b = RegisteredAutomation(
            id: "same-id", name: "B", trigger: AutomationTrigger(type: "schedule", humanReadable: "S"),
            actions: [], enabled: false, shortcutName: "S2", createdAt: "2026-02-01T00:00:00Z"
        )
        // Hashable/Equatable is based on id only
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test func logEntryComputedProperties() {
        let success = AutomationLogEntry(
            automationId: "a", automationName: "A",
            timestamp: "2026-01-15T08:30:00Z",
            actionsExecuted: 3, succeeded: 3, failed: 0
        )
        #expect(success.isSuccess == true)
        #expect(success.successRate == 100.0)
        #expect(success.date != nil)

        let partial = AutomationLogEntry(
            automationId: "b", automationName: "B",
            timestamp: "2026-01-15T09:00:00Z",
            actionsExecuted: 4, succeeded: 1, failed: 3, errors: ["err1", "err2"]
        )
        #expect(partial.isSuccess == false)
        #expect(partial.successRate == 25.0)

        let empty = AutomationLogEntry(
            automationId: "c", automationName: "C",
            timestamp: "2026-01-15T10:00:00Z",
            actionsExecuted: 0, succeeded: 0, failed: 0
        )
        #expect(empty.successRate == 100.0)
    }

    @Test func anyCodableValueRoundtrip() throws {
        let values: [AnyCodableValue] = [
            .string("hello"), .int(42), .double(3.14), .bool(true), .null,
            .array([.int(1), .string("two")]),
            .dictionary(["key": .bool(false)])
        ]

        for value in values {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
            #expect(decoded == value)
        }
    }

    @Test func anyCodableValueAccessors() {
        #expect(AnyCodableValue.string("hi").stringValue == "hi")
        #expect(AnyCodableValue.int(5).intValue == 5)
        #expect(AnyCodableValue.double(2.5).doubleValue == 2.5)
        #expect(AnyCodableValue.int(3).doubleValue == 3.0)
        #expect(AnyCodableValue.bool(true).boolValue == true)
        #expect(AnyCodableValue.array([.int(1)]).arrayValue?.count == 1)
        #expect(AnyCodableValue.dictionary(["a": .null]).dictionaryValue?["a"] == .null)

        // Wrong type returns nil
        #expect(AnyCodableValue.string("hi").intValue == nil)
        #expect(AnyCodableValue.int(5).boolValue == nil)
    }

    @Test func anyCodableValueDisplayString() {
        #expect(AnyCodableValue.string("test").displayString == "test")
        #expect(AnyCodableValue.int(42).displayString == "42")
        #expect(AnyCodableValue.bool(true).displayString == "true")
        #expect(AnyCodableValue.null.displayString == "null")
    }
}

// MARK: - KeychainHelper Tests

struct KeychainHelperTests {

    private let testKey = "com.hka.test.\(UUID().uuidString)"

    @Test func saveAndReadRoundtrip() throws {
        defer { KeychainHelper.delete(forKey: testKey) }

        try KeychainHelper.save("my-secret-key", forKey: testKey)
        let retrieved = KeychainHelper.read(forKey: testKey)
        #expect(retrieved == "my-secret-key")
    }

    @Test func readNonexistentReturnsNil() {
        let result = KeychainHelper.read(forKey: "nonexistent-key-\(UUID().uuidString)")
        #expect(result == nil)
    }

    @Test func deleteRemovesValue() throws {
        defer { KeychainHelper.delete(forKey: testKey) }

        try KeychainHelper.save("to-delete", forKey: testKey)
        #expect(KeychainHelper.read(forKey: testKey) == "to-delete")

        let deleted = KeychainHelper.delete(forKey: testKey)
        #expect(deleted == true)
        #expect(KeychainHelper.read(forKey: testKey) == nil)
    }

    @Test func saveOverwritesExisting() throws {
        defer { KeychainHelper.delete(forKey: testKey) }

        try KeychainHelper.save("first-value", forKey: testKey)
        #expect(KeychainHelper.read(forKey: testKey) == "first-value")

        try KeychainHelper.save("second-value", forKey: testKey)
        #expect(KeychainHelper.read(forKey: testKey) == "second-value")
    }

    @Test func migrateFromUserDefaults() {
        let udKey = "hka-test-migrate-\(UUID().uuidString)"
        let kcKey = "hka-test-kc-\(UUID().uuidString)"
        defer {
            UserDefaults.standard.removeObject(forKey: udKey)
            KeychainHelper.delete(forKey: kcKey)
        }

        // Set a value in UserDefaults
        UserDefaults.standard.set("migrate-me", forKey: udKey)

        // Run migration
        KeychainHelper.migrateFromUserDefaults(userDefaultsKey: udKey, keychainKey: kcKey)

        // Should be in Keychain now
        #expect(KeychainHelper.read(forKey: kcKey) == "migrate-me")
        // Should be removed from UserDefaults
        #expect(UserDefaults.standard.string(forKey: udKey) == nil)
    }

    @Test func migrateSkipsIfAlreadyInKeychain() throws {
        let udKey = "hka-test-skip-\(UUID().uuidString)"
        let kcKey = "hka-test-skip-kc-\(UUID().uuidString)"
        defer {
            UserDefaults.standard.removeObject(forKey: udKey)
            KeychainHelper.delete(forKey: kcKey)
        }

        // Pre-populate Keychain
        try KeychainHelper.save("existing-value", forKey: kcKey)
        // Set a different value in UserDefaults
        UserDefaults.standard.set("should-not-overwrite", forKey: udKey)

        // Run migration — should be a no-op
        KeychainHelper.migrateFromUserDefaults(userDefaultsKey: udKey, keychainKey: kcKey)

        // Keychain should still have original value
        #expect(KeychainHelper.read(forKey: kcKey) == "existing-value")
        // UserDefaults should NOT have been removed (migration was skipped)
        #expect(UserDefaults.standard.string(forKey: udKey) == "should-not-overwrite")
    }
}

// MARK: - HelperAPIClient Response Types Tests

struct HelperAPIResponseTests {

    @Test func statusResponseDecoding() throws {
        let json = """
        {"status": "ok", "version": "1.2.0", "uptime": 3600.5}
        """
        let response = try JSONDecoder().decode(StatusResponse.self, from: Data(json.utf8))
        #expect(response.status == "ok")
        #expect(response.version == "1.2.0")
        #expect(response.uptime == 3600.5)
    }

    @Test func statusResponseMinimal() throws {
        let json = """
        {"status": "ok"}
        """
        let response = try JSONDecoder().decode(StatusResponse.self, from: Data(json.utf8))
        #expect(response.status == "ok")
        #expect(response.version == nil)
        #expect(response.uptime == nil)
    }

    @Test func scenesResponseDecoding() throws {
        let json = """
        {"scenes": [{"name": "Good Night", "uuid": "abc-123"}, {"name": "Movie Time", "uuid": "def-456"}]}
        """
        let response = try JSONDecoder().decode(ScenesResponse.self, from: Data(json.utf8))
        #expect(response.scenes.count == 2)
        #expect(response.scenes[0].name == "Good Night")
        #expect(response.scenes[1].uuid == "def-456")
    }

    @Test func createAutomationResponseDecoding() throws {
        let successJson = """
        {"success": true, "automationId": "new-id-123", "message": null}
        """
        let success = try JSONDecoder().decode(CreateAutomationResponse.self, from: Data(successJson.utf8))
        #expect(success.success == true)
        #expect(success.automationId == "new-id-123")

        let failJson = """
        {"success": false, "automationId": null, "message": "Duplicate name"}
        """
        let fail = try JSONDecoder().decode(CreateAutomationResponse.self, from: Data(failJson.utf8))
        #expect(fail.success == false)
        #expect(fail.message == "Duplicate name")
    }

    @Test func deviceMapResponseDecoding() throws {
        let json = """
        {
            "homes": [{"name": "My Home", "uuid": "h1", "rooms": [{"name": "Living Room", "uuid": "r1"}], "accessories": []}],
            "rooms": [{"name": "Living Room", "uuid": "r1"}],
            "scenes": [{"name": "Good Night", "uuid": "s1"}]
        }
        """
        let response = try JSONDecoder().decode(DeviceMapResponse.self, from: Data(json.utf8))
        #expect(response.homes?.count == 1)
        #expect(response.homes?.first?.name == "My Home")
        #expect(response.rooms?.count == 1)
        #expect(response.scenes?.count == 1)
    }

    @Test func helperAPIErrorDescriptions() {
        let errors: [(HelperAPIError, String)] = [
            (.socketCreationFailed, "Could not create socket"),
            (.connectionFailed, "Could not connect to HomeKitHelper"),
            (.sendFailed, "Failed to send command"),
            (.noResponse, "No response from HomeKitHelper"),
            (.encodingFailed, "Failed to encode request"),
            (.decodingFailed, "Failed to decode response"),
            (.helperNotRunning, "HomeKitHelper is not running"),
            (.serverError("test msg"), "HomeKitHelper error: test msg")
        ]

        for (error, expected) in errors {
            #expect(error.errorDescription == expected)
        }
    }
}

// MARK: - LLMProvider Tests

struct LLMProviderTests {

    @Test func providerDefaults() {
        #expect(LLMProvider.openai.defaultModel == "gpt-4o")
        #expect(LLMProvider.claude.defaultModel == "claude-sonnet-4-20250514")
        #expect(LLMProvider.custom.defaultModel == "")

        #expect(LLMProvider.openai.defaultEndpoint.contains("openai.com"))
        #expect(LLMProvider.claude.defaultEndpoint.contains("anthropic.com"))
        #expect(LLMProvider.custom.defaultEndpoint == "")
    }

    @Test func providerRawValueRoundtrip() {
        for provider in LLMProvider.allCases {
            #expect(LLMProvider(rawValue: provider.rawValue) == provider)
        }
    }

    @Test func temperatureUnitRoundtrip() {
        for unit in TemperatureUnit.allCases {
            #expect(TemperatureUnit(rawValue: unit.rawValue) == unit)
        }
        #expect(TemperatureUnit.celsius.displayName.contains("C"))
        #expect(TemperatureUnit.fahrenheit.displayName.contains("F"))
    }
}
