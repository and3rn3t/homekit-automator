// HomeKitHelperApp.swift
// Main entry point for the HomeKitHelper background agent.
// This app provides HomeKit framework access to the main HomeKit Automator app
// via Unix domain sockets.

import SwiftUI
import HomeKit

@main
struct HomeKitHelperApp: App {
    @NSApplicationDelegateAdaptor(HelperAppDelegate.self) var appDelegate
    
    var body: some Scene {
        // No windows - this is a background agent (LSUIElement = YES)
        Settings {
            EmptyView()
        }
    }
}

/// Application delegate managing the helper's lifecycle and services.
@MainActor
final class HelperAppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Services
    
    private var socketServer: SocketServer?
    private var homeKitManager: HomeKitManager?
    private var automationEngine: AutomationEngine?
    private var logger: HelperLogger?
    
    // MARK: - Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[HomeKitHelper] Starting...")
        
        // Initialize logger
        logger = HelperLogger.shared
        logger?.log("HomeKitHelper starting", level: .info)
        
        // Initialize HomeKit
        homeKitManager = HomeKitManager()
        
        // Initialize automation engine
        automationEngine = AutomationEngine(homeKitManager: homeKitManager!)
        
        // Start socket server
        Task {
            do {
                socketServer = try SocketServer(
                    homeKitManager: homeKitManager!,
                    automationEngine: automationEngine!
                )
                try await socketServer?.start()
                logger?.log("Socket server started successfully", level: .info)
            } catch {
                logger?.log("Failed to start socket server: \(error)", level: .error)
                // Don't exit - maybe user can fix permissions
            }
        }
        
        // Start automation engine
        Task {
            await automationEngine?.start()
            logger?.log("Automation engine started", level: .info)
        }
        
        logger?.log("HomeKitHelper ready", level: .info)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        logger?.log("HomeKitHelper terminating", level: .info)
        
        // Stop services
        Task {
            await automationEngine?.stop()
            await socketServer?.stop()
        }
        
        logger?.log("HomeKitHelper stopped", level: .info)
    }
    
    // Prevent app from terminating when windows are closed (no windows anyway)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
