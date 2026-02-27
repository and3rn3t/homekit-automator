// HomeKitAutomatorApp.swift
// Main entry point for the HomeKit Automator menu bar application.
//
// This app runs as a macOS menu bar agent (no Dock icon) and manages:
// - The HomeKitHelper lifecycle (launch, monitor, restart)
// - The automation dashboard UI
// - Settings and execution history views

import SwiftUI

@main
struct HomeKitAutomatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Main window (opened from menu bar)
        Window("HomeKit Automator", id: "main") {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .defaultSize(width: 900, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
        
        // Settings window
        Settings {
            SettingsView()
        }
    }
}
