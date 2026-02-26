/// AppDelegate.swift
/// HomeKitHelper — Headless Mac Catalyst app that bridges HomeKit to the Unix socket.
/// This process holds the HomeKit entitlement and runs HMHomeManager.
///
/// WHY MAC CATALYST:
/// HomeKit access via HMHomeManager requires the HomeKit entitlement, which is only granted to UIKit-based applications
/// on macOS (via Mac Catalyst). A command-line tool alone cannot hold this entitlement, so HomeKitHelper runs as a
/// lightweight Catalyst app that holds the entitlement and serves homekit-automator CLI commands over a Unix socket.
///
/// PROCESS LIFECYCLE:
/// 1. App launches, AppDelegate initializes HomeKitManager (which creates HMHomeManager)
/// 2. HMHomeManager asynchronously loads home data from iCloud; HomeKitManager.waitForReady() waits for this
/// 3. HelperSocketServer starts listening on ~/Library/Application Support/homekit-automator/homekitauto.sock for JSON-NL commands
/// 4. CLI tool connects to socket and sends commands (get_device, set_device, discover, etc.)
/// 5. On shutdown command or termination, socket server stops and app exits

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    /// Unix domain socket server that accepts commands from the CLI tool.
    var socketServer: HelperSocketServer?
    /// Manager for HomeKit home and accessory control; must run on main thread (@MainActor).
    private(set) lazy var homeKitManager = HomeKitManager()

    /// Application initialization entry point.
    /// Initializes HomeKitManager and starts the Unix socket server.
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Start the Unix socket server
        socketServer = HelperSocketServer(homeKitManager: homeKitManager)
        socketServer?.start()

        print("[HomeKitHelper] Started. Listening on socket.")
        return true
    }

    /// Clean shutdown: stop accepting connections and close the socket.
    func applicationWillTerminate(_ application: UIApplication) {
        socketServer?.stop()
        print("[HomeKitHelper] Shutting down.")
    }
}
