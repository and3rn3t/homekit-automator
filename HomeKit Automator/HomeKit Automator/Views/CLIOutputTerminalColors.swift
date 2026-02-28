// TerminalColors.swift
// ANSI color codes for beautiful terminal output.

import Foundation

/// Terminal color and formatting utilities using ANSI escape codes.
enum TerminalColor: String {
    // Regular colors
    case black = "\u{001B}[0;30m"
    case red = "\u{001B}[0;31m"
    case green = "\u{001B}[0;32m"
    case yellow = "\u{001B}[0;33m"
    case blue = "\u{001B}[0;34m"
    case magenta = "\u{001B}[0;35m"
    case cyan = "\u{001B}[0;36m"
    case white = "\u{001B}[0;37m"
    
    // Bright colors
    case brightBlack = "\u{001B}[0;90m"
    case brightRed = "\u{001B}[0;91m"
    case brightGreen = "\u{001B}[0;92m"
    case brightYellow = "\u{001B}[0;93m"
    case brightBlue = "\u{001B}[0;94m"
    case brightMagenta = "\u{001B}[0;95m"
    case brightCyan = "\u{001B}[0;96m"
    case brightWhite = "\u{001B}[0;97m"
    
    // Styles
    case bold = "\u{001B}[1m"
    case dim = "\u{001B}[2m"
    case italic = "\u{001B}[3m"
    case underline = "\u{001B}[4m"
    case blink = "\u{001B}[5m"
    case reverse = "\u{001B}[7m"
    case hidden = "\u{001B}[8m"
    
    // Reset
    case reset = "\u{001B}[0m"
    
    /// Checks if colors are supported in the current terminal.
    static var isSupported: Bool {
        guard let term = ProcessInfo.processInfo.environment["TERM"] else {
            return false
        }
        return term != "dumb" && isatty(STDOUT_FILENO) == 1
    }
}

/// Convenience functions for colored output.
struct Terminal {
    
    static var colorsEnabled = TerminalColor.isSupported
    
    // MARK: - Colored Strings
    
    static func success(_ message: String) -> String {
        colored(message, .green)
    }
    
    static func error(_ message: String) -> String {
        colored(message, .red)
    }
    
    static func warning(_ message: String) -> String {
        colored(message, .yellow)
    }
    
    static func info(_ message: String) -> String {
        colored(message, .cyan)
    }
    
    static func bold(_ message: String) -> String {
        styled(message, .bold)
    }
    
    static func dim(_ message: String) -> String {
        styled(message, .dim)
    }
    
    static func underline(_ message: String) -> String {
        styled(message, .underline)
    }
    
    static func colored(_ message: String, _ color: TerminalColor) -> String {
        guard colorsEnabled else { return message }
        return "\(color.rawValue)\(message)\(TerminalColor.reset.rawValue)"
    }
    
    static func styled(_ message: String, _ style: TerminalColor) -> String {
        guard colorsEnabled else { return message }
        return "\(style.rawValue)\(message)\(TerminalColor.reset.rawValue)"
    }
    
    // MARK: - Status Indicators
    
    static func checkmark(_ message: String) -> String {
        colored("✓", .green) + " " + message
    }
    
    static func cross(_ message: String) -> String {
        colored("✗", .red) + " " + message
    }
    
    static func warningIcon(_ message: String) -> String {
        colored("⚠", .yellow) + " " + message
    }
    
    static func infoIcon(_ message: String) -> String {
        colored("ℹ", .cyan) + " " + message
    }
    
    static func spinner(_ message: String) -> String {
        colored("⏳", .blue) + " " + message
    }
    
    static func sparkles(_ message: String) -> String {
        colored("✨", .magenta) + " " + message
    }
    
    // MARK: - Headers & Sections
    
    static func header(_ title: String, width: Int = 50) -> String {
        let padding = max(0, (width - title.count - 2) / 2)
        let paddingStr = String(repeating: "═", count: padding)
        return "\n" + bold(colored("\(paddingStr) \(title) \(paddingStr)", .cyan)) + "\n"
    }
    
    static func section(_ title: String) -> String {
        "\n" + bold(title) + "\n" + String(repeating: "─", count: title.count)
    }
    
    static func divider(width: Int = 50, character: String = "━") -> String {
        String(repeating: character, count: width)
    }
    
    // MARK: - Output Functions
    
    static func print(_ message: String) {
        Swift.print(message)
    }
    
    static func printSuccess(_ message: String) {
        print(checkmark(message))
    }
    
    static func printError(_ message: String) {
        print(cross(message))
    }
    
    static func printWarning(_ message: String) {
        print(warningIcon(message))
    }
    
    static func printInfo(_ message: String) {
        print(infoIcon(message))
    }
    
    // MARK: - Progress
    
    static func progress(current: Int, total: Int, label: String = "Progress") -> String {
        let percentage = Int((Double(current) / Double(total)) * 100)
        let barWidth = 30
        let filled = Int((Double(current) / Double(total)) * Double(barWidth))
        let empty = barWidth - filled
        
        let bar = colored(String(repeating: "█", count: filled), .green) +
                  dim(String(repeating: "░", count: empty))
        
        return "\(label): [\(bar)] \(percentage)% (\(current)/\(total))"
    }
}

// MARK: - String Extensions

extension String {
    var green: String { Terminal.colored(self, .green) }
    var red: String { Terminal.colored(self, .red) }
    var yellow: String { Terminal.colored(self, .yellow) }
    var blue: String { Terminal.colored(self, .blue) }
    var cyan: String { Terminal.colored(self, .cyan) }
    var magenta: String { Terminal.colored(self, .magenta) }
    var white: String { Terminal.colored(self, .white) }
    
    var bold: String { Terminal.styled(self, .bold) }
    var dim: String { Terminal.styled(self, .dim) }
    var underline: String { Terminal.styled(self, .underline) }
}
