// DeviceBrowser.swift
// Interactive device browser for CLI with search, filtering, and selection.

import Foundation

/// Interactive device browser for selecting HomeKit devices.
struct DeviceBrowser {
    
    // MARK: - Device Selection
    
    /// Prompts user to select a device interactively.
    static func selectDevice(
        prompt: String = "Select a device",
        apiClient: HelperAPIClient,
        roomFilter: String? = nil,
        typeFilter: String? = nil
    ) async throws -> DeviceSelection {
        
        Terminal.print("\n" + Terminal.header("Device Browser"))
        Terminal.print(Terminal.spinner("Loading devices..."))
        
        // Fetch device map
        let deviceMap = try await apiClient.getDeviceMap()
        
        // Clear loading message
        print("\u{001B}[1A\u{001B}[2K", terminator: "")
        Terminal.printSuccess("Loaded devices")
        
        // Extract all devices
        var allDevices: [(home: String, device: AccessoryInfo)] = []
        for home in deviceMap.homes {
            for accessory in home.accessories {
                // Apply filters
                if let roomFilter = roomFilter, accessory.room != roomFilter {
                    continue
                }
                if let typeFilter = typeFilter, accessory.category != typeFilter {
                    continue
                }
                allDevices.append((home: home.name, device: accessory))
            }
        }
        
        guard !allDevices.isEmpty else {
            Terminal.printError("No devices found matching criteria")
            throw DeviceBrowserError.noDevicesFound
        }
        
        // Show devices grouped by room
        Terminal.print("\n" + Terminal.bold(prompt) + "\n")
        
        // Group by room
        var devicesByRoom: [String: [(home: String, device: AccessoryInfo)]] = [:]
        for item in allDevices {
            let room = item.device.room ?? "No Room"
            devicesByRoom[room, default: []].append(item)
        }
        
        // Display devices
        var index = 1
        var deviceIndex: [Int: (home: String, device: AccessoryInfo)] = [:]
        
        for (room, devices) in devicesByRoom.sorted(by: { $0.key < $1.key }) {
            Terminal.print("\n" + Terminal.bold(room).cyan)
            
            for item in devices {
                let emoji = deviceEmoji(for: item.device.category)
                Terminal.print("  \(Terminal.dim(String(index) + ".")) \(emoji) \(item.device.name)")
                
                // Show some characteristics
                let charNames = item.device.characteristics.prefix(3).map { $0.name }
                if !charNames.isEmpty {
                    Terminal.print("     " + Terminal.dim("→ \(charNames.joined(separator: ", "))"))
                }
                
                deviceIndex[index] = item
                index += 1
            }
        }
        
        Terminal.print("")
        
        // Prompt for selection
        while true {
            Terminal.print(Terminal.bold("Enter device number") + " (1-\(deviceIndex.count)) or " + Terminal.dim("0 to cancel") + ": ", terminator: "")
            
            guard let input = readLine(),
                  let choice = Int(input) else {
                Terminal.printError("Invalid input")
                continue
            }
            
            if choice == 0 {
                throw DeviceBrowserError.cancelled
            }
            
            guard let selected = deviceIndex[choice] else {
                Terminal.printError("Invalid device number")
                continue
            }
            
            // Show selected device details
            Terminal.print("")
            Terminal.printSuccess("Selected: \(selected.device.name)")
            
            // Ask for characteristic
            let characteristic = try await selectCharacteristic(
                for: selected.device,
                prompt: "Which characteristic?"
            )
            
            return DeviceSelection(
                device: selected.device,
                home: selected.home,
                characteristic: characteristic
            )
        }
    }
    
    // MARK: - Characteristic Selection
    
    /// Prompts user to select a characteristic for a device.
    static func selectCharacteristic(
        for device: AccessoryInfo,
        prompt: String = "Select a characteristic"
    ) async throws -> CharacteristicInfo {
        
        guard !device.characteristics.isEmpty else {
            Terminal.printError("Device has no controllable characteristics")
            throw DeviceBrowserError.noCharacteristics
        }
        
        Terminal.print("\n" + Terminal.bold(prompt) + "\n")
        
        // Filter to writable characteristics (common ones)
        let writableChars = device.characteristics.filter { char in
            ["On", "Brightness", "Temperature", "Hue", "Saturation", "Lock Target State"].contains(char.name)
        }
        
        let chars = writableChars.isEmpty ? device.characteristics : writableChars
        
        for (index, char) in chars.enumerated() {
            let value = char.value?.displayString ?? "—"
            Terminal.print("  \(Terminal.dim(String(index + 1) + ".")) \(char.name) " + Terminal.dim("(current: \(value))"))
        }
        
        Terminal.print("")
        
        while true {
            Terminal.print(Terminal.bold("Enter number") + " (1-\(chars.count)): ", terminator: "")
            
            guard let input = readLine(),
                  let choice = Int(input),
                  choice > 0 && choice <= chars.count else {
                Terminal.printError("Invalid selection")
                continue
            }
            
            return chars[choice - 1]
        }
    }
    
