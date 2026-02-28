# Phase 5: Additional Features - Implementation Plan

## Overview

Implement the deferred features that make HomeKit Automator truly autonomous and powerful: scheduling, conditions, shortcuts, real-time sync, and more.

---

## Goals

1. **Scheduler** - Time-based and solar triggers
2. **Condition Evaluator** - Smart execution logic
3. **Shortcuts Integration** - Siri and Apple Shortcuts
4. **Real-time Sync** - GUI updates without refresh
5. **Push Notifications** - Event notifications
6. **Widgets** - Quick access to automations
7. **Analytics** - Usage insights

---

## Priority 1: Automation Scheduler (CRITICAL)

### What It Does:
Enables time-based and solar automations to run automatically in the background.

### Components:

#### 1. **Cron Parser** (`CronParser.swift`)
- [ ] Parse cron expressions (minute, hour, day, month, weekday)
- [ ] Calculate next run time
- [ ] Support wildcards and ranges
- [ ] Validate expressions
- [ ] Handle edge cases (leap years, DST)

Example:
```swift
let parser = CronParser()
let cron = try parser.parse("0 7 * * 1-5") // 7 AM weekdays
let nextRun = cron.nextRunDate(after: Date())
```

#### 2. **Solar Calculator** (`SolarCalculator.swift`)
- [ ] Calculate sunrise time for location
- [ ] Calculate sunset time for location
- [ ] Apply offset (minutes before/after)
- [ ] Update daily
- [ ] Handle timezone changes

Example:
```swift
let solar = SolarCalculator(latitude: 37.7749, longitude: -122.4194)
let sunrise = solar.sunrise(on: Date())
let sunset = solar.sunset(on: Date())
```

#### 3. **Automation Scheduler** (`AutomationScheduler.swift`)
- [ ] Load enabled automations on start
- [ ] Schedule timers for each automation
- [ ] Handle timer fires
- [ ] Reschedule after execution
- [ ] Cancel on disable/delete
- [ ] Persist next run times

Example:
```swift
actor AutomationScheduler {
    func schedule(_ automation: RegisteredAutomation)
    func unschedule(_ automationId: String)
    func getNextRun(_ automationId: String) -> Date?
}
```

#### 4. **Timer Manager** (`TimerManager.swift`)
- [ ] Single background thread for all timers
- [ ] Efficient timer coalescing
- [ ] Wake from sleep handling
- [ ] Battery-friendly scheduling
- [ ] Drift correction

---

## Priority 2: Condition Evaluator (HIGH)

### What It Does:
Checks conditions before executing automations (time windows, device states, etc.)

### Components:

#### 1. **Condition Evaluator** (`ConditionEvaluator.swift`)
- [ ] Time window conditions (after/before)
- [ ] Day of week conditions
- [ ] Device state conditions
- [ ] Location conditions (future)
- [ ] Boolean logic (AND/OR)
- [ ] Async device state checking

Example:
```swift
struct ConditionEvaluator {
    func evaluate(_ conditions: [AutomationCondition], context: ExecutionContext) async -> Bool
}
```

#### 2. **Execution Context** (`ExecutionContext.swift`)
- [ ] Current time
- [ ] Current day of week
- [ ] Current location (if available)
- [ ] Device states cache
- [ ] User presence

---

## Priority 3: Shortcuts Integration (MEDIUM)

### What It Does:
Allows triggering automations via Siri and Apple Shortcuts app.

### Components:

#### 1. **App Intents** (`AutomationIntents.swift`)
- [ ] TriggerAutomationIntent
- [ ] ListAutomationsIntent
- [ ] EnableAutomationIntent
- [ ] DisableAutomationIntent
- [ ] AppShortcutsProvider

Example:
```swift
import AppIntents

struct TriggerAutomationIntent: AppIntent {
    static var title: LocalizedStringResource = "Trigger Automation"
    
    @Parameter(title: "Automation")
    var automation: AutomationEntity
    
    func perform() async throws -> some IntentResult {
        // Trigger via helper
        return .result()
    }
}
```

#### 2. **Automation Entity** (`AutomationEntity.swift`)
- [ ] AppEntity conformance
- [ ] Entity query
- [ ] Display representation
- [ ] Type display representation

---

## Priority 4: Real-time Sync (MEDIUM)

### What It Does:
GUI updates automatically when automations are created/modified/executed.

### Components:

#### 1. **File System Watcher** (`FileWatcher.swift`)
- [ ] Monitor automations.json
- [ ] Monitor logs directory
- [ ] Debounce rapid changes
- [ ] Notify subscribers
- [ ] Handle file moves/deletes

Example:
```swift
@Observable
class FileWatcher {
    var lastChange: Date?
    
    func watch(path: URL, onChange: @escaping () -> Void)
}
```

#### 2. **Auto-Reload** (in AutomationStore)
- [ ] Subscribe to file changes
- [ ] Reload on change
- [ ] Throttle reloads
- [ ] Preserve UI state
- [ ] Show update indicator

