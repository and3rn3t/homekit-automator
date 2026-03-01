// HomeKitManager.swift
// Wraps Apple's HMHomeManager to provide a clean async interface for device discovery,
// state queries, and control commands.

import HomeKit
import Foundation

/// Shared ISO8601 formatter to avoid repeated allocation.
private let sharedISO8601Formatter = ISO8601DateFormatter()

/// Thread-safe wrapper around HMHomeManager providing async device access.
///
/// MAIN THREAD REQUIREMENT:
/// Marked with @MainActor because HMHomeManager and its delegate callbacks must always be accessed from the main thread.
/// HomeKit framework is not thread-safe; accessing homes, accessories, or characteristics from background threads
/// can cause crashes or data corruption.
@MainActor
class HomeKitManager: NSObject, HMHomeManagerDelegate, HMHomeDelegate {

    /// The underlying HomeKit home manager.
    private var homeManager: HMHomeManager!
    /// Flag indicating whether HMHomeManager has finished loading homes from iCloud.
    private var isReady = false
    /// Continuations waiting for homeManagerDidUpdateHomes callback; allows multiple waiters.
    private var readyContinuations: [CheckedContinuation<Void, Never>] = []

    // MARK: - State Change Monitoring

    /// Circular buffer storing recent device state changes for the `state_changes` command.
    /// Capped at 200 entries to prevent unbounded memory growth.
    private(set) var recentStateChanges: [[String: Any]] = []
    /// Maximum number of state changes retained in the circular buffer.
    private let maxStateChanges = 200
    /// Set of device names the user has explicitly subscribed to for monitoring.
    private(set) var subscribedDevices: Swift.Set<String> = []

    override init() {
        super.init()
        homeManager = HMHomeManager()
        homeManager.delegate = self
    }

    // MARK: - HMHomeManagerDelegate

