// ValidationEngine.swift
// Validates automation definitions before execution.

import Foundation

/// Validates automation definitions and provides actionable feedback.
struct ValidationEngine {
    
    let apiClient: HelperAPIClient
    
    // MARK: - Main Validation
    
    /// Validates an automation definition.
    func validate(_ definition: AutomationDefinition) async -> ValidationResult {
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []
        
        // Validate name
        if definition.name.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.init(
                field: "name",
                message: "Automation name is required",
                suggestion: "Provide a descriptive name for the automation"
            ))
        }
        
        // Validate trigger
        let triggerResult = await validateTrigger(definition.trigger)
        errors.append(contentsOf: triggerResult.errors)
        warnings.append(contentsOf: triggerResult.warnings)
        
        // Validate actions
        if definition.actions.isEmpty {
            errors.append(.init(
                field: "actions",
                message: "At least one action is required",
                suggestion: "Add an action to control a device or scene"
            ))
        } else {
            for (index, action) in definition.actions.enumerated() {
                let actionResult = await validateAction(action, index: index)
                errors.append(contentsOf: actionResult.errors)
                warnings.append(contentsOf: actionResult.warnings)
            }
        }
        
        // Validate conditions
        if let conditions = definition.conditions {
            for (index, condition) in conditions.enumerated() {
                let conditionResult = validateCondition(condition, index: index)
                errors.append(contentsOf: conditionResult.errors)
                warnings.append(contentsOf: conditionResult.warnings)
            }
        }
        
        return ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }
    
    /// Validates a registered automation by ID.
    func validate(_ automationId: String) async -> ValidationResult {
        do {
            let automations = try await apiClient.listAutomations()
            guard let automation = automations.first(where: { $0.id == automationId }) else {
                return ValidationResult(
                    isValid: false,
                    errors: [.init(field: "id", message: "Automation not found", suggestion: nil)],
                    warnings: []
                )
            }
            
            // Convert to definition for validation
            let definition = AutomationDefinition(
                name: automation.name,
                description: automation.description,
                trigger: automation.trigger,
                conditions: automation.conditions,
                actions: automation.actions,
                enabled: automation.enabled
            )
            
            return await validate(definition)
        } catch {
            return ValidationResult(
                isValid: false,
                errors: [.init(field: "general", message: error.localizedDescription, suggestion: nil)],
                warnings: []
            )
        }
    }
    
    // MARK: - Trigger Validation
    
    private func validateTrigger(_ trigger: AutomationTrigger) async -> ValidationResult {
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []
        
        switch trigger.type {
        case "schedule":
            // Validate cron expression
            if let cron = trigger.cron {
                if !isValidCron(cron) {
                    errors.append(.init(
                        field: "trigger.cron",
                        message: "Invalid cron expression: \(cron)",
                        suggestion: "Use format: minute hour day month weekday (e.g., '0 7 * * 1-5')"
                    ))
                }
            } else {
                errors.append(.init(
                    field: "trigger.cron",
                    message: "Cron expression is required for schedule trigger",
                    suggestion: "Add a cron expression like '0 7 * * *' for daily at 7 AM"
                ))
            }
            
            // Validate timezone
            if let timezone = trigger.timezone {
                if TimeZone(identifier: timezone) == nil {
                    errors.append(.init(
                        field: "trigger.timezone",
                        message: "Invalid timezone: \(timezone)",
                        suggestion: "Use a valid timezone like 'America/Los_Angeles'"
                    ))
                }
            } else {
                warnings.append(.init(
                    field: "trigger.timezone",
                    message: "No timezone specified, will use system timezone",
                    impact: "Automation may run at unexpected times if device moves"
                ))
            }
            
        case "solar":
            // Validate event
            if let event = trigger.event {
                if event != "sunrise" && event != "sunset" {
                    errors.append(.init(
                        field: "trigger.event",
                        message: "Invalid solar event: \(event)",
                        suggestion: "Use 'sunrise' or 'sunset'"
                    ))
                }
            } else {
                errors.append(.init(
                    field: "trigger.event",
                    message: "Solar event is required",
                    suggestion: "Specify 'sunrise' or 'sunset'"
                ))
            }
            
        case "manual":
            // Validate keyword
            if let keyword = trigger.keyword, keyword.isEmpty {
                warnings.append(.init(
                    field: "trigger.keyword",
                    message: "Empty keyword for manual trigger",
                    impact: "Siri may have trouble recognizing the shortcut"
                ))
            }
            
        case "device_state":
            // Validate device
            if let deviceUuid = trigger.deviceUuid, !deviceUuid.isEmpty {
                // TODO: Check if device exists
            } else {
                errors.append(.init(
                    field: "trigger.deviceUuid",
                    message: "Device UUID is required for device state trigger",
                    suggestion: "Specify the device to monitor"
                ))
            }
            
        default:
            warnings.append(.init(
                field: "trigger.type",
                message: "Unknown trigger type: \(trigger.type)",
                impact: "Trigger may not work as expected"
            ))
        }
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings)
    }
    
    // MARK: - Action Validation
    
    private func validateAction(_ action: AutomationAction, index: Int) async -> ValidationResult {
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []
        
        let prefix = "action[\(index)]"
        
        // Check if it's a scene action
        if let sceneUuid = action.sceneUuid, !sceneUuid.isEmpty {
            // Scene action - validate scene
            if action.sceneName?.isEmpty ?? true {
                warnings.append(.init(
                    field: "\(prefix).sceneName",
                    message: "Scene name is empty",
                    impact: "Action may fail to identify scene"
                ))
            }
        } else {
            // Device action - validate device and characteristic
            if action.deviceUuid.isEmpty {
                errors.append(.init(
                    field: "\(prefix).deviceUuid",
                    message: "Device UUID is required",
                    suggestion: "Specify which device to control"
                ))
            }
            
            if action.characteristic.isEmpty {
                errors.append(.init(
                    field: "\(prefix).characteristic",
                    message: "Characteristic is required",
                    suggestion: "Specify what to control (e.g., 'On', 'Brightness')"
                ))
            }
            
            // Validate value range
            let valueValidation = validateValue(
                action.value,
                for: action.characteristic,
                field: "\(prefix).value"
            )
            errors.append(contentsOf: valueValidation.errors)
            warnings.append(contentsOf: valueValidation.warnings)
        }
        
        // Validate delay
        if action.delaySeconds < 0 {
            errors.append(.init(
                field: "\(prefix).delaySeconds",
                message: "Delay cannot be negative",
                suggestion: "Use 0 for immediate execution or positive number for delay"
            ))
        } else if action.delaySeconds > 3600 {
            warnings.append(.init(
                field: "\(prefix).delaySeconds",
                message: "Delay is very long (\(action.delaySeconds) seconds)",
                impact: "Automation may take over an hour to complete"
            ))
        }
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings)
    }
    
    // MARK: - Condition Validation
    
    private func validateCondition(_ condition: AutomationCondition, index: Int) -> ValidationResult {
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []
        
        let prefix = "condition[\(index)]"
        
        switch condition.type {
        case "time":
            if condition.after == nil && condition.before == nil {
                errors.append(.init(
                    field: prefix,
                    message: "Time condition requires 'after' or 'before'",
                    suggestion: "Specify time window like 'after: 08:00' or 'before: 22:00'"
                ))
            }
            
        case "device_state":
            if condition.deviceUuid == nil || condition.deviceUuid?.isEmpty == true {
                errors.append(.init(
                    field: "\(prefix).deviceUuid",
                    message: "Device UUID is required",
                    suggestion: "Specify which device to check"
                ))
            }
            
        case "days":
            if condition.days?.isEmpty == true {
                errors.append(.init(
                    field: "\(prefix).days",
                    message: "At least one day is required",
                    suggestion: "Specify days like [1, 2, 3, 4, 5] for weekdays"
                ))
            }
            
        default:
            warnings.append(.init(
                field: "\(prefix).type",
                message: "Unknown condition type: \(condition.type)",
                impact: "Condition may not be evaluated"
            ))
        }
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings)
    }
    
    // MARK: - Value Validation
    
    private func validateValue(
        _ value: AnyCodableValue,
        for characteristic: String,
        field: String
    ) -> ValidationResult {
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []
        
        switch characteristic {
        case "On":
            if case .bool = value {
                // Valid
            } else {
                errors.append(.init(
                    field: field,
                    message: "Value for 'On' must be boolean (true/false)",
                    suggestion: "Use true or false"
                ))
            }
            
        case "Brightness", "Saturation":
            if case .int(let val) = value {
                if val < 0 || val > 100 {
                    errors.append(.init(
                        field: field,
                        message: "\(characteristic) must be between 0 and 100, got \(val)",
                        suggestion: "Use a value between 0 (off/minimum) and 100 (full)"
                    ))
                }
            } else {
                errors.append(.init(
                    field: field,
                    message: "\(characteristic) must be a number",
                    suggestion: "Use an integer between 0 and 100"
                ))
            }
            
        case "Hue":
            if case .int(let val) = value {
                if val < 0 || val > 360 {
                    errors.append(.init(
                        field: field,
                        message: "Hue must be between 0 and 360, got \(val)",
                        suggestion: "Use degrees: 0=red, 120=green, 240=blue"
                    ))
                }
            } else {
                errors.append(.init(
                    field: field,
                    message: "Hue must be a number",
                    suggestion: "Use degrees between 0 and 360"
                ))
            }
            
        case let char where char.contains("Temperature"):
            if case .int(let val) = value {
                if val < 50 || val > 90 {
                    warnings.append(.init(
                        field: field,
                        message: "Temperature \(val)°F is outside typical range (50-90°F)",
                        impact: "May be uncomfortable or device may reject value"
                    ))
                }
            }
            
        default:
            // Unknown characteristic, skip validation
            break
        }
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings)
    }
    
    // MARK: - Helpers
    
    private func isValidCron(_ cron: String) -> Bool {
        let parts = cron.split(separator: " ")
        return parts.count == 5
    }
}