---

## Priority 5: Push Notifications (LOW)

### What It Does:
Notify user when automations run, fail, or have issues.

### Components:

#### 1. **Notification Service** (`NotificationService.swift`)
- [ ] Request permission
- [ ] Automation executed notification
- [ ] Automation failed notification
- [ ] Device offline notification
- [ ] Helper disconnected notification
- [ ] Configurable per automation

Example:
```swift
struct NotificationService {
    func notify(automation: RegisteredAutomation, success: Bool, errors: [String]?)
}
```

---

## Priority 6: Widgets (LOW)

### What It Does:
Quick access to trigger automations from home screen/notification center.

### Components:

#### 1. **Widget Extension** (`AutomationWidget.swift`)
- [ ] Small widget (1 automation)
- [ ] Medium widget (3-4 automations)
- [ ] Large widget (automation list)
- [ ] Timeline provider
- [ ] Deep links to app

---

## Priority 7: Analytics (LOW)

### What It Does:
Shows insights about automation usage and success rates.

### Components:

#### 1. **Analytics View** (`AnalyticsView.swift`)
- [ ] Most used automations
- [ ] Success rate trends
- [ ] Execution timeline
- [ ] Device usage stats
- [ ] Charts with Swift Charts

---

## Implementation Timeline

### Week 1: Scheduler (CRITICAL)
**Priority**: Must-have for automatic execution

**Day 1-2**: Cron Parser
- Parse cron expressions
- Calculate next run
- Unit tests

**Day 3-4**: Solar Calculator
- Sunrise/sunset calculation
- Location handling
- Timezone support

**Day 5**: Integration
- Wire up to AutomationEngine
- Test with real automations
- Background execution

**Deliverable**: Automations run automatically on schedule

---

### Week 2: Conditions + Shortcuts (HIGH)
**Priority**: Important for smart automations

**Day 6-7**: Condition Evaluator
- Implement all condition types
- Device state checking
- Boolean logic

**Day 8-9**: Shortcuts Integration
- Create AppIntents
- Test with Siri
- Add to Shortcuts app

**Day 10**: Testing
- End-to-end scenarios
- Edge cases
- Documentation

**Deliverable**: Smart automations + Siri control

---

### Week 3: Real-time + Notifications (MEDIUM)
**Priority**: Quality of life improvements

**Day 11-12**: File Watcher
- Implement FS monitoring
- Auto-reload GUI
- Test synchronization

**Day 13-14**: Notifications
- Permission handling
- Notification types
- User preferences

**Day 15**: Polish
- UI improvements
- Bug fixes
- Documentation

**Deliverable**: Live GUI + helpful notifications

---

### Week 4: Widgets + Analytics (LOW)
**Priority**: Nice-to-have enhancements

**Day 16-17**: Widget Extension
- Create widget target
- Implement timeline
- Design layouts

**Day 18-19**: Analytics
- Data aggregation
- Chart rendering
- Export reports

**Day 20**: Final Polish
- Performance tuning
- Documentation
- Release prep

**Deliverable**: Widgets + insights

---

## Technical Deep Dives

### Cron Parsing Algorithm

```swift
struct CronExpression {
    let minute: CronField    // 0-59
    let hour: CronField      // 0-23
    let day: CronField       // 1-31
    let month: CronField     // 1-12
    let weekday: CronField   // 0-6 (Sun-Sat)
    
    func nextRunDate(after: Date) -> Date? {
        var components = Calendar.current.dateComponents([...], from: after)
        
        // Find next matching minute
        while !minute.matches(components.minute!) {
            components.minute! += 1
            // Handle overflow...
        }
        
        // Find next matching hour
        while !hour.matches(components.hour!) {
            components.hour! += 1
            components.minute = minute.first
            // Handle overflow...
        }
        
        // Continue for day, month, weekday...
        
        return Calendar.current.date(from: components)
    }
}

enum CronField {
    case any                    // *
    case specific(Int)          // 5
    case range(Int, Int)        // 1-5
    case list([Int])            // 1,3,5
    case step(Int, Int)         // */5
    
    func matches(_ value: Int) -> Bool {
        switch self {
        case .any: return true
        case .specific(let n): return value == n
        case .range(let min, let max): return value >= min && value <= max
        case .list(let values): return values.contains(value)
        case .step(let start, let step): return (value - start) % step == 0
        }
    }
}
```

### Solar Calculation Algorithm

