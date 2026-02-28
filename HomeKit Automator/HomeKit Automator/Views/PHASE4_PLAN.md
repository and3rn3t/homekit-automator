# Phase 4: CLI Enhancements - Implementation Plan

## Overview

Enhance the command-line interface (CLI) tool to provide a powerful alternative to the GUI with better interactivity, error messages, templates, and device discovery.

---

## Goals

1. **Interactive Mode** - Rich prompts with auto-completion
2. **Better Error Messages** - Clear, actionable feedback
3. **Automation Templates** - Pre-built automation patterns
4. **Device Discovery** - Interactive device selection
5. **Validation** - Check automations before saving
6. **Export/Import** - Share automations as JSON
7. **Batch Operations** - Manage multiple automations
8. **Color Output** - Improve readability

---

## Components to Build

### 1. **Interactive Prompts** (`InteractivePrompts.swift`)
- [ ] Rich text input with validation
- [ ] Yes/no confirmations
- [ ] Multiple choice menus
- [ ] Device picker with search
- [ ] Time picker (12h/24h)
- [ ] Cron expression builder

### 2. **Automation Templates** (`AutomationTemplates.swift`)
- [ ] Morning routine (lights, thermostat)
- [ ] Evening routine (lights, locks)
- [ ] Away mode (security)
- [ ] Arrive home (welcome scene)
- [ ] Movie time (lights, shades)
- [ ] Bedtime (all off)
- [ ] Custom template engine

### 3. **Device Discovery** (`DeviceDiscovery.swift`)
- [ ] Interactive device browser
- [ ] Room-based filtering
- [ ] Characteristic inspection
- [ ] Device search
- [ ] Recent devices
- [ ] Favorites

### 4. **Validation Engine** (`ValidationEngine.swift`)
- [ ] Check device UUIDs exist
- [ ] Validate characteristic types
- [ ] Verify value ranges
- [ ] Check cron expressions
- [ ] Validate conditions
- [ ] Pre-flight checks

### 5. **Export/Import** (`ImportExport.swift`)
- [ ] Export single automation
- [ ] Export all automations
- [ ] Import from JSON
- [ ] Import from file
- [ ] Merge strategies
- [ ] Conflict resolution

### 6. **Batch Operations** (`BatchOperations.swift`)
- [ ] Enable/disable multiple
- [ ] Delete multiple
- [ ] Duplicate automation
- [ ] Bulk edit
- [ ] Backup/restore

### 7. **Output Formatting** (`OutputFormatter.swift`)
- [ ] Colored terminal output
- [ ] Tables with borders
- [ ] Progress bars
- [ ] Status indicators
- [ ] JSON output mode
- [ ] Quiet mode

---

## Enhanced Commands

### Existing Commands (Improve):
```bash
homekitauto automation list
homekitauto automation create
homekitauto automation trigger <id>
homekitauto automation enable <id>
homekitauto automation disable <id>
homekitauto automation delete <id>
homekitauto device list
homekitauto scene list
```

### New Commands:
```bash
# Interactive creation with prompts
homekitauto automation create --interactive

# Create from template
homekitauto automation template morning-routine

# Device browser
homekitauto device browse

# Validation
homekitauto automation validate <id>

# Export/Import
homekitauto automation export <id> -o file.json
homekitauto automation export --all -o automations.json
homekitauto automation import -f file.json

# Batch operations
homekitauto automation enable --all
homekitauto automation disable --pattern "Night*"
homekitauto automation delete --disabled

# Status
homekitauto status --detailed
homekitauto logs --follow
homekitauto logs --automation <id>

# Configuration
homekitauto config set default-home "My Home"
homekitauto config list

# Backup/Restore
homekitauto backup create
homekitauto backup restore <file>
```

---

## User Experience Improvements

### Before (Current):
```bash
$ homekitauto automation create
Error: Missing required arguments
Usage: homekitauto automation create --json '{...}'
```

### After (Enhanced):
```bash
$ homekitauto automation create --interactive

🏠 HomeKit Automator - Create Automation
═══════════════════════════════════════

What would you like to automate?
❯ Use a template
  Create from scratch
  Import from file

Template selected: Morning Routine
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📝 Automation Name: Morning Lights
📅 When: Every weekday at 7:00 AM
🎯 Actions:
  1. Turn on Bedroom Light → 100%
  2. Turn on Kitchen Light → 80%
  3. Set Thermostat → 72°F

Looks good? (y/N): y

✓ Automation created successfully!
  ID: abc-123-def
  
Run now? (y/N): n

💡 Tip: Test your automation with: homekitauto automation trigger abc-123-def
```

