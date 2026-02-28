// AutomationTemplates.swift
// Pre-built automation templates for common scenarios.

import Foundation

/// Template for creating automations from common patterns.
struct AutomationTemplate {
    let id: String
    let name: String
    let category: String
    let description: String
    let icon: String
    let parameters: [TemplateParameter]
    let generate: (TemplateContext) async throws -> AutomationDefinition
}

/// Parameter for template customization.
struct TemplateParameter {
    let key: String
    let label: String
    let type: ParameterType
    let defaultValue: Any?
    let required: Bool
    let helpText: String?
    
    init(key: String, label: String, type: ParameterType, defaultValue: Any? = nil, required: Bool = true, helpText: String? = nil) {
        self.key = key
        self.label = label
        self.type = type
        self.defaultValue = defaultValue
        self.required = required
        self.helpText = helpText
    }
}

/// Parameter types for templates.
enum ParameterType {
    case device
    case time
    case temperature
    case brightness
    case text
    case boolean
}

/// Context for template generation.
struct TemplateContext {
    var parameters: [String: Any] = [:]
    
    subscript(key: String) -> Any? {
        get { parameters[key] }
        set { parameters[key] = newValue }
    }
    
    func getString(_ key: String) -> String? {
        parameters[key] as? String
    }
    
    func getInt(_ key: String) -> Int? {
        parameters[key] as? Int
    }
    
    func getBool(_ key: String) -> Bool? {
        parameters[key] as? Bool
    }
    
    func getDevice(_ key: String) -> String? {
        parameters[key] as? String
    }
}

/// Collection of built-in automation templates.
struct BuiltInTemplates {
    
    static let all: [AutomationTemplate] = [
        morningRoutine,
        eveningRoutine,
        bedtimeRoutine,
        arriveHome,
        leaveHome,
        movieTime
    ]
    
    // MARK: - Morning Routine
    
    static let morningRoutine = AutomationTemplate(
        id: "morning-routine",
        name: "Morning Routine",
        category: "Daily Routines",
        description: "Turn on lights and adjust settings to wake up",
        icon: "☀️"
    ,
        parameters: [
            TemplateParameter(
                key: "time",
                label: "Wake up time",
                type: .time,
                defaultValue: "07:00",
                helpText: "When should the routine run? (HH:MM format)"
            ),
            TemplateParameter(
                key: "days",
                label: "Days of week",
                type: .text,
                defaultValue: "weekdays",
                helpText: "Every day, weekdays, or weekends"
            ),
            TemplateParameter(
                key: "bedroom_light",
                label: "Bedroom light",
                type: .device,
                helpText: "Main bedroom light to turn on"
            ),
            TemplateParameter(
                key: "brightness",
                label: "Light brightness",
                type: .brightness,
                defaultValue: 80,
                required: false,
                helpText: "Brightness level (0-100)"
            ),
            TemplateParameter(
                key: "temperature",
                label: "Thermostat temperature",
                type: .temperature,
                defaultValue: 72,
                required: false,
                helpText: "Target temperature in Fahrenheit"
            )
        ],
        generate: { context in
            let time = context.getString("time") ?? "07:00"
            let days = context.getString("days") ?? "weekdays"
            let bedroomLight = context.getDevice("bedroom_light") ?? ""
            let brightness = context.getInt("brightness") ?? 80
            let temp = context.getInt("temperature")
            
            // Convert time to cron
            let timeParts = time.split(separator: ":")
            let hour = timeParts[0]
            let minute = timeParts[1]
            
            let cronDays: String
            switch days {
            case "weekdays":
                cronDays = "1-5"
            case "weekends":
                cronDays = "0,6"
            default:
                cronDays = "*"
            }
            
            let cron = "\(minute) \(hour) * * \(cronDays)"
            
            var actions: [AutomationAction] = []
            
            // Add light action
            if !bedroomLight.isEmpty {
                actions.append(AutomationAction(
                    deviceUuid: bedroomLight,
                    deviceName: "Bedroom Light",
                    characteristic: "On",
                    value: .bool(true)
                ))
                
                if brightness < 100 {
                    actions.append(AutomationAction(
                        deviceUuid: bedroomLight,
                        deviceName: "Bedroom Light",
                        characteristic: "Brightness",
                        value: .int(brightness),
                        delaySeconds: 1
                    ))
                }
            }
            
            // Add thermostat action if specified
            if let temp = temp {
                // Would need thermostat device UUID from context
                // Placeholder for now
            }
            
            return AutomationDefinition(
                name: "Morning Routine",
                description: "Wake up routine at \(time) on \(days)",
                trigger: AutomationTrigger(
                    type: "schedule",
                    humanReadable: "At \(time) on \(days)",
                    cron: cron,
                    timezone: TimeZone.current.identifier
                ),
                conditions: nil,
                actions: actions,
                enabled: true
            )
        }
    )
    
    // MARK: - Evening Routine
    