    /// Called by HMHomeManager when homes are first loaded or updated.
    /// Resumes all waiters in readyContinuations so that async commands can proceed.
    /// Also registers as HMHomeDelegate on each home for state change monitoring.
    nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor in
            isReady = true
            // Register as delegate on each home for state change monitoring
            for home in manager.homes {
                home.delegate = self
            }
            for continuation in readyContinuations {
                continuation.resume()
            }
            readyContinuations.removeAll()
            print("[HomeKitManager] Homes updated. Found \(manager.homes.count) home(s).")
        }
    }

    /// Waits until HomeKit has loaded home data from iCloud.
    /// Uses CheckedContinuation pattern to allow multiple concurrent waiters without blocking.
    /// Returns immediately if homes are already loaded.
    /// Times out after 30 seconds to prevent indefinite hangs (e.g., iCloud sync issues).
    func waitForReady() async throws {
        if isReady { return }
        let readyTask = Task { @MainActor in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                readyContinuations.append(continuation)
            }
        }
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(30))
        }
        // Race: whichever finishes first wins
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { await readyTask.value; return true }
            group.addTask { return (try? await timeoutTask.value) == nil ? false : false }
            if let first = await group.next(), !first {
                readyTask.cancel()
            }
            group.cancelAll()
        }
        guard isReady else {
            print("[HomeKitManager] ERROR: Timed out waiting for HomeKit to load homes (30s)")
            throw HomeKitManagerError.homeKitLoadTimeout
        }
    }

    /// Errors that can occur during HomeKit operations.
    enum HomeKitManagerError: LocalizedError {
        case homeKitLoadTimeout

        var errorDescription: String? {
            switch self {
            case .homeKitLoadTimeout:
                return "HomeKit did not finish loading within 30 seconds. Check iCloud and HomeKit entitlements."
            }
        }
    }

    // MARK: - HMHomeDelegate (State Change Monitoring)

    /// Called when a characteristic value changes on any accessory in a home.
    /// Records the change in the circular buffer for retrieval via the `state_changes` command.
    nonisolated func home(_ home: HMHome, didUpdateValueFor characteristic: HMCharacteristic) {
        Task { @MainActor in
            guard let accessory = characteristic.service?.accessory else { return }
            let deviceName = accessory.name
            let charName = characteristicTypeName(characteristic.characteristicType)
            let value = characteristic.value

            let changeEntry: [String: Any] = [
                "device": deviceName,
                "home": home.name,
                "room": accessory.room?.name ?? "Unknown",
                "characteristic": charName,
                "value": value ?? "null",
                "timestamp": sharedISO8601Formatter.string(from: Date()),
                "subscribed": subscribedDevices.contains(deviceName)
            ]

            recentStateChanges.append(changeEntry)
            // Maintain circular buffer size
            if recentStateChanges.count > maxStateChanges {
                recentStateChanges.removeFirst(recentStateChanges.count - maxStateChanges)
            }

            if subscribedDevices.contains(deviceName) {
                print("[HomeKitManager] Subscribed device changed: \(deviceName).\(charName) = \(value ?? "nil")")
            }
        }
    }

    // MARK: - State Changes & Subscriptions

    /// Returns recent state changes from the circular buffer.
    /// - Parameter deviceName: Optional filter — if provided, only changes for this device are returned.
    /// - Returns: Array of state change dictionaries.
    func getStateChanges(deviceName: String? = nil) -> [[String: Any]] {
        if let deviceName = deviceName {
            return recentStateChanges.filter { ($0["device"] as? String) == deviceName }
        }
        return recentStateChanges
    }

    /// Subscribes to state change notifications for a specific device.
    /// Subscribed devices are flagged in state change entries and logged to console.
    /// - Parameter deviceName: The name of the device to subscribe to.
    /// - Returns: Confirmation dictionary with subscription status.
    func subscribe(deviceName: String) -> [String: Any] {
        subscribedDevices.insert(deviceName)
        return [
            "subscribed": true,
            "device": deviceName,
            "totalSubscriptions": subscribedDevices.count
        ]
    }

    // MARK: - Status

    /// Returns overall HomeKit status: connection state, homes, and automation count.
    /// - Returns: Dictionary with keys "connected" (bool), "homes" (array), "automationCount" (int)
    func getStatus() async throws -> [String: Any] {
        try await waitForReady()
        let homes = homeManager.homes.map { home -> [String: Any] in
            [
                "name": home.name,
                "accessoryCount": home.accessories.count,
                "roomCount": home.rooms.count
            ]
        }
        return [
            "connected": true,
            "homes": homes,
            "automationCount": 0  // Populated from registry, not HomeKit
        ]
    }

    // MARK: - Discovery

    /// Discovers all homes, rooms, accessories, characteristics, and scenes.
    /// Returns complete HomeKit topology for display and device lookup.
    /// - Returns: Dictionary with keys "homes" (array of home objects) and "summary" (human-readable count string)
    func discover() async throws -> [String: Any] {
        try await waitForReady()

        let homes = homeManager.homes.map { home -> [String: Any] in
            let rooms = home.rooms.map { room -> [String: Any] in
                let accessories = room.accessories.map { accessory -> [String: Any] in
                    let characteristics = accessory.services.flatMap { $0.characteristics }.map { char -> [String: Any] in
                        var charDict: [String: Any] = [
                            "type": characteristicTypeName(char.characteristicType),
                            "writable": char.properties.contains(HMCharacteristicPropertyWritable)
                        ]
                        if let value = char.value {
                            charDict["value"] = value
                        }
                        if let metadata = char.metadata {
                            if let min = metadata.minimumValue {
                                charDict["min"] = min
                            }
                            if let max = metadata.maximumValue {
                                charDict["max"] = max
                            }
                        }
                        return charDict
                    }

                    return [
                        "uuid": accessory.uniqueIdentifier.uuidString,
                        "name": accessory.name,
                        "category": categoryName(accessory.category),
                        "reachable": accessory.isReachable,
                        "characteristics": characteristics
                    ]
                }

                return [
                    "name": room.name,
                    "accessories": accessories
                ]
            }

            let scenes = home.actionSets.map { actionSet -> [String: Any] in
                [
                    "uuid": actionSet.uniqueIdentifier.uuidString,
                    "name": actionSet.name,
                    "actions": actionSet.actions.count
                ]
            }

            return [
                "name": home.name,
                "isPrimary": home == homeManager.primaryHome,
                "rooms": rooms,
                "scenes": scenes
            ]
        }

        let totalAccessories = homeManager.homes.flatMap { $0.accessories }.count
        let totalRooms = homeManager.homes.flatMap { $0.rooms }.count
        let totalScenes = homeManager.homes.flatMap { $0.actionSets }.count

        return [
            "homes": homes,
            "summary": "\(homeManager.homes.count) home(s), \(totalRooms) rooms, \(totalAccessories) accessories, \(totalScenes) scenes"
        ]
    }

    // MARK: - Device Control

    /// Retrieves the complete state of a device (all its characteristics).
    /// - Parameters:
    ///   - nameOrUuid: Device name (exact or fuzzy match) or UUID string
    /// - Returns: Dictionary with device info including "device", "uuid", "room", "reachable", "category", "state" (characteristic values)
    /// - Throws: HomeKitError.deviceNotFound if accessory not found
    func getDevice(nameOrUuid: String) async throws -> [String: Any] {
        try await waitForReady()
        guard let accessory = findAccessory(nameOrUuid) else {
            throw HomeKitError.deviceNotFound(nameOrUuid)
        }
        return accessoryState(accessory)
    }

    /// Sets a characteristic value on a device.
    /// Validates that the characteristic is writable before attempting the write.
    /// - Parameters:
    ///   - nameOrUuid: Device name (exact or fuzzy match) or UUID string
    ///   - characteristic: Characteristic type name (e.g., "power", "brightness", "lockState")
    ///   - value: New value; strings are coerced to appropriate types (e.g., "true" → Bool, "50" → Int)
    /// - Returns: Dictionary confirming the change with "device", "characteristic", "previousValue", "newValue", "confirmed"
    /// - Throws: HomeKitError for device not found, characteristic not found, or read-only characteristic
    func setDevice(nameOrUuid: String, characteristic: String, value: Any) async throws -> [String: Any] {
        try await waitForReady()
        guard let accessory = findAccessory(nameOrUuid) else {
            throw HomeKitError.deviceNotFound(nameOrUuid)
        }

        guard let char = findCharacteristic(accessory: accessory, type: characteristic) else {
            throw HomeKitError.characteristicNotFound(characteristic, accessory.name)
        }

        guard char.properties.contains(HMCharacteristicPropertyWritable) else {
            throw HomeKitError.readOnly(characteristic, accessory.name)
        }

        let previousValue = char.value

        // Convert value to the appropriate type
        let convertedValue = convertValue(value, for: char)

        try await char.writeValue(convertedValue)

        return [
            "device": accessory.name,
            "characteristic": characteristic,
            "previousValue": previousValue as Any,
            "newValue": convertedValue,
            "confirmed": true
        ]
    }

    // MARK: - Scenes

    /// Lists all scenes (action sets) across all homes or in a specific home.
    /// - Parameters:
    ///   - homeName: Optional; if provided, filters scenes to only this home
    /// - Returns: Array of scene objects with "uuid", "name", "actions" (count), "home"
    func listScenes(homeName: String? = nil) async throws -> [[String: Any]] {
        try await waitForReady()
        let homes = homeName != nil
            ? homeManager.homes.filter { $0.name == homeName }
            : homeManager.homes

        return homes.flatMap { home in
            home.actionSets.map { actionSet in
                [
                    "uuid": actionSet.uniqueIdentifier.uuidString,
                    "name": actionSet.name,
                    "actions": actionSet.actions.count,
                    "home": home.name
                ] as [String: Any]
            }
        }
    }

    /// Executes a scene (action set) by name or UUID.
    /// - Parameters:
    ///   - nameOrUuid: Scene name (exact match) or UUID string
    /// - Returns: Dictionary with "scene" (name), "actionsExecuted" (count), "confirmed"
    /// - Throws: HomeKitError.sceneNotFound if scene not found
    func triggerScene(nameOrUuid: String) async throws -> [String: Any] {
        try await waitForReady()

        for home in homeManager.homes {
            for actionSet in home.actionSets {
                if actionSet.name == nameOrUuid ||
                   actionSet.uniqueIdentifier.uuidString == nameOrUuid {
                    try await home.executeActionSet(actionSet)
                    return [
                        "scene": actionSet.name,
                        "actionsExecuted": actionSet.actions.count,
                        "confirmed": true
                    ]
                }
            }
        }

        throw HomeKitError.sceneNotFound(nameOrUuid)
    }

    // MARK: - Rooms

    /// Lists all rooms across all homes or in a specific home, with accessories in each room.
    /// - Parameters:
    ///   - homeName: Optional; if provided, filters rooms to only this home
    /// - Returns: Array of room objects with "name", "home", "accessoryCount", "accessories" (array of device info)
    func listRooms(homeName: String? = nil) async throws -> [[String: Any]] {
        try await waitForReady()
        let homes = homeName != nil
            ? homeManager.homes.filter { $0.name == homeName }
            : homeManager.homes

        return homes.flatMap { home in
            home.rooms.map { room in
                [
                    "name": room.name,
                    "home": home.name,
                    "accessoryCount": room.accessories.count,
                    "accessories": room.accessories.map { acc in
                        ["name": acc.name, "category": categoryName(acc.category)]
                    }
                ] as [String: Any]
            }
        }
    }

    // MARK: - Private Helpers

    /// Finds an accessory by exact name, exact UUID, or fuzzy name match (case-insensitive substring).
    /// FUZZY MATCHING LOGIC:
    /// 1. First pass: exact name match or exact UUID match
    /// 2. Second pass: case-insensitive substring search on device names
    /// This allows "light" to match a device named "Living Room Light" when exact match fails.
    /// - Parameters:
    ///   - nameOrUuid: Device name (any case) or UUID string
    /// - Returns: First matching HMAccessory or nil if not found
    private func findAccessory(_ nameOrUuid: String) -> HMAccessory? {
        for home in homeManager.homes {
            for accessory in home.accessories {
                if accessory.name == nameOrUuid ||
                   accessory.uniqueIdentifier.uuidString == nameOrUuid {
                    return accessory
                }
            }
        }
        // Fuzzy match by lowercased name
        let lower = nameOrUuid.lowercased()
        for home in homeManager.homes {
            for accessory in home.accessories where accessory.name.lowercased().contains(lower) {
                return accessory
            }
        }
        return nil
    }

    /// Finds a characteristic by its friendly name (e.g., "power", "brightness") or UUID.
    /// Searches all services and characteristics on the accessory.
    /// - Parameters:
    ///   - accessory: The HMAccessory to search
    ///   - type: Characteristic name like "power", "brightness", "lockState", etc.
    /// - Returns: Matching HMCharacteristic or nil
    private func findCharacteristic(accessory: HMAccessory, type: String) -> HMCharacteristic? {
        let targetType = characteristicUUID(for: type)
        for service in accessory.services {
            for char in service.characteristics {
                if char.characteristicType == targetType ||
                   characteristicTypeName(char.characteristicType) == type {
                    return char
                }
            }
        }
        return nil
    }

    /// Collects all characteristic values from an accessory into a single state dictionary.
    /// Includes device metadata like reachability, room, and category.
    /// - Parameters:
    ///   - accessory: The HMAccessory to snapshot
    /// - Returns: Dictionary with "device", "uuid", "room", "reachable", "category", and "state" (all characteristics)
    private func accessoryState(_ accessory: HMAccessory) -> [String: Any] {
        var state: [String: Any] = [:]
        for service in accessory.services {
            for char in service.characteristics {
                let name = characteristicTypeName(char.characteristicType)
                if let value = char.value {
                    state[name] = value
                }
            }
        }

        let room = accessory.room?.name ?? "Default Room"
        return [
            "device": accessory.name,
            "uuid": accessory.uniqueIdentifier.uuidString,
            "room": room,
            "reachable": accessory.isReachable,
            "category": categoryName(accessory.category),
            "state": state
        ]
    }

    /// Coerces a JSON-decoded value to the appropriate type for HomeKit.
    /// STRING-TO-TYPE COERCION LOGIC:
    /// 1. Boolean strings: "true", "on", "locked", "open" → true; "false", "off", "unlocked", "closed" → false
    /// 2. Numeric strings: attempts Int parse, then Double parse
    /// 3. Other strings and non-strings: passed through unchanged
    /// This enables CLI tools to send string values that are automatically converted to the right type.
    /// - Parameters:
    ///   - value: Any value (typically from JSON or string CLI argument)
    ///   - characteristic: The HMCharacteristic to determine expected type (currently unused but reserved for future enhancement)
    /// - Returns: Coerced value suitable for HMCharacteristic.writeValue(_:)
    private func convertValue(_ value: Any, for characteristic: HMCharacteristic) -> Any {
        // Handle boolean strings
        if let str = value as? String {
            switch str.lowercased() {
            case "true", "on", "locked", "open": return true
            case "false", "off", "unlocked", "closed": return false
            default: break
            }
            if let intVal = Int(str) { return intVal }
            if let doubleVal = Double(str) { return doubleVal }
        }
        return value
    }

    // MARK: - Characteristic & Category Mappings

    /// Maps HomeKit characteristic UUIDs to human-readable names.
    /// This table is the source of truth for names used in CLI commands and JSON responses.
    /// Common characteristics: "power", "brightness", "hue", "saturation", "temperature" variants,
    /// "lockState", "position" variants, "motionDetected", "contactState", "batteryLevel", etc.
    private static let characteristicTypeNames: [String: String] = [
        HMCharacteristicTypePowerState: "power",
        HMCharacteristicTypeBrightness: "brightness",
        HMCharacteristicTypeHue: "hue",
        HMCharacteristicTypeSaturation: "saturation",
        HMCharacteristicTypeColorTemperature: "colorTemperature",
        HMCharacteristicTypeTargetTemperature: "targetTemperature",
        HMCharacteristicTypeCurrentTemperature: "currentTemperature",
        HMCharacteristicTypeTargetHeatingCooling: "hvacMode",
        HMCharacteristicTypeCurrentHeatingCooling: "currentHeatingCoolingState",
        HMCharacteristicTypeLockMechanismTargetState: "lockState",
        HMCharacteristicTypeLockMechanismCurrentState: "currentLockState",
        HMCharacteristicTypeTargetDoorState: "targetPosition",
        HMCharacteristicTypeCurrentDoorState: "currentPosition",
        HMCharacteristicTypeTargetPosition: "targetPosition",
        HMCharacteristicTypeCurrentPosition: "currentPosition",
        HMCharacteristicTypeRotationSpeed: "rotationSpeed",
        HMCharacteristicTypeRotationDirection: "rotationDirection",
        HMCharacteristicTypeSwingMode: "swingMode",
        HMCharacteristicTypeActive: "active",
        HMCharacteristicTypeMotionDetected: "motionDetected",
        HMCharacteristicTypeContactState: "contactState",
        HMCharacteristicTypeBatteryLevel: "batteryLevel",
        HMCharacteristicTypeTargetRelativeHumidity: "targetHumidity",
        HMCharacteristicTypeCurrentRelativeHumidity: "currentHumidity",
        HMCharacteristicTypeCurrentLightLevel: "lightLevel"
    ]

    /// Converts a HomeKit characteristic UUID to a friendly name.
    /// - Parameters:
    ///   - type: HomeKit characteristic UUID constant (e.g., HMCharacteristicTypePowerState)
    /// - Returns: Friendly name (e.g., "power") or the UUID itself if unmapped
    private func characteristicTypeName(_ type: String) -> String {
        Self.characteristicTypeNames[type] ?? type
    }

    /// Lookup table from friendly name to HomeKit characteristic UUID.
    private static let characteristicUUIDs: [String: String] = [
        "power": HMCharacteristicTypePowerState,
        "brightness": HMCharacteristicTypeBrightness,
        "hue": HMCharacteristicTypeHue,
        "saturation": HMCharacteristicTypeSaturation,
        "colorTemperature": HMCharacteristicTypeColorTemperature,
        "targetTemperature": HMCharacteristicTypeTargetTemperature,
        "hvacMode": HMCharacteristicTypeTargetHeatingCooling,
        "lockState": HMCharacteristicTypeLockMechanismTargetState,
        "targetPosition": HMCharacteristicTypeTargetPosition,
        "rotationSpeed": HMCharacteristicTypeRotationSpeed,
        "active": HMCharacteristicTypeActive,
        "targetHumidity": HMCharacteristicTypeTargetRelativeHumidity
    ]

    /// Reverse mapping: converts friendly names back to HomeKit characteristic UUIDs.
    /// Used when parsing CLI commands that reference characteristics by friendly names.
    /// - Parameters:
    ///   - name: Friendly name (e.g., "power", "brightness", "lockState")
    /// - Returns: HomeKit characteristic UUID constant or the name itself if unmapped
    private func characteristicUUID(for name: String) -> String {
        Self.characteristicUUIDs[name] ?? name
    }

    /// Lookup table from accessory category type to display name.
    private static let categoryNames: [String: String] = [
        HMAccessoryCategoryTypeLightbulb: "light",
        HMAccessoryCategoryTypeThermostat: "thermostat",
        HMAccessoryCategoryTypeDoorLock: "lock",
        HMAccessoryCategoryTypeGarageDoorOpener: "garageDoor",
        HMAccessoryCategoryTypeFan: "fan",
        HMAccessoryCategoryTypeWindowCovering: "windowCovering",
        HMAccessoryCategoryTypeSwitch: "switch",
        HMAccessoryCategoryTypeOutlet: "outlet",
        HMAccessoryCategoryTypeSensor: "sensor",
        HMAccessoryCategoryTypeDoor: "door",
        HMAccessoryCategoryTypeWindow: "window"
    ]

    /// Maps HomeKit accessory categories to display names.
    /// Categories help CLI tools categorize devices (e.g., "light", "thermostat", "lock").
    /// - Parameters:
    ///   - category: The HMAccessoryCategory from a device
    /// - Returns: Friendly category name or the raw category type if unmapped
    private func categoryName(_ category: HMAccessoryCategory) -> String {
        Self.categoryNames[category.categoryType] ?? category.categoryType
    }
}

