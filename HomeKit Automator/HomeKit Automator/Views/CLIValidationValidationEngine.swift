// ValidationEngine.swift
// Pre-flight validation for automations before saving or executing.

import Foundation

/// Validates automation definitions against HomeKit devices and configuration.
struct ValidationEngine {
    
    private let apiClient: HelperAPIClient
    
    init(apiClient: HelperAPIClient = .shared) {
        self.apiClient = apiClient
    }
    
    // MARK: - Public Interface
    
    /// Validates an automation definition.
    func validate(_ automation: AutomationDefinition) async throws -> ValidationResult {
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []
        
        // Validate name
        if automation.name.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.emptyName)
        }
        
        // Validate trigger
        let triggerResult = try await validateTrigger(automation.trigger)
        errors.append(contentsOf: triggerResult.errors)
        warnings.append(contentsOf: triggerResult.warnings)
        
        // Validate actions
        if automation.actions.isEmpty {
            errors.append(.noActions)
        } else {
            for (index, action) in automation.actions.enumerated() {
                let actionResult = try await validateAction(action, index: index)
                errors.append(contentsOf: actionResult.errors)
                warnings.append(contentsOf: actionResult.warnings)
            }
        }
        
        // Validate conditions if present
        if let conditions = automation.conditions {
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
    func validateRegistered(id: String) async throws -> ValidationResult {
        // Load automation
        let automations = try await apiClient.listAutomations()
        
        guard let automation = automations.first(where: { $0.id == id }) else {
            return ValidationResult(
                isValid: false,
                errors: [.automationNotFound(id)],
                warnings: []
            )
        }
        
        // Convert to definition and validate
        let definition = AutomationDefinition(
            name: automation.name,
            description: automation.description,
            trigger: automation.trigger,
            conditions: automation.conditions,
            actions: automation.actions,
            enabled: automation.enabled
        )
        
        return try await validate(definition)
    }
    
    // MARK: - Trigger Validation
    
    private func validateTrigger(_ trigger: AutomationTrigger) async throws -> PartialValidationResult {
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []
        
        switch trigger.type {
        case "schedule":
            // Validate cron expression
            if let cron = trigger.cron {
                if !isValidCron(cron) {
                    errors.append(.invalidCronExpression(cron))
                }
            } else {
                errors.append(.missingTriggerField("cron"))
            }
            
            // Check timezone
            if let tz = trigger.timezone {
                if TimeZone(identifier: tz) == nil {
                    warnings.append(.invalidTimezone(tz))
                }
            }
            
        case "solar":
            // Validate solar event
            if let event = trigger.event {
                if event != "sunrise" && event != "sunset" {
                    errors.append(.invalidSolarEvent(event))
                }
            } else {
                errors.append(.missingTriggerField("event"))
            }
            
            // Validate offset
            if let offset = trigger.offsetMinutes {
                if abs(offset) > 120 {
                    warnings.append(.largeOffset(offset))
                }
            }
            
        case "manual":
            // Validate keyword
            if let keyword = trigger.keyword {
                if keyword.isEmpty {
                    errors.append(.emptyKeyword)
                }
            }
            
        case "device_state":
            // Validate device
            if let deviceUUID = trigger.deviceUuid {
                let exists = try await deviceExists(uuid: deviceUUID)
                if !exists {
                    errors.append(.deviceNotFound(deviceUUID))
                }
            } else {
                errors.append(.missingTriggerField("deviceUuid"))
            }
            
        default:
            errors.append(.unknownTriggerType(trigger.type))
        }
        
        return PartialValidationResult(errors: errors, warnings: warnings)
    }
    
    // MARK: - Action Validation
    
    private func validateAction(_ action: AutomationAction, index: Int) async throws -> PartialValidationResult {
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []
        
        // Check if it's a scene action
        if action.sceneUuid != nil || action.sceneName != nil {
            return PartialValidationResult(errors: [], warnings: [])
        }
        
        // Validate device UUID
        if action.deviceUuid.isEmpty {
            errors.append(.actionMissingDevice(index))
            return PartialValidationResult(errors: errors, warnings: warnings)
        }
        
        // Check device exists
        let deviceMap = try await apiClient.getDeviceMap()
        var foundDevice: AccessoryInfo?
        
        for home in deviceMap.homes {
            if let device = home.accessories.first(where: { $0.uuid == action.deviceUuid }) {
                foundDevice = device
                break
            }
        }
        
        guard let device = foundDevice else {
            errors.append(.actionDeviceNotFound(index, action.deviceUuid))
            return PartialValidationResult(errors: errors, warnings: warnings)
        }
        
        // Validate characteristic exists
        let hasCharacteristic = device.characteristics.contains {
            $0.name == action.characteristic || $0.type == action.characteristic
        }
        
        if !hasCharacteristic {
            errors.append(.characteristicNotFound(index, action.characteristic, device.name))
            
            // Suggest similar characteristics
            let similar = findSimilarCharacteristics(action.characteristic, in: device.characteristics)
            if !similar.isEmpty {
                warnings.append(.didYouMean(similar.first!))
            }
        }
        
        // Validate value type/range
        if let char = device.characteristics.first(where: { $0.name == action.characteristic }) {
            let valueResult = validateCharacteristicValue(action.value, for: char, actionIndex: index)
            errors.append(contentsOf: valueResult.errors)
            warnings.append(contentsOf: valueResult.warnings)
        }
        
        // Check delay
        if action.delaySeconds < 0 {
            errors.append(.negativeDelay(index))
        } else if action.delaySeconds > 300 {
            warnings.append(.largeDelay(index, action.delaySeconds))
        }
        
        return PartialValidationResult(errors: errors, warnings: warnings)
    }
    
    // MARK: - Condition Validation
    
    private func validateCondition(_ condition: AutomationCondition, index: Int) -> PartialValidationResult {
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []
        
        switch condition.type {
        case "time":
            // Validate time window
            if let after = condition.after, !isValidTime(after) {
                errors.append(.invalidTimeFormat(after))
            }
            if let before = condition.before, !isValidTime(before) {
                errors.append(.invalidTimeFormat(before))
            }
            
        case "device_state":
            // Would validate device UUID if present
            break
            
        case "location":
            // Would validate location settings
            break
            
        default:
            warnings.append(.unknownConditionType(condition.type))
        }
        
        return PartialValidationResult(errors: errors, warnings: warnings)
    }
    
    // MARK: - Value Validation
    
    private func validateCharacteristicValue(
        _ value: AnyCodableValue,
        for characteristic: CharacteristicInfo,
        actionIndex: Int
    ) -> PartialValidationResult {
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []
        
        // Check format compatibility
        if let format = characteristic.format {
            switch format.lowercased() {
            case "bool":
                if case .bool = value {} else {
                    errors.append(.typeMismatch(actionIndex, "boolean", value.displayString))
                }
                
            case "int", "uint8", "uint16", "uint32", "uint64":
                if case .int = value {} else {
                    errors.append(.typeMismatch(actionIndex, "integer", value.displayString))
                }
                
            case "float":
                if case .double = value {} else if case .int = value {
                    warnings.append(.typeCoercion(actionIndex, "int to float"))
                } else {
                    errors.append(.typeMismatch(actionIndex, "number", value.displayString))
                }
                
            default:
                break
            }
        }
        
        // Check common value ranges
        if characteristic.name.lowercased().contains("brightness") {
            if case .int(let val) = value {
                if val < 0 || val > 100 {
                    errors.append(.valueOutOfRange(actionIndex, "Brightness", 0, 100))
                }
            }
        }
        
        if characteristic.name.lowercased().contains("hue") {
            if case .int(let val) = value {
                if val < 0 || val > 360 {
                    errors.append(.valueOutOfRange(actionIndex, "Hue", 0, 360))
                }
            }
        }
        
        if characteristic.name.lowercased().contains("saturation") {
            if case .int(let val) = value {
                if val < 0 || val > 100 {
                    errors.append(.valueOutOfRange(actionIndex, "Saturation", 0, 100))
                }
            }
        }
        
        return PartialValidationResult(errors: errors, warnings: warnings)
    }
    
    // MARK: - Helpers
    
    private func deviceExists(uuid: String) async throws -> Bool {
        let deviceMap = try await apiClient.getDeviceMap()
        
        for home in deviceMap.homes {
            if home.accessories.contains(where: { $0.uuid == uuid }) {
                return true
            }
        }
        
        return false
    }
    
    private func isValidCron(_ cron: String) -> Bool {
        let parts = cron.split(separator: " ")
        return parts.count == 5
    }
    
    private func isValidTime(_ time: String) -> Bool {
        let parts = time.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return false
        }
        return hour >= 0 && hour < 24 && minute >= 0 && minute < 60
    }
    
    private func findSimilarCharacteristics(_ target: String, in characteristics: [CharacteristicInfo]) -> [String] {
        // Simple similarity check
        let lowercaseTarget = target.lowercased()
        return characteristics
            .map { $0.name }
            .filter { $0.lowercased().contains(lowercaseTarget) || lowercaseTarget.contains($0.lowercased()) }
    }
}