```swift
// Based on NOAA Solar Calculator
struct SolarCalculator {
    let latitude: Double
    let longitude: Double
    
    func sunrise(on date: Date) -> Date {
        let jd = julianDate(date)
        let sunrise = calculateSunrise(jd, latitude, longitude)
        return date.adjusting(toTimeOfDay: sunrise)
    }
    
    private func julianDate(_ date: Date) -> Double {
        // Convert Gregorian to Julian Day
        // ...
    }
    
    private func calculateSunrise(_ jd: Double, _ lat: Double, _ lon: Double) -> Double {
        // Solar noon
        let solarNoon = jd + lon / 360.0
        
        // Solar anomaly
        let M = 357.5291 + 0.98560028 * (jd - 2451545)
        
        // Equation of center
        let C = 1.9148 * sin(M) + 0.0200 * sin(2*M) + 0.0003 * sin(3*M)
        
        // ... more complex calculations
        
        return sunriseTime
    }
}
```

### File Watching Implementation

```swift
import Foundation

actor FileWatcher {
    private var fileDescriptor: Int32?
    private var dispatchSource: DispatchSourceFileSystemObject?
    
    func watch(url: URL, handler: @escaping () -> Void) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        
        fileDescriptor = fd
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .background)
        )
        
        source.setEventHandler { [weak self] in
            Task {
                await handler()
            }
        }
        
        source.setCancelHandler { [weak self] in
            guard let fd = self?.fileDescriptor else { return }
            close(fd)
        }
        
        source.resume()
        dispatchSource = source
    }
}
```

---

## Dependencies

### System Frameworks:
- **Foundation** - Core functionality
- **AppIntents** - Shortcuts integration (iOS 16+, macOS 13+)
- **UserNotifications** - Push notifications
- **WidgetKit** - Widgets (optional)
- **Charts** - Swift Charts for analytics (optional)

### Third-party (Optional):
- **SunCalc** - Solar calculations (or implement ourselves)
- **FSEvents** - File system monitoring (or use DispatchSource)

---

## Testing Strategy

### Unit Tests:
```swift
import Testing

@Suite("Cron Parser Tests")
struct CronParserTests {
    @Test("Parse simple cron")
    func parseSimple() throws {
        let cron = try CronParser().parse("0 7 * * *")
        #expect(cron.minute == .specific(0))
        #expect(cron.hour == .specific(7))
    }
    
    @Test("Calculate next run")
    func nextRun() throws {
        let cron = try CronParser().parse("0 7 * * 1-5")
        let now = Date() // Friday at 6 AM
        let next = cron.nextRunDate(after: now)
        // Should be Friday at 7 AM
    }
}

@Suite("Solar Calculator Tests")
struct SolarCalculatorTests {
    @Test("Sunrise calculation")
    func sunrise() {
        let solar = SolarCalculator(latitude: 37.7749, longitude: -122.4194)
        let sunrise = solar.sunrise(on: Date())
        // Verify time is reasonable
        #expect(sunrise.hour >= 5 && sunrise.hour <= 8)
    }
}
```

### Integration Tests:
- Schedule automation → verify it runs at correct time
- Add condition → verify automation skips when false
- Trigger via Siri → verify execution
- Modify file → verify GUI updates

---

## Performance Considerations

### Scheduler:
- Single timer thread for efficiency
- Coalesce similar wake times
- Minimum 1-minute granularity (don't schedule seconds)
- Battery-friendly: use `tolerance` parameter

### File Watcher:
- Debounce rapid changes (300ms)
- Only watch specific files, not entire directory
- Unwatch when app in background

### Notifications:
- Respect user preferences
- Batch multiple failures
- Rate limit (max 5/hour)

---

## Security & Privacy

### Permissions:
- Location: Only if user enables solar triggers
- Notifications: Ask on first automation run
- Shortcuts: Automatic with AppIntents

### Data:
- All data stays local
- No analytics tracking
- No cloud sync (future feature)

---

## Success Metrics

### Phase 5 Complete When:
- ✅ Cron automations run on schedule
- ✅ Solar automations run at sunrise/sunset
- ✅ Conditions evaluated before execution
- ✅ Can trigger via Siri
- ✅ Appears in Shortcuts app
- ✅ GUI updates automatically
- ✅ Notifications work
- ✅ All tests pass

---

## Recommended Approach

### Option A: Full Implementation (~3 weeks)
Build everything in this plan. Comprehensive but time-consuming.

### Option B: MVP Features (~1 week)
Focus on **Scheduler** + **Conditions** only. Get automations working automatically, skip polish features.

### Option C: Scheduler Only (~3-4 days)
Just the critical missing piece. Automations run on schedule.

---

## My Recommendation

**Option C: Scheduler Only**

Here's why:
1. It's the **#1 missing feature**
2. Makes automations actually automatic
3. Reasonable implementation time (~3-4 days)
4. Other features are nice-to-have

Then users have a **fully autonomous system**:
- ✅ Create with natural language
- ✅ Execute automatically on schedule
- ✅ Log all executions
- ✅ Manage via beautiful GUI or CLI

Everything else (conditions, Siri, widgets) can be added incrementally based on user feedback.

---

## Ready to Start?

I can implement:

1. **Scheduler Only** (Recommended - ~3-4 days)
2. **Scheduler + Conditions** (~1 week)
3. **Full Phase 5** (~3 weeks)

Which would you like? 🎯
