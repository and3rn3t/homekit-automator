// CronParser.swift
// Parses cron expressions and calculates next run times.

import Foundation

/// Parses and evaluates cron expressions.
struct CronParser {
    
    // MARK: - Parsing
    
    /// Parses a cron expression string into a CronExpression.
    /// Format: "minute hour day month weekday"
    /// Example: "0 7 * * 1-5" = 7:00 AM on weekdays
    func parse(_ expression: String) throws -> CronExpression {
        let parts = expression.split(separator: " ").map(String.init)
        
        guard parts.count == 5 else {
            throw CronError.invalidFormat("Expected 5 fields: minute hour day month weekday")
        }
        
        let minute = try parseField(parts[0], range: 0...59, name: "minute")
        let hour = try parseField(parts[1], range: 0...23, name: "hour")
        let day = try parseField(parts[2], range: 1...31, name: "day")
        let month = try parseField(parts[3], range: 1...12, name: "month")
        let weekday = try parseField(parts[4], range: 0...6, name: "weekday")
        
        return CronExpression(
            minute: minute,
            hour: hour,
            day: day,
            month: month,
            weekday: weekday
        )
    }
    
    private func parseField(_ field: String, range: ClosedRange<Int>, name: String) throws -> CronField {
        // Wildcard
        if field == "*" {
            return .any
        }
        
        // Step values (*/5)
        if field.hasPrefix("*/") {
            guard let step = Int(field.dropFirst(2)) else {
                throw CronError.invalidField(name, "Invalid step value")
            }
            guard range.contains(step) else {
                throw CronError.invalidField(name, "Step out of range")
            }
            return .step(range.lowerBound, step)
        }
        
        // Range (1-5)
        if field.contains("-") {
            let parts = field.split(separator: "-")
            guard parts.count == 2,
                  let start = Int(parts[0]),
                  let end = Int(parts[1]),
                  range.contains(start),
                  range.contains(end),
                  start <= end else {
                throw CronError.invalidField(name, "Invalid range")
            }
            return .range(start, end)
        }
        
        // List (1,3,5)
        if field.contains(",") {
            let values = try field.split(separator: ",").map { part -> Int in
                guard let value = Int(part), range.contains(value) else {
                    throw CronError.invalidField(name, "Invalid list value")
                }
                return value
            }
            return .list(values)
        }
        
        // Specific value
        guard let value = Int(field), range.contains(value) else {
            throw CronError.invalidField(name, "Invalid value")
        }
        return .specific(value)
    }
}

// MARK: - Cron Expression

/// Represents a parsed cron expression.
struct CronExpression: Sendable {
    let minute: CronField
    let hour: CronField
    let day: CronField
    let month: CronField
    let weekday: CronField
    
    /// Calculates the next run date after the given date.
    func nextRunDate(after date: Date = Date()) -> Date? {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .weekday],
            from: date
        )
        
        // Start from next minute
        components.second = 0
        components.minute! += 1
        
        // Normalize
        guard var current = calendar.date(from: components) else {
            return nil
        }
        
        // Try to find next matching date (limit to 4 years)
        let maxIterations = 365 * 4
        var iterations = 0
        
        while iterations < maxIterations {
            components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .weekday],
                from: current
            )
            
            // Check month
            if !month.matches(components.month!) {
                // Move to next month
                components.month! += 1
                components.day = 1
                components.hour = 0
                components.minute = 0
                guard let next = calendar.date(from: components) else { return nil }
                current = next
                iterations += 1
                continue
            }
            
            // Check day and weekday
            let dayMatches = day.matches(components.day!)
            let weekdayMatches = weekday.matches(components.weekday! - 1) // weekday is 1-based
            
            // Both must match (or one must be "any")
            let dayOk = (day == .any || dayMatches) && (weekday == .any || weekdayMatches)
            
            if !dayOk {
                // Move to next day
                components.day! += 1
                components.hour = 0
                components.minute = 0
                guard let next = calendar.date(from: components) else { return nil }
                current = next
                iterations += 1
                continue
            }
            
            // Check hour
            if !hour.matches(components.hour!) {
                // Move to next hour
                components.hour! += 1
                components.minute = 0
                guard let next = calendar.date(from: components) else { return nil }
                current = next
                iterations += 1
                continue
            }
            
            // Check minute
            if !minute.matches(components.minute!) {
                // Move to next minute
                components.minute! += 1
                guard let next = calendar.date(from: components) else { return nil }
                current = next
                iterations += 1
                continue
            }
            
            // All fields match!
            return current
        }
        
        return nil
    }
    
    /// Returns a human-readable description.
    var description: String {
        // Try to create a friendly description
        if minute == .specific(0) && hour != .any && day == .any && month == .any {
            let hourVal = hour.first ?? 0
            let weekdayDesc = weekday.weekdayDescription
            return "Every \(weekdayDesc) at \(hourVal):00"
        }
        
        return "Custom schedule"
    }
}

// MARK: - Cron Field

/// Represents a single field in a cron expression.
enum CronField: Sendable, Equatable {
    case any                    // *
    case specific(Int)          // 5
    case range(Int, Int)        // 1-5
    case list([Int])            // 1,3,5
    case step(Int, Int)         // */5 or 0/5
    
    /// Checks if a value matches this field.
    func matches(_ value: Int) -> Bool {
        switch self {
        case .any:
            return true
        case .specific(let n):
            return value == n
        case .range(let min, let max):
            return value >= min && value <= max
        case .list(let values):
            return values.contains(value)
        case .step(let start, let step):
            return (value - start) % step == 0 && value >= start
        }
    }
    
    /// Returns the first value in this field (for scheduling).
    var first: Int? {
        switch self {
        case .any:
            return 0
        case .specific(let n):
            return n
        case .range(let min, _):
            return min
        case .list(let values):
            return values.first
        case .step(let start, _):
            return start
        }
    }
    
    var weekdayDescription: String {
        switch self {
        case .any:
            return "day"
        case .specific(let n):
            return weekdayName(n)
        case .range(1, 5):
            return "weekday"
        case .range(0, 0), .range(6, 6), .list([0, 6]):
            return "weekend"
        case .list(let days):
            return days.map(weekdayName).joined(separator: ", ")
        default:
            return "selected days"
        }
    }
    
    private func weekdayName(_ day: Int) -> String {
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][day]
    }
}

// MARK: - Errors

enum CronError: LocalizedError {
    case invalidFormat(String)
    case invalidField(String, String)
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat(let message):
            return "Invalid cron format: \(message)"
        case .invalidField(let field, let message):
            return "Invalid \(field): \(message)"
        }
    }
}

// MARK: - Convenience

extension CronExpression {
    /// Creates a daily cron at a specific time.
    static func daily(hour: Int, minute: Int = 0) -> CronExpression {
        CronExpression(
            minute: .specific(minute),
            hour: .specific(hour),
            day: .any,
            month: .any,
            weekday: .any
        )
    }
    
    /// Creates a weekday cron at a specific time.
    static func weekdays(hour: Int, minute: Int = 0) -> CronExpression {
        CronExpression(
            minute: .specific(minute),
            hour: .specific(hour),
            day: .any,
            month: .any,
            weekday: .range(1, 5)
        )
    }
    
    /// Creates a weekend cron at a specific time.
    static func weekends(hour: Int, minute: Int = 0) -> CronExpression {
        CronExpression(
            minute: .specific(minute),
            hour: .specific(hour),
            day: .any,
            month: .any,
            weekday: .list([0, 6])
        )
    }
}