// MARK: - Validation Results

struct ValidationResult {
    let isValid: Bool
    let errors: [ValidationError]
    let warnings: [ValidationWarning]
    
    func printResults() {
        if isValid {
            Terminal.printSuccess("Validation passed")
            
            if !warnings.isEmpty {
                Terminal.print("\n" + Terminal.warningIcon("Warnings:"))
                for warning in warnings {
                    Terminal.print("  • " + warning.description)
                }
            }
        } else {
            Terminal.printError("Validation failed with \(errors.count) error(s)")
            
            Terminal.print("\n" + Terminal.cross("Errors:"))
            for error in errors {
                Terminal.print("  • " + error.description.red)
            }
            
            if !warnings.isEmpty {
                Terminal.print("\n" + Terminal.warningIcon("Warnings:"))
                for warning in warnings {
                    Terminal.print("  • " + warning.description)
                }
            }
        }
    }
}

struct PartialValidationResult {
    let errors: [ValidationError]
    let warnings: [ValidationWarning]
}

// MARK: - Errors & Warnings

enum ValidationError: CustomStringConvertible {
    case emptyName
    case noActions
    case invalidCronExpression(String)
    case invalidSolarEvent(String)
    case emptyKeyword
    case unknownTriggerType(String)
    case missingTriggerField(String)
    case deviceNotFound(String)
    case actionMissingDevice(Int)
    case actionDeviceNotFound(Int, String)
    case characteristicNotFound(Int, String, String)
    case typeMismatch(Int, String, String)
    case valueOutOfRange(Int, String, Int, Int)
    case negativeDelay(Int)
    case invalidTimeFormat(String)
    case automationNotFound(String)
    