// MARK: - Errors

/// Errors that can occur during HomeKit operations.
///
/// Case details:
/// - `deviceNotFound`: No accessory matched the provided name or UUID
/// - `characteristicNotFound`: Device doesn't support the requested characteristic
/// - `readOnly`: Characteristic is read-only and cannot be written
/// - `sceneNotFound`: No scene (action set) matched the provided name or UUID
/// - `notReady`: HomeKit has not finished loading homes from iCloud; call waitForReady() first
enum HomeKitError: LocalizedError {
    /// Device name/UUID did not match any accessory
    case deviceNotFound(String)
    /// Device lacks the requested characteristic
    case characteristicNotFound(String, String)
    /// Characteristic is read-only on this device
    case readOnly(String, String)
    /// Scene name/UUID did not match any action set
    case sceneNotFound(String)
    /// HomeKit data not yet loaded from iCloud
    case notReady

    var errorDescription: String? {
        switch self {
        case .deviceNotFound(let name):
            return "Device not found: \(name)"
        case .characteristicNotFound(let char, let device):
            return "\(device) doesn't have a '\(char)' characteristic"
        case .readOnly(let char, let device):
            return "\(char) on \(device) is read-only"
        case .sceneNotFound(let name):
            return "Scene not found: \(name)"
        case .notReady:
            return "HomeKit is not ready. Make sure you're signed into iCloud."
        }
    }
}