    static let eveningRoutine = AutomationTemplate(
        id: "evening-routine",
        name: "Evening Routine",
        category: "Daily Routines",
        description: "Dim lights and prepare for evening",
        icon: "🌙",
        parameters: [
            TemplateParameter(
                key: "time",
                label: "Evening time",
                type: .time,
                defaultValue: "20:00",
                helpText: "When to start evening routine"
            ),
            TemplateParameter(
                key: "living_room_light",
                label: "Living room light",
                type: .device
            ),
            TemplateParameter(
                key: "brightness",
                label: "Dimmed brightness",
                type: .brightness,
                defaultValue: 30
            )
        ],
        generate: { context in
            let time = context.getString("time") ?? "20:00"
            let livingRoomLight = context.getDevice("living_room_light") ?? ""
            let brightness = context.getInt("brightness") ?? 30
            
            let timeParts = time.split(separator: ":")
            let cron = "\(timeParts[1]) \(timeParts[0]) * * *"
            
            return AutomationDefinition(
                name: "Evening Routine",
                description: "Dim lights for evening at \(time)",
                trigger: AutomationTrigger(
                    type: "schedule",
                    humanReadable: "Every day at \(time)",
                    cron: cron,
                    timezone: TimeZone.current.identifier
                ),
                actions: [
                    AutomationAction(
                        deviceUuid: livingRoomLight,
                        deviceName: "Living Room Light",
                        characteristic: "Brightness",
                        value: .int(brightness)
                    )
                ],
                enabled: true
            )
        }
    )
    
    // MARK: - Bedtime Routine
    
    static let bedtimeRoutine = AutomationTemplate(
        id: "bedtime-routine",
        name: "Bedtime Routine",
        category: "Daily Routines",
        description: "Turn off all lights and lock doors",
        icon: "🛏️",
        parameters: [
            TemplateParameter(
                key: "time",
                label: "Bedtime",
                type: .time,
                defaultValue: "23:00"
            ),
            TemplateParameter(
                key: "turn_off_all",
                label: "Turn off all lights",
                type: .boolean,
                defaultValue: true
            )
        ],
        generate: { context in
            let time = context.getString("time") ?? "23:00"
            let timeParts = time.split(separator: ":")
            let cron = "\(timeParts[1]) \(timeParts[0]) * * *"
            
            return AutomationDefinition(
                name: "Bedtime Routine",
                description: "Prepare for sleep at \(time)",
                trigger: AutomationTrigger(
                    type: "schedule",
                    humanReadable: "Every day at \(time)",
                    cron: cron,
                    timezone: TimeZone.current.identifier
                ),
                actions: [
                    // Would need to enumerate all lights
                    // Placeholder action
                    AutomationAction(
                        deviceName: "All Lights",
                        characteristic: "On",
                        value: .bool(false)
                    )
                ],
                enabled: true
            )
        }
    )
    
    // MARK: - Arrive Home
    
    static let arriveHome = AutomationTemplate(
        id: "arrive-home",
        name: "Arrive Home",
        category: "Location",
        description: "Welcome home with lights and temperature",
        icon: "🏠",
        parameters: [
            TemplateParameter(
                key: "entry_light",
                label: "Entry light",
                type: .device
            ),
            TemplateParameter(
                key: "keyword",
                label: "Shortcut keyword",
                type: .text,
                defaultValue: "I'm home"
            )
        ],
        generate: { context in
            let entryLight = context.getDevice("entry_light") ?? ""
            let keyword = context.getString("keyword") ?? "I'm home"
            
            return AutomationDefinition(
                name: "Arrive Home",
                description: "Triggered when arriving home",
                trigger: AutomationTrigger(
                    type: "manual",
                    humanReadable: "Say '\(keyword)' to Siri",
                    keyword: keyword
                ),
                actions: [
                    AutomationAction(
                        deviceUuid: entryLight,
                        deviceName: "Entry Light",
                        characteristic: "On",
                        value: .bool(true)
                    )
                ],
                enabled: true
            )
        }
    )
    
    // MARK: - Leave Home
    
    static let leaveHome = AutomationTemplate(
        id: "leave-home",
        name: "Leave Home",
        category: "Location",
        description: "Turn off everything when leaving",
        icon: "🚪",
        parameters: [
            TemplateParameter(
                key: "keyword",
                label: "Shortcut keyword",
                type: .text,
                defaultValue: "I'm leaving"
            )
        ],
        generate: { context in
            let keyword = context.getString("keyword") ?? "I'm leaving"
            
            return AutomationDefinition(
                name: "Leave Home",
                description: "Triggered when leaving home",
                trigger: AutomationTrigger(
                    type: "manual",
                    humanReadable: "Say '\(keyword)' to Siri",
                    keyword: keyword
                ),
                actions: [
                    AutomationAction(
                        deviceName: "All Lights",
                        characteristic: "On",
                        value: .bool(false)
                    )
                ],
                enabled: true
            )
        }
    )
    
    // MARK: - Movie Time
    
    static let movieTime = AutomationTemplate(
        id: "movie-time",
        name: "Movie Time",
        category: "Entertainment",
        description: "Dim lights for watching movies",
        icon: "🎬",
        parameters: [
            TemplateParameter(
                key: "living_room_light",
                label: "Living room light",
                type: .device
            ),
            TemplateParameter(
                key: "brightness",
                label: "Dimmed brightness",
                type: .brightness,
                defaultValue: 10
            ),
            TemplateParameter(
                key: "keyword",
                label: "Shortcut keyword",
                type: .text,
                defaultValue: "Movie time"
            )
        ],
        generate: { context in
            let livingRoomLight = context.getDevice("living_room_light") ?? ""
            let brightness = context.getInt("brightness") ?? 10
            let keyword = context.getString("keyword") ?? "Movie time"
            
            return AutomationDefinition(
                name: "Movie Time",
                description: "Set mood lighting for movies",
                trigger: AutomationTrigger(
                    type: "manual",
                    humanReadable: "Say '\(keyword)' to Siri",
                    keyword: keyword
                ),
                actions: [
                    AutomationAction(
                        deviceUuid: livingRoomLight,
                        deviceName: "Living Room Light",
                        characteristic: "Brightness",
                        value: .int(brightness)
                    )
                ],
                enabled: true
            )
        }
    )
}