    var description: String {
        switch self {
        case .emptyName:
            return "Automation name cannot be empty"
        case .noActions:
            return "At least one action is required"
        case .invalidCronExpression(let cron):
            return "Invalid cron expression: '\(cron)'"
        case .invalidSolarEvent(let event):
            return "Invalid solar event: '\(event)' (must be 'sunrise' or 'sunset')"
        case .emptyKeyword:
            return "Manual trigger keyword cannot be empty"
        case .unknownTriggerType(let type):
            return "Unknown trigger type: '\(type)'"
        case .missingTriggerField(let field):
            return "Missing required trigger field: '\(field)'"
        case .deviceNotFound(let uuid):
            return "Device not found with UUID: \(uuid)"
        case .actionMissingDevice(let index):
            return "Action \(index + 1): Device UUID is required"
        case .actionDeviceNotFound(let index, let uuid):
            return "Action \(index + 1): Device not found: \(uuid)"
        case .characteristicNotFound(let index, let char, let device):
            return "Action \(index + 1): Characteristic '\(char)' not found on '\(device)'"
        case .typeMismatch(let index, let expected, let actual):
            return "Action \(index + 1): Expected \(expected), got '\(actual)'"
        case .valueOutOfRange(let index, let char, let min, let max):
            return "Action \(index + 1): \(char) value must be between \(min) and \(max)"
        case .negativeDelay(let index):
            return "Action \(index + 1): Delay cannot be negative"
        case .invalidTimeFormat(let time):
            return "Invalid time format: '\(time)' (use HH:MM)"
        case .automationNotFound(let id):
            return "Automation not found: \(id)"
        }
    }
}

enum ValidationWarning: CustomStringConvertible {
    case invalidTimezone(String)
    case largeOffset(Int)
    case largeDelay(Int, Int)
    case unknownConditionType(String)
    case typeCoercion(Int, String)
    case didYouMean(String)
    
    var description: String {
        switch self {
        case .invalidTimezone(let tz):
            return "Unknown timezone: '\(tz)' (will use system default)"
        case .largeOffset(let minutes):
            return "Large solar offset: \(minutes) minutes"
        case .largeDelay(let index, let seconds):
            return "Action \(index + 1): Large delay: \(seconds) seconds"
        case .unknownConditionType(let type):
            return "Unknown condition type: '\(type)' (will be ignored)"
        case .typeCoercion(let index, let desc):
            return "Action \(index + 1): Type coercion: \(desc)"
        case .didYouMean(let suggestion):
            return "Did you mean '\(suggestion)'?"
        }
    }
}