---

## Interactive Creation Flow

```
1. Choose Method:
   - Template
   - Scratch
   - Import

2. If Template:
   - Select template
   - Customize parameters
   - Preview
   - Confirm

3. If Scratch:
   a. Name & Description
   b. Choose Trigger Type:
      - Schedule (time-based)
      - Solar (sunrise/sunset)
      - Manual (shortcut)
      - Device State
   
   c. Configure Trigger:
      - Schedule: Use cron builder
      - Solar: Choose event + offset
      - Manual: Enter keyword
      - Device: Select device + condition
   
   d. Add Actions:
      - Browse devices
      - Select device
      - Choose characteristic
      - Set value
      - Add delay (optional)
      - Add more actions
   
   e. Add Conditions (optional):
      - Time window
      - Days of week
      - Device state
   
   f. Review & Confirm

4. If Import:
   - Select file
   - Validate
   - Preview
   - Confirm
```

---

## Template System

### Template Definition:
```swift
struct AutomationTemplate {
    let id: String
    let name: String
    let category: String
    let description: String
    let icon: String
    let parameters: [TemplateParameter]
    let generate: (TemplateContext) -> AutomationDefinition
}

struct TemplateParameter {
    let key: String
    let label: String
    let type: ParameterType
    let defaultValue: Any?
    let required: Bool
}

enum ParameterType {
    case device
    case time
    case temperature
    case brightness
    case text
}
```

### Example Template:
```swift
let morningRoutine = AutomationTemplate(
    id: "morning-routine",
    name: "Morning Routine",
    category: "Daily Routines",
    description: "Turn on lights and adjust temperature in the morning",
    icon: "☀️",
    parameters: [
        TemplateParameter(
            key: "time",
            label: "Wake up time",
            type: .time,
            defaultValue: "07:00",
            required: true
        ),
        TemplateParameter(
            key: "bedroom_light",
            label: "Bedroom light",
            type: .device,
            defaultValue: nil,
            required: true
        ),
        TemplateParameter(
            key: "brightness",
            label: "Light brightness",
            type: .brightness,
            defaultValue: 80,
            required: false
        )
    ]
) { context in
    // Generate automation from parameters
}
```

---

## Validation Examples

### Device UUID Validation:
```bash
$ homekitauto automation validate abc-123

Validating automation "Morning Lights"...

✓ Name is valid
✓ Trigger is valid (schedule: 0 7 * * 1-5)
✗ Action 1: Device not found "Bedroom Light" (UUID: xyz-456)
  → Available devices:
     - Bedroom Lamp (uuid: abc-789)
     - Master Bedroom Light (uuid: def-012)
  
✗ Action 2: Invalid brightness value "150" (must be 0-100)

2 errors found. Automation will not execute correctly.

Fix issues? (Y/n): y
```

### Characteristic Validation:
```bash
✓ All device UUIDs exist
✗ Characteristic "Brightness" not found on "Smart Lock"
  → Available characteristics:
     - Lock Current State
     - Lock Target State
     - Battery Level
     
Suggestion: Did you mean "Lock Target State"?
```

---

## Color Output

### Terminal Colors:
```swift
enum TerminalColor {
    case reset
    case black, red, green, yellow, blue, magenta, cyan, white
    case brightBlack, brightRed, brightGreen, brightYellow
    case brightBlue, brightMagenta, brightCyan, brightWhite
    
    var code: String {
        // ANSI escape codes
    }
}

// Usage:
print("\(TerminalColor.green.code)✓ Success\(TerminalColor.reset.code)")
print("\(TerminalColor.red.code)✗ Error\(TerminalColor.reset.code)")
```

### Status Indicators:
```bash
[✓] Connected to HomeKit
[✗] Failed to load automation
[⚠] Warning: Device offline
[ℹ] Tip: Use --help for more options
[⏳] Executing automation...
[✨] Done!
```

---

## Device Browser

### Interactive Interface:
```bash
$ homekitauto device browse

🏠 HomeKit Device Browser
═══════════════════════════════════════

Home: My Home
Rooms: Living Room, Bedroom, Kitchen

Filter: [All Rooms ▼] [All Types ▼] [Search: _____]

Living Room
  💡 Living Room Light
     └─ On: false
     └─ Brightness: 0
     └─ Hue: 180
  
  🎬 Living Room TV
     └─ Active: false
     └─ Volume: 50

Bedroom  
  💡 Bedroom Lamp (offline)
     └─ On: ?
     └─ Brightness: ?

[↑↓] Navigate  [Enter] Details  [Q] Quit  [/] Search
```

