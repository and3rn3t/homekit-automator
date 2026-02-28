// HomeKitManager.swift
// Manages HomeKit framework integration, device discovery, and control.

import Foundation
import HomeKit

/// Actor-based wrapper around HMHomeManager for thread-safe HomeKit access.
actor HomeKitManager: NSObject {
    
    // MARK: - Properties
    
    private var homeManager: HMHomeManager!
    private var isReady = false
    private var homesUpdateContinuation: CheckedContinuation<Void, Never>?
    
    private let logger = HelperLogger.shared
    
    // MARK: - Init
    
    override init() {
        super.init()
        homeManager = HMHomeManager()
        homeManager.delegate = self
    }
    
    /// Waits for HomeKit to be ready.
    private func ensureReady() async {
        guard !isReady else { return }
        
        await logger.log("Waiting for HomeKit to be ready...", level: .info)
        
        await withCheckedContinuation { continuation in
            homesUpdateContinuation = continuation
        }
        
        isReady = true
        await logger.log("HomeKit is ready", level: .info)
    }
    
    // MARK: - Authorization
    
    func isAuthorized() async -> Bool {
        await ensureReady()
        
        #if os(macOS)
        // On macOS, check if we have access to homes
        return !homeManager.homes.isEmpty || homeManager.primaryHome != nil
        #else
        return HMHomeManager.authorizationStatus() == .authorized
        #endif
    }
    
    // MARK: - Homes
    
    func listHomes() async throws -> [String] {
        await ensureReady()
        
        let names = homeManager.homes.map { $0.name }
        await logger.log("Listed \(names.count) homes", level: .debug)
        return names
    }
    
    func getPrimaryHome() async throws -> HMHome {
        await ensureReady()
        
        guard let home = homeManager.primaryHome ?? homeManager.homes.first else {
            throw HomeKitError.noHomeAvailable
        }
        
        return home
    }
    
    func getHome(name: String?) async throws -> HMHome {
        await ensureReady()
        
        if let name = name {
            guard let home = homeManager.homes.first(where: { $0.name == name }) else {
                throw HomeKitError.homeNotFound(name)
            }
            return home
        } else {
            return try await getPrimaryHome()
        }
    }
    
    // MARK: - Device Map
    
    func getDeviceMap() async throws -> DeviceMapResponse {
        await ensureReady()
        
        await logger.log("Generating device map", level: .debug)
        
        var homes: [HomeInfo] = []
        
        for home in homeManager.homes {
            var rooms: [RoomInfo] = []
            for room in home.rooms {
                rooms.append(RoomInfo(name: room.name, uuid: room.uniqueIdentifier.uuidString))
            }
            
            var accessories: [AccessoryInfo] = []
            for accessory in home.accessories {
                var characteristics: [CharacteristicInfo] = []
                
                for service in accessory.services {
                    for char in service.characteristics {
                        // Get current value
                        let value: AnyCodableValue?
                        if let val = char.value {
                            value = convertToAnyCodableValue(val)
                        } else {
                            value = nil
                        }
                        
                        characteristics.append(CharacteristicInfo(
                            name: char.localizedDescription,
                            type: char.characteristicType,
                            value: value,
                            format: char.metadata?.format?.rawValue
                        ))
                    }
                }
                
                accessories.append(AccessoryInfo(
                    name: accessory.name,
                    uuid: accessory.uniqueIdentifier.uuidString,
                    room: accessory.room?.name,
                    category: accessory.category.categoryType,
                    characteristics: characteristics
                ))
            }
            
            homes.append(HomeInfo(
                name: home.name,
                uuid: home.uniqueIdentifier.uuidString,
                rooms: rooms,
                accessories: accessories
            ))
        }
        
        await logger.log("Generated device map with \(accessories.count) accessories", level: .info)
        
        return DeviceMapResponse(homes: homes)
    }
    
    // MARK: - Devices
    
    func listDevices(home homeName: String?) async throws -> [AccessoryInfo] {
        let home = try await getHome(name: homeName)
        
        var devices: [AccessoryInfo] = []
        for accessory in home.accessories {
            var characteristics: [CharacteristicInfo] = []
            
            for service in accessory.services {
                for char in service.characteristics {
                    let value: AnyCodableValue?
                    if let val = char.value {
                        value = convertToAnyCodableValue(val)
                    } else {
                        value = nil
                    }
                    
                    characteristics.append(CharacteristicInfo(
                        name: char.localizedDescription,
                        type: char.characteristicType,
                        value: value,
                        format: char.metadata?.format?.rawValue
                    ))
                }
            }
            
            devices.append(AccessoryInfo(
                name: accessory.name,
                uuid: accessory.uniqueIdentifier.uuidString,
                room: accessory.room?.name,
                category: accessory.category.categoryType,
                characteristics: characteristics
            ))
        }
        
        return devices
    }
    
    func getDevice(uuid: String) async throws -> AccessoryInfo {
        let devices = try await listDevices(home: nil)
        
        guard let device = devices.first(where: { $0.uuid == uuid }) else {
            throw HomeKitError.deviceNotFound(uuid)
        }
        
        return device
    }
    
    // MARK: - Characteristic Control
    
    func setCharacteristic(deviceUUID: String, characteristic charName: String, value: Any) async throws {
        await ensureReady()
        
        // Find accessory
        var targetAccessory: HMAccessory?
        for home in homeManager.homes {
            if let accessory = home.accessories.first(where: { $0.uniqueIdentifier.uuidString == deviceUUID }) {
                targetAccessory = accessory
                break
            }
        }
        
        guard let accessory = targetAccessory else {
            throw HomeKitError.deviceNotFound(deviceUUID)
        }
        
        // Find characteristic
        var targetChar: HMCharacteristic?
        for service in accessory.services {
            if let char = service.characteristics.first(where: { 
                $0.localizedDescription == charName || $0.characteristicType == charName 
            }) {
                targetChar = char
                break
            }
        }
        
        guard let characteristic = targetChar else {
            throw HomeKitError.characteristicNotFound(charName)
        }
        
        // Write value
        await logger.log("Writing \(value) to \(accessory.name).\(charName)", level: .info)
        
        try await characteristic.writeValue(value)
        
        await logger.log("Successfully wrote value", level: .debug)
    }
    
    // MARK: - Scenes
    
    func listScenes(home homeName: String?) async throws -> ScenesResponse {
        let home = try await getHome(name: homeName)
        
        let scenes = home.actionSets.map { scene in
            SceneInfo(name: scene.name, uuid: scene.uniqueIdentifier.uuidString)
        }
        
        return ScenesResponse(scenes: scenes)
    }
    
    func activateScene(name: String) async throws {
        await ensureReady()
        
        await logger.log("Activating scene: \(name)", level: .info)
        
        // Find scene in all homes
        var targetScene: HMActionSet?
        for home in homeManager.homes {
            if let scene = home.actionSets.first(where: { $0.name == name }) {
                targetScene = scene
                break
            }
        }
        
        guard let scene = targetScene else {
            throw HomeKitError.sceneNotFound(name)
        }
        
        try await scene.home.executeActionSet(scene)
        
        await logger.log("Scene activated successfully", level: .info)
    }
    
    // MARK: - Helpers
    
    private func convertToAnyCodableValue(_ value: Any) -> AnyCodableValue {
        switch value {
        case let str as String:
            return .string(str)
        case let int as Int:
            return .int(int)
        case let double as Double:
            return .double(double)
        case let bool as Bool:
            return .bool(bool)
        case let array as [Any]:
            return .array(array.map(convertToAnyCodableValue))
        case let dict as [String: Any]:
            return .dictionary(dict.mapValues(convertToAnyCodableValue))
        default:
            return .string(String(describing: value))
        }
    }
}