    // MARK: - Value Input
    
    /// Prompts user to enter a value for a characteristic.
    static func promptValue(
        for characteristic: CharacteristicInfo,
        current: AnyCodableValue?
    ) -> AnyCodableValue {
        
        let charName = characteristic.name
        let currentStr = current?.displayString ?? "none"
        
        Terminal.print("\n" + Terminal.bold("Set value for \(charName)") + " " + Terminal.dim("(current: \(currentStr))") + "\n")
        
        // Determine type and prompt accordingly
        if charName == "On" {
            let value = InteractivePrompts.promptYesNo("Turn on?", default: true)
            return .bool(value)
        } else if charName == "Brightness" || charName == "Hue" || charName == "Saturation" {
            let max = charName == "Hue" ? 360 : 100
            let value = InteractivePrompts.promptNumber("Value", min: 0, max: max)
            return .int(value)
        } else if charName.contains("Temperature") {
            let value = InteractivePrompts.promptNumber("Temperature (°F)", min: 50, max: 90)
            return .int(value)
        } else if charName == "Lock Target State" {
            let locked = InteractivePrompts.promptYesNo("Lock?", default: true)
            return .int(locked ? 1 : 0)
        } else {
            // Generic prompt
            let value = InteractivePrompts.promptText("Value")
            
            // Try to parse as number
            if let int = Int(value) {
                return .int(int)
            } else if let double = Double(value) {
                return .double(double)
            } else if value.lowercased() == "true" {
                return .bool(true)
            } else if value.lowercased() == "false" {
                return .bool(false)
            } else {
                return .string(value)
            }
        }
    }
    
    // MARK: - Helpers
    
    private static func deviceEmoji(for category: String) -> String {
        switch category.lowercased() {
        case let cat where cat.contains("light"):
            return "💡"
        case let cat where cat.contains("switch"):
            return "🔌"
        case let cat where cat.contains("thermostat"):
            return "🌡️"
        case let cat where cat.contains("lock"):
            return "🔒"
        case let cat where cat.contains("door"):
            return "🚪"
        case let cat where cat.contains("window"):
            return "🪟"
        case let cat where cat.contains("sensor"):
            return "📡"
        case let cat where cat.contains("camera"):
            return "📹"
        case let cat where cat.contains("fan"):
            return "💨"
        case let cat where cat.contains("outlet"):
            return "🔌"
        case let cat where cat.contains("speaker"):
            return "🔊"
        case let cat where cat.contains("tv"):
            return "📺"
        default:
            return "🏠"
        }
    }
    
    // MARK: - Browse Mode
    
    /// Interactive browse mode for exploring devices.
    static func browse(apiClient: HelperAPIClient) async throws {
        Terminal.print("\n" + Terminal.header("HomeKit Device Browser"))
        Terminal.print(Terminal.spinner("Loading devices..."))
        
        let deviceMap = try await apiClient.getDeviceMap()
        
        print("\u{001B}[1A\u{001B}[2K", terminator: "")
        Terminal.printSuccess("Loaded \(deviceMap.homes.count) home(s)")
        
        for home in deviceMap.homes {
            Terminal.print("\n" + Terminal.section("🏠 \(home.name)"))
            
            // Group by room
            var devicesByRoom: [String: [AccessoryInfo]] = [:]
            for accessory in home.accessories {
                let room = accessory.room ?? "No Room"
                devicesByRoom[room, default: []].append(accessory)
            }
            
            for (room, devices) in devicesByRoom.sorted(by: { $0.key < $1.key }) {
                Terminal.print("\n  " + Terminal.bold(room).cyan)
                
                for device in devices {
                    let emoji = deviceEmoji(for: device.category)
                    Terminal.print("    \(emoji) \(device.name)")
                    
                    // Show characteristics
                    for char in device.characteristics.prefix(5) {
                        let value = char.value?.displayString ?? "—"
                        Terminal.print("       " + Terminal.dim("• \(char.name): \(value)"))
                    }
                }
            }
        }
        
        Terminal.print("")
    }
}

// MARK: - Types

struct DeviceSelection {
    let device: AccessoryInfo
    let home: String
    let characteristic: CharacteristicInfo
}

enum DeviceBrowserError: LocalizedError {
    case noDevicesFound
    case noCharacteristics
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .noDevicesFound:
            return "No devices found"
        case .noCharacteristics:
            return "Device has no controllable characteristics"
        case .cancelled:
            return "Selection cancelled"
        }
    }
}
