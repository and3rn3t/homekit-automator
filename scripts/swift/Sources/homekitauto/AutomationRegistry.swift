/// AutomationRegistry.swift
/// Serves as the persistence layer for the HomeKit Automator, managing all read/write operations
/// on the automation registry stored at ~/.config/homekit-automator/automations.json.
///
/// The registry maintains a JSON file containing an array of `RegisteredAutomation` objects,
/// with atomic writes to prevent corruption during concurrent access. Additionally, it manages
/// an execution log at ~/.config/homekit-automator/logs/automation-log.json for audit trails.
///
/// Thread Safety: All file operations use atomic writes, but callers should synchronize
/// multiple concurrent calls to avoid race conditions during rapid load-modify-write cycles.
/// The registry does not employ internal locking.

import Foundation

/// Manages the persistent automation registry and logs for HomeKit automations.
///
/// Directory Layout:
/// - ~/.config/homekit-automator/automations.json — Registry of all registered automations
/// - ~/.config/homekit-automator/logs/automation-log.json — Execution audit trail (up to 1000 entries)
///
/// All data is stored as JSON and persisted atomically to prevent corruption. Directories are
/// created on demand if they do not exist.
struct AutomationRegistry {
    private let configDirPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config")
        .appendingPathComponent("homekit-automator")

    /// Ensures the config directory (~/.config/homekit-automator) exists, creating intermediate
    /// directories if necessary.
    ///
    /// - Returns: The URL of the config directory.
    /// - Throws: `FileManager` errors if directory creation fails (e.g., permission denied,
    ///   disk full, or invalid path).
    func ensureConfigDir() throws -> URL {
        try FileManager.default.createDirectory(at: configDirPath, withIntermediateDirectories: true)
        return configDirPath
    }

    private var registryPath: URL {
        configDirPath.appendingPathComponent("automations.json")
    }

    private var logPath: URL {
        configDirPath.appendingPathComponent("logs").appendingPathComponent("automation-log.json")
    }

    // MARK: - CRUD

    /// Loads all registered automations from the registry file.
    ///
    /// - Returns: An array of all registered automations. Returns an empty array if the
    ///   registry file does not exist (normal on first run).
    /// - Throws: `DecodingError` if the JSON is malformed or does not match the expected
    ///   schema; `FileManager` errors if file access fails.
    func loadAll() throws -> [RegisteredAutomation] {
        guard FileManager.default.fileExists(atPath: registryPath.path) else {
            return []
        }
        let data = try Data(contentsOf: registryPath)
        return try JSONDecoder().decode([RegisteredAutomation].self, from: data)
    }

    /// Finds a registered automation by ID or name (case-insensitive name matching).
    ///
    /// - Parameter identifier: Either the automation's unique ID or its name. Name matching is
    ///   case-insensitive.
    /// - Returns: The matching automation, or `nil` if no automation matches the identifier.
    /// - Throws: `DecodingError` if the registry file is malformed; `FileManager` errors if
    ///   file access fails.
    func find(_ identifier: String) throws -> RegisteredAutomation? {
        let all = try loadAll()
        return all.first { $0.id == identifier || $0.name.lowercased() == identifier.lowercased() }
    }

    /// Saves a new automation to the registry.
    ///
    /// - Parameter automation: The automation to register. Must have a unique ID; no duplicate
    ///   checking is performed here.
    /// - Throws: `DecodingError` if the existing registry is malformed; `EncodingError` if the
    ///   new automation cannot be encoded; `FileManager` errors if directory creation or file
    ///   write fails.
    func save(_ automation: RegisteredAutomation) throws {
        var all = try loadAll()
        all.append(automation)
        try persist(all)
    }

    /// Updates an existing automation in the registry.
    ///
    /// - Parameter automation: The updated automation with the same ID as the one to replace.
    /// - Throws: `RegistryError.notFound` if no automation with the given ID exists;
    ///   `DecodingError` if the existing registry is malformed; `EncodingError` if the
    ///   updated automation cannot be encoded; `FileManager` errors if file write fails.
    func update(_ automation: RegisteredAutomation) throws {
        var all = try loadAll()
        guard let index = all.firstIndex(where: { $0.id == automation.id }) else {
            throw RegistryError.notFound(automation.id)
        }
        all[index] = automation
        try persist(all)
    }

    /// Deletes an automation from the registry by ID.
    ///
    /// - Parameter id: The unique ID of the automation to delete. Silently succeeds if no
    ///   matching automation exists.
    /// - Throws: `DecodingError` if the existing registry is malformed; `EncodingError` if the
    ///   updated registry cannot be encoded; `FileManager` errors if file write fails.
    func delete(_ id: String) throws {
        var all = try loadAll()
        all.removeAll { $0.id == id }
        try persist(all)
    }

    // MARK: - Persistence

    private func persist(_ automations: [RegisteredAutomation]) throws {
        let _ = try ensureConfigDir()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(automations)
        try data.write(to: registryPath, options: .atomic)
    }

    // MARK: - Logging

    /// Appends a log entry for an automation execution to the audit trail.
    ///
    /// Automatically maintains a rolling window of the 1000 most recent entries; older entries
    /// are discarded to prevent unbounded log growth.
    ///
    /// - Parameter entry: The log entry to append (typically containing execution time,
    ///   automation ID, and status).
    /// - Throws: `DecodingError` if the existing log is malformed; `EncodingError` if the
    ///   updated log cannot be encoded; `FileManager` errors if directory creation or file
    ///   write fails.
    func appendLog(_ entry: AutomationLogEntry) throws {
        let logDir = logPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        var entries = try loadLog()
        entries.append(entry)

        // Keep only the last 1000 entries
        if entries.count > 1000 {
            entries = Array(entries.suffix(1000))
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(entries)
        try data.write(to: logPath, options: .atomic)
    }

    /// Loads automation execution log entries, optionally filtered by a time period.
    ///
    /// - Parameter period: Optional time period for filtering. Supported values are "today",
    ///   "week", "month". Defaults to "week" if an unrecognized value is provided. Pass `nil`
    ///   to retrieve all entries.
    /// - Returns: An array of log entries matching the period filter. Returns an empty array
    ///   if the log file does not exist.
    /// - Throws: `DecodingError` if the log file is malformed; `FileManager` errors if file
    ///   access fails.
    func loadLog(period: String? = nil) throws -> [AutomationLogEntry] {
        guard FileManager.default.fileExists(atPath: logPath.path) else {
            return []
        }
        let data = try Data(contentsOf: logPath)
        var entries = try JSONDecoder().decode([AutomationLogEntry].self, from: data)

        if let period = period {
            let formatter = ISO8601DateFormatter()
            let now = Date()
            let cutoff: Date
            switch period {
            case "today":
                cutoff = Calendar.current.startOfDay(for: now)
            case "week":
                cutoff = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
            case "month":
                cutoff = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
            default:
                cutoff = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
            }

            entries = entries.filter { entry in
                guard let date = formatter.date(from: entry.timestamp) else { return false }
                return date >= cutoff
            }
        }

        return entries
    }
}

/// Errors thrown by registry operations.
enum RegistryError: LocalizedError {
    /// The requested automation was not found in the registry (e.g., during update or delete).
    case notFound(String)

    /// An automation with the given name already exists in the registry.
    case duplicateName(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let id): return "Automation not found: \(id)"
        case .duplicateName(let name): return "An automation named '\(name)' already exists"
        }
    }
}