// MARK: - HMHomeManagerDelegate

extension HomeKitManager: HMHomeManagerDelegate {
    
    nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task {
            await logger.log("HomeKit homes updated", level: .debug)
            
            if let continuation = await homesUpdateContinuation {
                await MainActor.run {
                    continuation.resume()
                }
                await clearContinuation()
            }
        }
    }
    
    private func clearContinuation() {
        homesUpdateContinuation = nil
    }
    
    nonisolated func homeManager(_ manager: HMHomeManager, didAdd home: HMHome) {
        Task {
            await logger.log("Home added: \(home.name)", level: .info)
        }
    }
    
    nonisolated func homeManager(_ manager: HMHomeManager, didRemove home: HMHome) {
        Task {
            await logger.log("Home removed: \(home.name)", level: .info)
        }
    }
}

// MARK: - Errors

enum HomeKitError: LocalizedError {
    case noHomeAvailable
    case homeNotFound(String)
    case deviceNotFound(String)
    case characteristicNotFound(String)
    case sceneNotFound(String)
    case writeValueFailed
    case unauthorized
    
    var errorDescription: String? {
        switch self {
        case .noHomeAvailable:
            return "No HomeKit home is available"
        case .homeNotFound(let name):
            return "Home not found: \(name)"
        case .deviceNotFound(let uuid):
            return "Device not found: \(uuid)"
        case .characteristicNotFound(let name):
            return "Characteristic not found: \(name)"
        case .sceneNotFound(let name):
            return "Scene not found: \(name)"
        case .writeValueFailed:
            return "Failed to write characteristic value"
        case .unauthorized:
            return "HomeKit access not authorized"
        }
    }
}
