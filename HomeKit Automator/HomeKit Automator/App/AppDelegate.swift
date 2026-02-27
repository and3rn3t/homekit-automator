// AppDelegate.swift
// Manages the NSStatusBar menu bar item, health-check timer, and window lifecycle
// for the HomeKit Automator menu bar app.

import AppKit
import SwiftUI
import ServiceManagement

/// Application delegate that owns the menu bar status item and orchestrates
/// periodic health checks against the HomeKitHelper process.
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var healthCheckTimer: Timer?
    private var dashboardWindow: NSWindow?
    private var historyWindow: NSWindow?

    let helperManager = HelperManager()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        startHealthCheckTimer()
        // Launch helper on startup
        Task {
            await helperManager.launchHelper()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "house.fill", accessibilityDescription: "HomeKit Automator")
        }

        let menu = NSMenu()

        statusMenuItem = NSMenuItem(title: "Status: Checking…", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())
        
        let mainWindowItem = NSMenuItem(title: "Show Automations…", action: #selector(openMainWindow), keyEquivalent: "a")
        mainWindowItem.target = self
        menu.addItem(mainWindowItem)

        let dashboardItem = NSMenuItem(title: "Legacy Dashboard…", action: #selector(openDashboard), keyEquivalent: "d")
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        let historyItem = NSMenuItem(title: "History…", action: #selector(openHistory), keyEquivalent: "h")
        historyItem.target = self
        menu.addItem(historyItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let restartHelperItem = NSMenuItem(title: "Restart Helper", action: #selector(restartHelper), keyEquivalent: "r")
        restartHelperItem.target = self
        menu.addItem(restartHelperItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Health Check Timer

    private func startHealthCheckTimer() {
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.performHealthCheck()
            }
        }
        // Run an initial check immediately
        Task {
            await performHealthCheck()
        }
    }

    private func performHealthCheck() async {
        await helperManager.healthCheck()

        await MainActor.run {
            switch helperManager.helperStatus {
            case .running:
                statusMenuItem.title = "Status: Connected"
                statusItem.button?.image = NSImage(
                    systemSymbolName: "house.fill",
                    accessibilityDescription: "HomeKit Automator – Connected"
                )
            case .stopped:
                statusMenuItem.title = "Status: Disconnected"
                statusItem.button?.image = NSImage(
                    systemSymbolName: "house",
                    accessibilityDescription: "HomeKit Automator – Disconnected"
                )
            case .error:
                statusMenuItem.title = "Status: Error"
                statusItem.button?.image = NSImage(
                    systemSymbolName: "house.fill",
                    accessibilityDescription: "HomeKit Automator – Error"
                )
            case .restarting:
                statusMenuItem.title = "Status: Restarting…"
                statusItem.button?.image = NSImage(
                    systemSymbolName: "house",
                    accessibilityDescription: "HomeKit Automator – Restarting"
                )
            }
        }
    }

    // MARK: - Menu Actions
    
    @objc private func openMainWindow() {
        // Use the new SwiftUI Window API - open by ID
        if let url = URL(string: "homekitautomator://main") {
            NSWorkspace.shared.open(url)
        }
        // Fallback: activate the app which will show windows
        NSApp.activate(ignoringOtherApps: true)
        
        // If no window is visible, open the main window programmatically
        if NSApp.windows.isEmpty || !NSApp.windows.contains(where: { $0.isVisible && $0.title == "HomeKit Automator" }) {
            NSApp.sendAction(NSSelectorFromString("newDocument:"), to: nil, from: nil)
        }
    }

    @objc private func openDashboard() {
        if let window = dashboardWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let dashboardView = DashboardView()
        let hostingView = NSHostingView(rootView: dashboardView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Automation Dashboard"
        window.contentView = hostingView
        window.center()
        window.setFrameAutosaveName("DashboardWindow")
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        dashboardWindow = window
    }

    @objc private func openHistory() {
        if let window = historyWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let historyView = HistoryView()
        let hostingView = NSHostingView(rootView: historyView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Execution History"
        window.contentView = hostingView
        window.center()
        window.setFrameAutosaveName("HistoryWindow")
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        historyWindow = window
    }

    @objc private func openSettings() {
        NSApp.sendAction(NSSelectorFromString("showSettingsWindow:"), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func restartHelper() {
        Task {
            await helperManager.stopHelper()
            try? await Task.sleep(for: .seconds(2))
            await helperManager.launchHelper()
        }
    }

    @objc private func quitApp() {
        Task {
            await helperManager.stopHelper()
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run {
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Login Item

    /// Registers or unregisters the app as a login item using SMAppService (macOS 13+).
    static func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            print("Failed to \(enabled ? "register" : "unregister") login item: \(error)")
        }
    }

    /// Returns the current login item registration status.
    static var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
