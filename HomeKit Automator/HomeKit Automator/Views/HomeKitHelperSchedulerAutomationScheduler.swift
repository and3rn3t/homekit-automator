// AutomationScheduler.swift
// Manages scheduling and execution of time-based automations.

import Foundation

/// Manages scheduling for all enabled automations.
actor AutomationScheduler {
    
    // MARK: - Properties
    
    private let engine: AutomationEngine
    private let registry: AutomationRegistry
    private let logger = HelperLogger.shared
    
    private var scheduledAutomations: [String: ScheduledAutomation] = [:]
    private var timerTask: Task<Void, Never>?
    private var isRunning = false
    
    // Solar calculator (default to San Francisco, can be updated)
    private var solarCalculator: SolarCalculator = .sanFrancisco
    
    // MARK: - Init
    
    init(engine: AutomationEngine, registry: AutomationRegistry) {
        self.engine = engine
        self.registry = registry
    }
    
    // MARK: - Lifecycle
    
    /// Starts the scheduler and loads all enabled automations.
    func start() async {
        guard !isRunning else { return }
        
        await logger.log("Automation scheduler starting", level: .info)
        isRunning = true
        
        // Load all automations
        do {
            let automations = try await registry.load()
            for automation in automations where automation.enabled {
                await schedule(automation)
            }
            
            await logger.log("Scheduled \(scheduledAutomations.count) automation(s)", level: .info)
        } catch {
            await logger.logError(error)
        }
        
        // Start main timer loop
        startTimerLoop()
    }
    
    /// Stops the scheduler.
    func stop() async {
        await logger.log("Automation scheduler stopping", level: .info)
        
        isRunning = false
        timerTask?.cancel()
        timerTask = nil
        scheduledAutomations.removeAll()
        
        await logger.log("Automation scheduler stopped", level: .info)
    }
    
    // MARK: - Scheduling
    
    /// Schedules an automation for execution.
    func schedule(_ automation: RegisteredAutomation) async {
        // Only schedule enabled automations
        guard automation.enabled else {
            return
        }
        
        // Calculate next run time based on trigger type
        let nextRun: Date?
        
        switch automation.trigger.type {
        case "schedule":
            nextRun = await calculateNextScheduledRun(for: automation)
            
        case "solar":
            nextRun = await calculateNextSolarRun(for: automation)
            
        default:
            // Manual or device state triggers are not scheduled
            return
        }
        
        guard let runDate = nextRun else {
            await logger.log("Could not calculate next run for \(automation.name)", level: .warning)
            return
        }
        
        let scheduled = ScheduledAutomation(
            automation: automation,
            nextRun: runDate
        )
        
        scheduledAutomations[automation.id] = scheduled
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        
        await logger.log(
            "Scheduled '\(automation.name)' for \(formatter.string(from: runDate))",
            level: .debug
        )
    }
    
    /// Unschedules an automation.
    func unschedule(_ automationId: String) async {
        scheduledAutomations.removeValue(forKey: automationId)
        await logger.log("Unscheduled automation: \(automationId)", level: .debug)
    }
    
    /// Reschedules an automation after execution.
    private func reschedule(_ automationId: String) async {
        guard let scheduled = scheduledAutomations[automationId] else {
            return
        }
        
        // Schedule again
        await schedule(scheduled.automation)
    }
    
    // MARK: - Next Run Calculation
    
    private func calculateNextScheduledRun(for automation: RegisteredAutomation) async -> Date? {
        guard let cronString = automation.trigger.cron else {
            await logger.log("No cron expression for scheduled automation: \(automation.name)", level: .warning)
            return nil
        }
        
        do {
            let parser = CronParser()
            let cron = try parser.parse(cronString)
            return cron.nextRunDate(after: Date())
        } catch {
            await logger.log("Failed to parse cron '\(cronString)': \(error.localizedDescription)", level: .error)
            return nil
        }
    }
    
    private func calculateNextSolarRun(for automation: RegisteredAutomation) async -> Date? {
        guard let event = automation.trigger.event else {
            await logger.log("No solar event for automation: \(automation.name)", level: .warning)
            return nil
        }
        
        let offset = automation.trigger.offsetMinutes ?? 0
        
        let solarEvent = SolarEvent(
            type: event == "sunrise" ? .sunrise : .sunset,
            offsetMinutes: offset
        )
        
        // Try today first
        if let time = solarEvent.calculateTime(on: Date(), calculator: solarCalculator),
           time > Date() {
            return time
        }
        
        // Otherwise tomorrow
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return solarEvent.calculateTime(on: tomorrow, calculator: solarCalculator)
    }
    
    // MARK: - Timer Loop
    
    private func startTimerLoop() {
        timerTask = Task { [weak self] in
            guard let self = self else { return }
            
            while await self.isRunning {
                await self.checkAndExecute()
                
                // Sleep for 30 seconds (or until next wake)
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
    
    private func checkAndExecute() async {
        let now = Date()
        let tolerance: TimeInterval = 60 // 1 minute tolerance
        
        for (id, scheduled) in scheduledAutomations {
            // Check if it's time to run
            if abs(scheduled.nextRun.timeIntervalSince(now)) <= tolerance {
                await logger.log("Triggering scheduled automation: \(scheduled.automation.name)", level: .info)
                
                // Execute
                do {
                    try await engine.triggerAutomation(id: id)
                    await logger.log("Successfully executed: \(scheduled.automation.name)", level: .info)
                } catch {
                    await logger.log("Failed to execute \(scheduled.automation.name): \(error)", level: .error)
                }
                
                // Reschedule for next run
                await reschedule(id)
            }
        }
    }
    
    // MARK: - Location
    
    /// Updates the location for solar calculations.
    func updateLocation(latitude: Double, longitude: Double) async {
        solarCalculator = SolarCalculator(latitude: latitude, longitude: longitude)
        
        await logger.log("Updated solar calculator location to \(latitude), \(longitude)", level: .info)
        
        // Reschedule all solar automations
        for scheduled in scheduledAutomations.values where scheduled.automation.trigger.type == "solar" {
            await schedule(scheduled.automation)
        }
    }
    
    // MARK: - Status
    
    /// Returns the next run date for an automation.
    func getNextRun(for automationId: String) async -> Date? {
        scheduledAutomations[automationId]?.nextRun
    }
    
    /// Returns all scheduled automations.
    func getAllScheduled() async -> [ScheduledAutomation] {
        Array(scheduledAutomations.values).sorted { $0.nextRun < $1.nextRun }
    }
}

// MARK: - Scheduled Automation

struct ScheduledAutomation {
    let automation: RegisteredAutomation
    let nextRun: Date
}