// MARK: - Result Types

struct ValidationResult {
    let isValid: Bool
    let errors: [ValidationError]
    let warnings: [ValidationWarning]
    
    var hasIssues: Bool {
        !errors.isEmpty || !warnings.isEmpty
    }
}

struct ValidationError {
    let field: String
    let message: String
    let suggestion: String?
}

struct ValidationWarning {
    let field: String
    let message: String
    let impact: String
}

// MARK: - Display

extension ValidationResult {
    
    func display() {
        if isValid && !hasIssues {
            Terminal.printSuccess("Validation passed!")
            return
        }
        
        if !errors.isEmpty {
            Terminal.print("\n" + Terminal.bold("Errors:").red)
            for error in errors {
                Terminal.print("  " + Terminal.cross(error.field))
                Terminal.print("    " + error.message)
                if let suggestion = error.suggestion {
                    Terminal.print("    " + Terminal.dim("→ \(suggestion)"))
                }
            }
        }
        
        if !warnings.isEmpty {
            Terminal.print("\n" + Terminal.bold("Warnings:").yellow)
            for warning in warnings {
                Terminal.print("  " + Terminal.warningIcon(warning.field))
                Terminal.print("    " + warning.message)
                Terminal.print("    " + Terminal.dim("Impact: \(warning.impact)"))
            }
        }
        
        Terminal.print("")
        
        if !isValid {
            Terminal.printError("Validation failed with \(errors.count) error(s)")
        } else {
            Terminal.printWarning("Validation passed with \(warnings.count) warning(s)")
        }
    }
}
