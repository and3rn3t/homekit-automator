/// Logger.swift
/// Centralized structured logging configuration for the HomeKit Automator CLI.
///
/// Provides pre-configured loggers for each subsystem using the swift-log framework.
/// All log output is directed to stderr so it does not interfere with JSON output
/// on stdout that the MCP server expects from the CLI.
///
/// Usage:
///   Log.configure(verbose: true)  // Call once at startup
///   Log.socket.info("Connected to helper")
///   Log.automation.debug("Loading registry", metadata: ["path": "\(path)"])

import Logging
import Foundation

/// Namespace for structured loggers used throughout the CLI.
///
/// Each logger has a unique label following reverse-DNS convention, which allows
/// filtering log output by subsystem when debugging. The log level is controlled
/// globally via `configure(verbose:)`.
enum Log {
    /// General-purpose logger for top-level CLI operations and startup.
    nonisolated(unsafe) static var main = Logger(label: "com.homekit-automator.cli")

    /// Logger for Unix domain socket IPC with the HomeKitHelper process.
    nonisolated(unsafe) static var socket = Logger(label: "com.homekit-automator.socket")

    /// Logger for automation registry CRUD and persistence operations.
    nonisolated(unsafe) static var automation = Logger(label: "com.homekit-automator.automation")

    /// Logger for Shortcut generation, import, and lifecycle management.
    nonisolated(unsafe) static var shortcut = Logger(label: "com.homekit-automator.shortcut")

    /// Bootstrap the logging system with the appropriate log level.
    ///
    /// Must be called exactly once, before any logging occurs (typically in the
    /// root command's `run()` or at the top of `main`). Subsequent calls are
    /// ignored by swift-log's `LoggingSystem.bootstrap`.
    ///
    /// - Parameter verbose: When true, sets log level to `.debug` for detailed
    ///   diagnostic output. When false (default), sets level to `.info`.
    static func configure(verbose: Bool = false) {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = verbose ? .debug : .info
            return handler
        }
    }
}
