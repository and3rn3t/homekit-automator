// HelperLogger.swift
// Logging system for HomeKitHelper with console and file output.

import Foundation

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

/// Singleton logger for HomeKitHelper with file and console output.
@MainActor
final class HelperLogger {
    
    static let shared = HelperLogger()
    
    private let logDir: URL
    private let logFile: URL
    private let dateFormatter: DateFormatter
    
    private init() {
        // Set up log directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        logDir = appSupport.appendingPathComponent("homekit-automator/logs")
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        
        // Log file path
        let dateString = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
            .replacingOccurrences(of: "/", with: "-")
        logFile = logDir.appendingPathComponent("helper-\(dateString).log")
        
        // Date formatter for log entries
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }
    
    /// Logs a message to console and file.
    func log(_ message: String, level: LogLevel = .info) {
        let timestamp = dateFormatter.string(from: Date())
        let logMessage = "[\(timestamp)] [\(level.rawValue)] \(message)"
        
        // Print to console
        print(logMessage)
        
        // Write to file
        Task.detached { [weak self, logMessage, logFile] in
            guard let self else { return }
            
            if let data = (logMessage + "\n").data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logFile.path) {
                    // Append
                    if let fileHandle = try? FileHandle(forWritingTo: logFile) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        try? fileHandle.close()
                    }
                } else {
                    // Create new
                    try? data.write(to: logFile)
                }
            }
        }
    }
    
    /// Logs an error with file and line information.
    func logError(_ error: Error, file: String = #file, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        log("Error at \(fileName):\(line) - \(error.localizedDescription)", level: .error)
    }
}
