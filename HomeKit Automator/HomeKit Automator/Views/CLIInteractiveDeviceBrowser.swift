// DeviceBrowser.swift
// Interactive device browser for CLI with filtering and search.

import Foundation

/// Interactive device browser for selecting HomeKit devices.
struct DeviceBrowser {
    
    private let apiClient: HelperAPIClient
    
    init(apiClient: HelperAPIClient = .shared) {
        self.apiClient = apiClient
    }
    
    // MARK: - Public Interface
    
    /// Interactively browse and select a device.
    func selectDevice(
        prompt: String = "Select a device",
        filter: DeviceFilter? = nil
    ) async throws -> AccessoryInfo? {
        Terminal.print(Terminal.header("🏠 Device Browser"))
        
        // Fetch device map
        let deviceMap = try await InteractivePrompts.withSpinner("Loading devices") {
            try await apiClient.getDeviceMap()
        }
        
        guard !deviceMap.homes.isEmpty else {
            Terminal.printError("No HomeKit homes found")
            return nil
        }
        
        // Flatten to list of devices
        var allDevices: [(home: String, room: String?, device: AccessoryInfo)] = []
        for home in deviceMap.homes {
            for device in home.accessories {
                allDevices.append((home.name, device.room, device))
            }
        }
        
        // Apply filter if provided
        if let filter = filter {
            allDevices = allDevices.filter { filter.matches($0.device) }
        }
        
        guard !allDevices.isEmpty else {
            Terminal.printError("No devices match the filter")
            return nil
        }
        
        // Show interactive selection
        return try await showDeviceSelection(
            prompt: prompt,
            devices: allDevices
        )
    }
    
    /// Browse devices with full interactive interface.
    func browse() async throws {
        Terminal.print(Terminal.header("🏠 HomeKit Device Browser"))
        
        let deviceMap = try await InteractivePrompts.withSpinner("Loading devices") {
            try await apiClient.getDeviceMap()
        }
        
        guard !deviceMap.homes.isEmpty else {
            Terminal.printError("No HomeKit homes found")
            return
        }
        
        // Show homes
        Terminal.print("\n" + Terminal.bold("Homes:"))
        for home in deviceMap.homes {
            Terminal.print("  • " + Terminal.colored(home.name, .cyan))
            Terminal.print("    Rooms: \(home.rooms.count), Devices: \(home.accessories.count)")
        }
        
        // Browse by home
        let homeChoice = InteractivePrompts.promptChoice(
            "\nSelect a home to browse",
            options: deviceMap.homes.map { $0.name } + ["View all devices"],
            display: { $0 },
            allowCancel: true
        )
        
        guard let choice = homeChoice else {
            return
        }
        
        if choice == "View all devices" {
            try await showAllDevices(deviceMap)
        } else {
            guard let home = deviceMap.homes.first(where: { $0.name == choice }) else {
                return
            }
            try await showHomeDevices(home)
        }
    }
    
    /// Search devices by name or characteristic.
    func searchDevices(query: String) async throws -> [AccessoryInfo] {
        let deviceMap = try await apiClient.getDeviceMap()
        
        var results: [AccessoryInfo] = []
        let lowercaseQuery = query.lowercased()
        
        for home in deviceMap.homes {
            for device in home.accessories {
                // Search in device name
                if device.name.lowercased().contains(lowercaseQuery) {
                    results.append(device)
                    continue
                }
                
                // Search in room name
                if device.room?.lowercased().contains(lowercaseQuery) == true {
                    results.append(device)
                    continue
                }
                
                // Search in characteristics
                if device.characteristics.contains(where: { $0.name.lowercased().contains(lowercaseQuery) }) {
                    results.append(device)
                }
            }
        }
        
        return results
    }
    
    // MARK: - Private Helpers
    
    private func showDeviceSelection(
        prompt: String,
        devices: [(home: String, room: String?, device: AccessoryInfo)]
    ) async throws -> AccessoryInfo? {
        Terminal.print("\n" + Terminal.bold(prompt) + "\n")
        
        for (index, item) in devices.enumerated() {
            let number = Terminal.dim("  \(index + 1).")
            let roomText = item.room.map { " (\($0))" } ?? ""
            let homeText = Terminal.dim(" — \(item.home)")
            
            Terminal.print("\(number) \(item.device.name)\(roomText)\(homeText)")
        }
        
        Terminal.print(Terminal.dim("  0.") + " Cancel")
        
        while true {
            Terminal.print("\n" + Terminal.bold("Enter number") + " (0-\(devices.count)): ", terminator: "")
            
            guard let input = readLine(),
                  let choice = Int(input),
                  choice >= 0 && choice <= devices.count else {
                Terminal.printError("Invalid selection")
                continue
            }
            
            if choice == 0 {
                return nil
            }
            
            return devices[choice - 1].device
        }
    }
    
    private func showAllDevices(_ deviceMap: DeviceMapResponse) async throws {
        Terminal.print(Terminal.section("All Devices"))
        
        var allDevices: [(home: String, room: String?, device: AccessoryInfo)] = []
        for home in deviceMap.homes {
            for device in home.accessories {
                allDevices.append((home.name, device.room, device))
            }
        }
        
        // Group by room
        let byRoom = Dictionary(grouping: allDevices) { $0.room ?? "No Room" }
        
        for (room, devices) in byRoom.sorted(by: { $0.key < $1.key }) {
            Terminal.print("\n" + Terminal.bold(room))
            for (_, _, device) in devices {
                Terminal.print("  \(deviceIcon(for: device.category)) \(device.name)")
                
                // Show key characteristics
                let keyChars = device.characteristics.prefix(3)
                for char in keyChars {
                    if let value = char.value {
                        Terminal.print(Terminal.dim("     └─ \(char.name): \(value.displayString)"))
                    }
                }
            }
        }
        
        // Ask if user wants details on a device
        if InteractivePrompts.promptYesNo("\nView details for a device?", default: false) {
            if let selected = try await showDeviceSelection(prompt: "Select device", devices: allDevices) {
                showDeviceDetails(selected)
            }
        }
    }
    
