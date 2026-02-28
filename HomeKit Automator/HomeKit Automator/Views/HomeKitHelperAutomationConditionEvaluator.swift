// ConditionEvaluator.swift
// Evaluates automation conditions before execution.

import Foundation

/// Evaluates conditions to determine if an automation should execute.
struct ConditionEvaluator {
    
    let homeKitManager: HomeKitManager
    
    // MARK: - Evaluation
    
    /// Evaluates all conditions and returns true if automation should execute.
    func evaluate(_ conditions: [AutomationCondition]) async -> Bool {
        guard !conditions.isEmpty else {
            return true // No conditions = always execute
        }
        
        // All conditions must be true (AND logic)
        for condition in conditions {
            if !(await evaluateCondition(condition)) {
                return false
            }
        }
        
        return true
    }
    
    private func evaluateCondition(_ condition: AutomationCondition) async -> Bool {
        switch condition.type {
        case "time":
            return evaluateTimeCondition(condition)
            
        case "days":
            return evaluateDaysCondition(condition)
            
        case "device_state":
            return await evaluateDeviceStateCondition(condition)
            
        default:
            // Unknown condition type - skip (log warning)
            print("Unknown condition type: \(condition.type)")
            return true
        }
    }
    
    // MARK: - Time Conditions
    
    private func evaluateTimeCondition(_ condition: AutomationCondition) -> Bool {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: now)
        
        guard let hour = components.hour, let minute = components.minute else {
            return false
        }
        
        let currentMinutes = hour * 60 + minute
        
        // Check "after" condition
        if let after = condition.after {
            let afterMinutes = timeStringToMinutes(after)
            if currentMinutes < afterMinutes {
                return false
            }
        }
        
        // Check "before" condition
        if let before = condition.before {
            let beforeMinutes = timeStringToMinutes(before)
            if currentMinutes >= beforeMinutes {
                return false
            }
        }
        
        return true
    }
    
    private func timeStringToMinutes(_ time: String) -> Int {
        let parts = time.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return 0
        }
        return hour * 60 + minute
    }
    
    // MARK: - Days Conditions
    
    private func evaluateDaysCondition(_ condition: AutomationCondition) -> Bool {
        guard let days = condition.days else {
            return true
        }
        
        let now = Date()
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now) - 1 // 0-based (0=Sunday)
        
        return days.contains(weekday)
    }
    
    // MARK: - Device State Conditions
    
    private func evaluateDeviceStateCondition(_ condition: AutomationCondition) async -> Bool {
        guard let deviceUuid = condition.deviceUuid,
              let characteristic = condition.characteristic,
              let `operator` = condition.operator,
              let expectedValue = condition.value else {
            return false
        }
        
        do {
            // Get device info (which includes current characteristic values)
            let device = try await homeKitManager.getDevice(uuid: deviceUuid)
            
            // Find the characteristic
            guard let char = device.characteristics.first(where: {
                $0.name == characteristic || $0.type == characteristic
            }) else {
                return false
            }
            
            guard let currentValue = char.value else {
                return false
            }
            
            // Compare based on operator
            return compareValues(currentValue, `operator`, expectedValue)
            
        } catch {
            print("Failed to evaluate device state condition: \(error)")
            return false
        }
    }
    
    private func compareValues(_ current: AnyCodableValue, _ op: String, _ expected: AnyCodableValue) -> Bool {
        switch op {
        case "equals", "==":
            return current == expected
            
        case "not_equals", "!=":
            return current != expected
            
        case "above", ">":
            return compareNumeric(current, expected, >)
            
        case "below", "<":
            return compareNumeric(current, expected, <)
            
        case "above_or_equal", ">=":
            return compareNumeric(current, expected, >=)
            
        case "below_or_equal", "<=":
            return compareNumeric(current, expected, <=)
            
        default:
            return false
        }
    }
    
    private func compareNumeric(
        _ current: AnyCodableValue,
        _ expected: AnyCodableValue,
        _ comparator: (Double, Double) -> Bool
    ) -> Bool {
        guard let currentNum = current.doubleValue,
              let expectedNum = expected.doubleValue else {
            return false
        }
        
        return comparator(currentNum, expectedNum)
    }
}

// MARK: - Execution Context

/// Context information available during automation execution.
struct ExecutionContext {
    let currentTime: Date
    let currentWeekday: Int
    let deviceStates: [String: Any] // Cached device states (future optimization)
    
    static var current: ExecutionContext {
        let now = Date()
        let weekday = Calendar.current.component(.weekday, from: now) - 1
        
        return ExecutionContext(
            currentTime: now,
            currentWeekday: weekday,
            deviceStates: [:]
        )
    }
}