---

## Implementation Priority

### Priority 1: Core UX (Essential)
1. Interactive creation flow
2. Color output
3. Better error messages
4. Device browser

### Priority 2: Templates (High Value)
5. Template system
6. 5-6 common templates
7. Template customization

### Priority 3: Validation (Important)
8. Device UUID validation
9. Characteristic validation
10. Value range checking

### Priority 4: Advanced (Nice to Have)
11. Export/Import
12. Batch operations
13. Backup/Restore
14. Config management

---

## Dependencies

### Swift Packages:
- **swift-argument-parser** - Command-line parsing (already used)
- **Rainbow** or **ANSITerminal** - Terminal colors
- **SwiftTerm** - Rich terminal UI (optional)

### Custom:
- All core logic already exists in models and helpers
- Just need CLI-specific wrappers

---

## File Structure

```
CLI/
├── main.swift (existing)
├── Commands/
│   ├── AutomationCommand.swift (enhance)
│   ├── DeviceCommand.swift (enhance)
│   ├── ConfigCommand.swift (new)
│   ├── BackupCommand.swift (new)
│   └── LogsCommand.swift (new)
│
├── Interactive/
│   ├── InteractivePrompts.swift
│   ├── DeviceBrowser.swift
│   ├── CronBuilder.swift
│   └── TemplateSelector.swift
│
├── Templates/
│   ├── TemplateEngine.swift
│   ├── BuiltInTemplates.swift
│   └── TemplateParameter.swift
│
├── Validation/
│   ├── ValidationEngine.swift
│   ├── DeviceValidator.swift
│   └── ValueValidator.swift
│
├── Output/
│   ├── OutputFormatter.swift
│   ├── TerminalColors.swift
│   ├── TableRenderer.swift
│   └── ProgressBar.swift
│
└── Utilities/
    ├── ImportExport.swift
    ├── BatchOperations.swift
    └── ConfigManager.swift
```

---

## Example Implementations

### Interactive Prompt:
```swift
func promptYesNo(_ question: String, default: Bool = false) -> Bool {
    let suffix = `default` ? " (Y/n)" : " (y/N)"
    print(question + suffix + ": ", terminator: "")
    
    guard let response = readLine()?.lowercased() else {
        return `default`
    }
    
    if response.isEmpty { return `default` }
    return response.hasPrefix("y")
}
```

### Device Picker:
```swift
func pickDevice(from devices: [DeviceInfo]) async throws -> DeviceInfo {
    print("\n📱 Select a device:\n")
    
    for (index, device) in devices.enumerated() {
        print("  \(index + 1). \(device.name) (\(device.room ?? "No Room"))")
    }
    
    print("\nEnter number (1-\(devices.count)): ", terminator: "")
    
    guard let input = readLine(),
          let choice = Int(input),
          choice > 0 && choice <= devices.count else {
        throw CLIError.invalidSelection
    }
    
    return devices[choice - 1]
}
```

---

## Testing Strategy

### Manual Testing:
1. Test each interactive flow
2. Verify color output in various terminals
3. Test error handling
4. Test templates
5. Test validation

### Automated Testing:
```swift
// Simulate user input
let testInput = """
y
Morning Routine
1
7:00
"""

// Run command with simulated input
// Verify output and file changes
```

---

## Timeline

### Week 1: Core UX
- Day 1-2: Interactive prompts & color output
- Day 3: Device browser
- Day 4: Better error messages

### Week 2: Templates & Validation
- Day 5-6: Template system + built-in templates
- Day 7: Validation engine

### Week 3: Advanced Features
- Day 8: Export/Import
- Day 9: Batch operations
- Day 10: Polish & documentation

**Total: ~10 days of work**

---

## Success Metrics

- ✅ User can create automation without reading docs
- ✅ Errors are clear and actionable
- ✅ Templates cover 80% of common use cases
- ✅ Device selection is intuitive
- ✅ Output is beautiful and readable
- ✅ CLI is faster than GUI for power users

---

## Next Steps

1. Enhance existing automation command with interactive mode
2. Add color output support
3. Implement device browser
4. Create template system
5. Add validation
6. Implement export/import

Ready to start building? 🚀
