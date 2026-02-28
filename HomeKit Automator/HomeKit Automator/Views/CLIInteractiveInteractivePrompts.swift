// InteractivePrompts.swift
// Interactive prompting system for CLI with validation and user-friendly input.

import Foundation

/// Interactive prompting utilities for CLI.
struct InteractivePrompts {
    
    // MARK: - Basic Prompts
    
    /// Prompts user for text input with optional validation.
    static func promptText(
        _ question: String,
        default defaultValue: String? = nil,
        validate: ((String) -> Bool)? = nil,
        errorMessage: String = "Invalid input, please try again."
    ) -> String {
        while true {
            let suffix = defaultValue.map { " [\($0)]" } ?? ""
            Terminal.print(Terminal.bold(question) + suffix + ": ", terminator: "")
            
            guard let input = readLine() else {
                continue
            }
            
            let value = input.isEmpty ? (defaultValue ?? "") : input
            
            if let validate = validate {
                if validate(value) {
                    return value
                } else {
                    Terminal.printError(errorMessage)
                    continue
                }
            }
            
            if !value.isEmpty {
                return value
            }
            
            if defaultValue != nil {
                return defaultValue!
            }
        }
    }
    
    /// Prompts user for yes/no confirmation.
    static func promptYesNo(
        _ question: String,
        default defaultValue: Bool? = nil
    ) -> Bool {
        let suffix: String
        if let def = defaultValue {
            suffix = def ? " (Y/n)" : " (y/N)"
        } else {
            suffix = " (y/n)"
        }
        
        while true {
            Terminal.print(Terminal.bold(question) + suffix + ": ", terminator: "")
            
            guard let input = readLine()?.lowercased() else {
                continue
            }
            
            if input.isEmpty, let def = defaultValue {
                return def
            }
            
            if input == "y" || input == "yes" {
                return true
            }
            
            if input == "n" || input == "no" {
                return false
            }
            
            Terminal.printError("Please enter 'y' or 'n'")
        }
    }
    
    /// Prompts user to choose from a list of options.
    static func promptChoice<T>(
        _ question: String,
        options: [T],
        display: (T) -> String,
        allowCancel: Bool = false
    ) -> T? {
        Terminal.print("\n" + Terminal.bold(question) + "\n")
        
        for (index, option) in options.enumerated() {
            let number = Terminal.dim("  \(index + 1).")
            Terminal.print("\(number) \(display(option))")
        }
        
        if allowCancel {
            Terminal.print(Terminal.dim("  0.") + " Cancel")
        }
        
        while true {
            let range = allowCancel ? 0...options.count : 1...options.count
            Terminal.print("\n" + Terminal.bold("Enter number") + " (\(range.lowerBound)-\(range.upperBound)): ", terminator: "")
            
            guard let input = readLine(),
                  let choice = Int(input),
                  range.contains(choice) else {
                Terminal.printError("Invalid selection")
                continue
            }
            
            if choice == 0 {
                return nil
            }
            
            return options[choice - 1]
        }
    }
    
    /// Prompts user to select multiple options.
    static func promptMultipleChoice<T>(
        _ question: String,
        options: [T],
        display: (T) -> String,
        min: Int = 0,
        max: Int = Int.max
    ) -> [T] {
        Terminal.print("\n" + Terminal.bold(question))
        Terminal.print(Terminal.dim("(Enter numbers separated by commas, e.g., 1,3,5)") + "\n")
        
        for (index, option) in options.enumerated() {
            let number = Terminal.dim("  \(index + 1).")
            Terminal.print("\(number) \(display(option))")
        }
        
        while true {
            Terminal.print("\n" + Terminal.bold("Enter selections") + ": ", terminator: "")
            
            guard let input = readLine() else {
                continue
            }
            
            let selections = input.split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                .filter { $0 > 0 && $0 <= options.count }
                .map { options[$0 - 1] }
            
            if selections.count >= min && selections.count <= max {
                return selections
            }
            
            Terminal.printError("Please select between \(min) and \(max) options")
        }
    }
    
    // MARK: - Specialized Prompts
    
