# Phase 3: Build Helper App - Implementation Plan

## Overview

The **HomeKitHelper** is a companion macOS app that provides HomeKit framework access to the main HomeKit Automator app via Unix domain sockets. It runs in the background (agent) and handles all HomeKit communication.

---

## Architecture

```
┌─────────────────────────┐
│  HomeKit Automator      │
│  (SwiftUI GUI)          │
└───────────┬─────────────┘
            │ Unix Socket
            │ (JSON Commands)
            ▼
┌─────────────────────────┐
│  HomeKitHelper          │
│  (Background Agent)     │
├─────────────────────────┤
│  • Socket Server        │
│  • HomeKit Manager      │
│  • Automation Engine    │
│  • Scheduler            │
│  • Shortcut Handler     │
└───────────┬─────────────┘
            │ HomeKit Framework
            ▼
┌─────────────────────────┐
│  Apple HomeKit          │
│  (Devices & Services)   │
└─────────────────────────┘
```

---

## Components to Build

### 1. **App Structure**
- [ ] HomeKitHelperApp.swift - Main entry point
- [ ] Info.plist - Background agent configuration
- [ ] Entitlements - HomeKit capability

### 2. **Socket Server** (`SocketServer.swift`)
- [ ] Unix domain socket creation
- [ ] Connection handling
- [ ] Command routing
- [ ] Response formatting
- [ ] Token authentication
- [ ] Error handling

### 3. **HomeKit Manager** (`HomeKitManager.swift`)
- [ ] HMHomeManager integration
- [ ] Home discovery
- [ ] Accessory enumeration
- [ ] Characteristic reading/writing
- [ ] Scene activation
- [ ] Delegate callbacks

### 4. **Device Map Generator** (`DeviceMapGenerator.swift`)
- [ ] Scan all homes
- [ ] Enumerate accessories
- [ ] Extract characteristics
- [ ] Format as JSON
- [ ] Cache for performance

### 5. **Automation Engine** (`AutomationEngine.swift`)
- [ ] Load automations from disk
- [ ] Evaluate triggers
- [ ] Check conditions
- [ ] Execute actions
- [ ] Log results
- [ ] Error recovery

### 6. **Scheduler** (`AutomationScheduler.swift`)
- [ ] Cron expression parsing
- [ ] Timer management
- [ ] Solar event calculation (sunrise/sunset)
- [ ] Trigger evaluation
- [ ] Thread-safe execution

### 7. **Shortcut Integration** (`ShortcutHandler.swift`)
- [ ] AppIntent definitions
- [ ] Manual trigger handling
- [ ] Siri integration
- [ ] Parameter passing

### 8. **Command Handler** (`CommandHandler.swift`)
- [ ] Parse JSON commands
- [ ] Route to appropriate service
- [ ] Execute operations
- [ ] Format responses
- [ ] Handle errors

---

## File Structure

```
HomeKitHelper/
├── HomeKitHelperApp.swift           # Main entry point
├── Info.plist                        # Agent configuration
├── HomeKitHelper.entitlements       # HomeKit capability
│
├── Server/
│   ├── SocketServer.swift           # Unix socket server
│   ├── CommandHandler.swift         # Command routing
│   └── SocketConstants.swift        # Shared with main app
│
├── HomeKit/
│   ├── HomeKitManager.swift         # HMHomeManager wrapper
│   ├── DeviceMapGenerator.swift    # Device enumeration
│   ├── CharacteristicWriter.swift  # Write values to devices
│   └── SceneController.swift       # Scene activation
│
├── Automation/
│   ├── AutomationEngine.swift      # Core execution engine
│   ├── AutomationScheduler.swift   # Trigger management
│   ├── AutomationRegistry.swift    # Persistence layer
│   ├── TriggerEvaluator.swift      # Condition checking
│   └── ActionExecutor.swift        # Device control
│
├── Shortcuts/
│   ├── ShortcutHandler.swift       # AppIntents
│   └── TriggerAutomationIntent.swift
│
├── Models/
│   └── Models.swift                 # Shared with main app
│
└── Utilities/
    ├── Logger.swift                 # Logging system
    └── DateHelpers.swift            # Date/time utilities
```

---

## Implementation Steps

### Step 1: Basic App Structure (30 min)
- Create HomeKitHelper target in Xcode
- Configure Info.plist as agent
- Add HomeKit entitlement
- Create main app file

### Step 2: Socket Server (1 hour)
- Implement Unix domain socket
- Add connection handling
- Create command routing
- Test with simple commands

### Step 3: HomeKit Manager (1.5 hours)
- Integrate HMHomeManager
- Implement device discovery
- Add characteristic reading
- Test device control

