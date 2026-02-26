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
        Settings {
            SettingsView()
        }
    }
}