    /// Prompts user for a time in HH:MM format.
    static func promptTime(
        _ question: String,
        default defaultValue: String? = nil
    ) -> String {
        promptText(
            question,
            default: defaultValue,
            validate: { input in
                let parts = input.split(separator: ":")
                guard parts.count == 2,
                      let hour = Int(parts[0]),
                      let minute = Int(parts[1]),
                      hour >= 0 && hour < 24,
                      minute >= 0 && minute < 60 else {
                    return false
                }
                return true
            },
            errorMessage: "Invalid time format. Use HH:MM (e.g., 07:30)"
        )
    }
    
    /// Prompts user for a number within a range.
    static func promptNumber(
        _ question: String,
        min: Int? = nil,
        max: Int? = nil,
        default defaultValue: Int? = nil
    ) -> Int {
        let defaultStr = defaultValue.map { String($0) }
        
        return Int(promptText(
            question,
            default: defaultStr,
            validate: { input in
                guard let number = Int(input) else {
                    return false
                }
                
                if let min = min, number < min {
                    return false
                }
                
                if let max = max, number > max {
                    return false
                }
                
                return true
            },
            errorMessage: {
                var msg = "Please enter a valid number"
                if let min = min, let max = max {
                    msg += " between \(min) and \(max)"
                } else if let min = min {
                    msg += " >= \(min)"
                } else if let max = max {
                    msg += " <= \(max)"
                }
                return msg
            }()
        ))!
    }
    
    /// Prompts user for days of the week.
    static func promptDaysOfWeek() -> [Int] {
        let days = [
            (0, "Sunday"),
            (1, "Monday"),
            (2, "Tuesday"),
            (3, "Wednesday"),
            (4, "Thursday"),
            (5, "Friday"),
            (6, "Saturday")
        ]
        
        let choice = promptChoice(
            "Which days?",
            options: [
                "Every day",
                "Weekdays (Mon-Fri)",
                "Weekends (Sat-Sun)",
                "Custom selection"
            ],
            display: { $0 }
        )
        
        switch choice {
        case "Every day":
            return [0, 1, 2, 3, 4, 5, 6]
        case "Weekdays (Mon-Fri)":
            return [1, 2, 3, 4, 5]
        case "Weekends (Sat-Sun)":
            return [0, 6]
        case "Custom selection":
            return promptMultipleChoice(
                "Select days",
                options: days,
                display: { $0.1 },
                min: 1
            ).map { $0.0 }
        default:
            return [0, 1, 2, 3, 4, 5, 6]
        }
    }
    
    // MARK: - Loading & Progress
    
    /// Shows a loading spinner while executing an async task.
    static func withSpinner<T>(
        _ message: String,
        task: () async throws -> T
    ) async throws -> T {
        Terminal.print(Terminal.spinner(message))
        
        let result = try await task()
        
        // Move cursor up and clear line
        print("\u{001B}[1A\u{001B}[2K", terminator: "")
        Terminal.printSuccess(message)
        
        return result
    }
    
    /// Shows progress while processing items.
    static func withProgress<T, U>(
        _ message: String,
        items: [T],
        process: (T) async throws -> U
    ) async throws -> [U] {
        var results: [U] = []
        
        for (index, item) in items.enumerated() {
            // Show progress
            print("\u{001B}[2K\r" + Terminal.progress(
                current: index + 1,
                total: items.count,
                label: message
            ), terminator: "")
            fflush(stdout)
            
            let result = try await process(item)
            results.append(result)
        }
        
        // Clear progress line and show completion
        print("\u{001B}[2K\r", terminator: "")
        Terminal.printSuccess("\(message): Completed \(items.count) items")
        
        return results
    }
    
    // MARK: - Confirmation
    
    /// Shows a preview and asks for confirmation.
    static func confirmAction(
        title: String,
        preview: String,
        action: String = "Continue"
    ) -> Bool {
        Terminal.print("\n" + Terminal.header(title))
        Terminal.print(preview)
        Terminal.print("")
        return promptYesNo(action, default: false)
    }
}