### Step 4: Device Map (30 min)
- Generate device hierarchy
- Format as JSON
- Add caching
- Test with real devices

### Step 5: Automation Engine (2 hours)
- Load automations from disk
- Implement action execution
- Add error handling
- Test simple automations

### Step 6: Scheduler (1.5 hours)
- Parse cron expressions
- Set up timers
- Add solar calculations
- Test scheduled triggers

### Step 7: Shortcuts (1 hour)
- Define AppIntents
- Implement handlers
- Test with Siri
- Add to Shortcuts app

### Step 8: Testing & Polish (1 hour)
- End-to-end testing
- Error recovery
- Performance tuning
- Documentation

**Total Estimated Time: 8-10 hours**

---

## Key Technologies

### HomeKit Framework
```swift
import HomeKit

// Main manager
let homeManager = HMHomeManager()

// Access homes
let home = homeManager.primaryHome

// Control device
let accessory = home.accessories.first
let service = accessory.services.first
let characteristic = service.characteristics.first
characteristic.writeValue(true)
```

### Unix Domain Sockets
```swift
import Darwin

let sock = socket(AF_UNIX, SOCK_STREAM, 0)
var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
// ... configure and bind
listen(sock, 5)
```

### Cron Expression Parsing
```swift
// "0 7 * * 1-5" = 7 AM weekdays
struct CronExpression {
    let minute: [Int]
    let hour: [Int]
    let day: [Int]
    let month: [Int]
    let weekday: [Int]
}
```

### AppIntents (Shortcuts)
```swift
import AppIntents

struct TriggerAutomationIntent: AppIntent {
    static var title: LocalizedStringResource = "Trigger Automation"
    
    @Parameter(title: "Automation Name")
    var name: String
    
    func perform() async throws -> some IntentResult {
        // Trigger automation
        return .result()
    }
}
```

---

## Security Considerations

### 1. **Socket Authentication**
- Generate unique token on first launch
- Store in UserDefaults (shared with main app)
- Validate on every command
- Reject invalid tokens

### 2. **File Permissions**
- Socket file: 0600 (owner only)
- Automation registry: 0600
- Log files: 0600

### 3. **HomeKit Permissions**
- Request user authorization
- Handle denied state gracefully
- Show helpful error messages

---

## Performance Optimizations

### 1. **Device Map Caching**
- Cache for 5 minutes
- Invalidate on home changes
- Background refresh

### 2. **Characteristic Reading**
- Batch reads when possible
- Cache frequently-accessed values
- Async operations

### 3. **Scheduler Efficiency**
- Single timer for all automations
- Check next trigger time
- Sleep until needed

---

## Error Handling

### Automation Execution Errors
```swift
enum AutomationError: Error {
    case deviceNotFound
    case characteristicNotFound
    case writeValueFailed
    case conditionNotMet
    case timeout
}
```

### Logging Strategy
- Console: Errors and warnings
- File: All events (for history view)
- JSON format for parsing

---

## Testing Strategy

### Unit Tests
- Cron parsing
- Trigger evaluation
- Condition checking
- Action formatting

### Integration Tests
- Socket communication
- HomeKit device control
- End-to-end automation

### Manual Tests
- Real HomeKit devices
- Multiple homes
- Complex automations
- Error scenarios

---

## Milestones

### Milestone 1: Basic Communication ✓
- Socket server running
- Can respond to "status" command
- Main app can connect

### Milestone 2: Device Discovery ✓
- Can list homes
- Can enumerate accessories
- Returns device map JSON

### Milestone 3: Device Control ✓
- Can write characteristics
- Can activate scenes
- Error handling works

### Milestone 4: Simple Automation ✓
- Can execute manual trigger
- Actions run successfully
- Logs to file

### Milestone 5: Scheduled Automation ✓
- Cron parsing works
- Timer fires correctly
- Automation executes on schedule

### Milestone 6: Full Features ✓
- All trigger types work
- Conditions evaluated
- Shortcuts integrated
- Error recovery solid

---

## Dependencies

### System Frameworks
- HomeKit.framework
- Foundation.framework
- AppIntents.framework (for Shortcuts)

### Shared Code
- Models.swift (from main app)
- SocketConstants.swift (from main app)

---

## Configuration Files

### Info.plist
```xml
<key>LSUIElement</key>
<true/>
<key>NSHomeKitUsageDescription</key>
<string>HomeKit Automator needs access to your HomeKit devices to create and execute automations.</string>
```

### Entitlements
```xml
<key>com.apple.developer.homekit</key>
<true/>
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

---

## Next Steps

1. Create HomeKitHelper Xcode target
2. Implement socket server
3. Add HomeKit integration
4. Build automation engine
5. Test with real devices

Ready to start building? 🚀