    private func showHomeDevices(_ home: HomeInfo) async throws {
        Terminal.print(Terminal.section("Home: \(home.name)"))
        
        Terminal.print("\nRooms: \(home.rooms.count)")
        Terminal.print("Devices: \(home.accessories.count)")
        
        // Group by room
        let byRoom = Dictionary(grouping: home.accessories) { $0.room ?? "No Room" }
        
        Terminal.print("\n" + Terminal.bold("Devices by Room:"))
        for (room, devices) in byRoom.sorted(by: { $0.key < $1.key }) {
            Terminal.print("\n  " + Terminal.colored(room, .cyan))
            for device in devices {
                Terminal.print("    \(deviceIcon(for: device.category)) \(device.name)")
            }
        }
        
        // Options
        let action = InteractivePrompts.promptChoice(
            "\nWhat would you like to do?",
            options: [
                "View device details",
                "Filter by room",
                "Search devices",
                "Back"
            ],
            display: { $0 }
        )
        
        switch action {
        case "View device details":
            let devices = home.accessories.map { (home.name, $0.room, $0) }
            if let selected = try await showDeviceSelection(prompt: "Select device", devices: devices) {
                showDeviceDetails(selected)
            }
            
        case "Filter by room":
            try await filterByRoom(home)
            
        case "Search devices":
            try await searchInHome(home)
            
        default:
            break
        }
    }
    
    private func filterByRoom(_ home: HomeInfo) async throws {
        let rooms = home.rooms.map { $0.name }
        
        guard let room = InteractivePrompts.promptChoice(
            "Select a room",
            options: rooms,
            display: { $0 },
            allowCancel: true
        ) else {
            return
        }
        
        let devicesInRoom = home.accessories.filter { $0.room == room }
        
        Terminal.print("\n" + Terminal.section("Devices in \(room)"))
        
        for device in devicesInRoom {
            Terminal.print("  \(deviceIcon(for: device.category)) \(device.name)")
            
            // Show online status and key characteristics
            let keyChars = device.characteristics.prefix(2)
            for char in keyChars {
                if let value = char.value {
                    Terminal.print(Terminal.dim("     └─ \(char.name): \(value.displayString)"))
                }
            }
        }
    }
    
    private func searchInHome(_ home: HomeInfo) async throws {
        let query = InteractivePrompts.promptText("Search query")
        
        let results = home.accessories.filter {
            $0.name.lowercased().contains(query.lowercased()) ||
            $0.characteristics.contains(where: { $0.name.lowercased().contains(query.lowercased()) })
        }
        
        if results.isEmpty {
            Terminal.printWarning("No devices match '\(query)'")
        } else {
            Terminal.printSuccess("Found \(results.count) device(s)")
            for device in results {
                Terminal.print("  • \(device.name) (\(device.room ?? "No Room"))")
            }
        }
    }
    
    private func showDeviceDetails(_ device: AccessoryInfo) {
        Terminal.print("\n" + Terminal.header("Device Details"))
        
        Terminal.print(Terminal.bold("Name:") + " \(device.name)")
        Terminal.print(Terminal.bold("UUID:") + " " + Terminal.dim(device.uuid))
        Terminal.print(Terminal.bold("Room:") + " \(device.room ?? "No Room")")
        Terminal.print(Terminal.bold("Category:") + " \(device.category)")
        
        Terminal.print("\n" + Terminal.bold("Characteristics:"))
        
        for char in device.characteristics {
            let value = char.value?.displayString ?? "null"
            let format = char.format.map { " (\($0))" } ?? ""
            Terminal.print("  • \(char.name): " + Terminal.colored(value, .cyan) + Terminal.dim(format))
        }
    }
    
    private func deviceIcon(for category: String) -> String {
        switch category.lowercased() {
        case "lightbulb", "light":
            return "💡"
        case "switch":
            return "🎚"
        case "outlet":
            return "🔌"
        case "thermostat":
            return "🌡"
        case "lock":
            return "🔒"
        case "garage":
            return "🚗"
        case "fan":
            return "🌀"
        case "window":
            return "🪟"
        case "door":
            return "🚪"
        case "sensor":
            return "📡"
        case "camera":
            return "📷"
        case "speaker":
            return "🔊"
        case "television", "tv":
            return "📺"
        default:
            return "📱"
        }
    }
}

// MARK: - Device Filter

/// Filter criteria for device browsing.
struct DeviceFilter {
    let category: String?
    let room: String?
    let hasCharacteristic: String?
    
    func matches(_ device: AccessoryInfo) -> Bool {
        if let category = category {
            guard device.category.lowercased() == category.lowercased() else {
                return false
            }
        }
        
        if let room = room {
            guard device.room?.lowercased() == room.lowercased() else {
                return false
            }
        }
        
        if let characteristic = hasCharacteristic {
            guard device.characteristics.contains(where: {
                $0.name.lowercased() == characteristic.lowercased() ||
                $0.type.lowercased() == characteristic.lowercased()
            }) else {
                return false
            }
        }
        
        return true
    }
}
