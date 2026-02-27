# Apple Shortcuts Integration

This document explains how HomeKit Automator registers automations as native Apple Shortcuts
so they run reliably without the AI agent or app being active.

## Why Apple Shortcuts?

The core problem: AI agents are session-based. When the user closes Claude or OpenClaw, the
agent can't fire scheduled automations. We need a native scheduler.

Options considered:
- **launchd daemon** — Reliable but can't control HomeKit without the entitlement
- **cron jobs** — Same limitation, plus poor macOS integration
- **The app's own timer** — Only works while the app is running
- **Apple Shortcuts** — Native, runs on schedule, syncs across devices via iCloud, has
  built-in HomeKit actions, survives app closure and system sleep

Apple Shortcuts is the clear winner. Once an automation is registered as a Shortcut with a
Personal Automation trigger, Apple's system handles everything.

## How It Works

### Step 1: Build the Shortcut Definition

Each automation is translated into a Shortcut containing:
1. A **trigger** (time of day, arrival/departure, etc.)
2. Optional **conditions** (implemented as If blocks in the Shortcut)
3. **HomeKit actions** (Control Home, Set Scene)

### Step 2: Export as .shortcut File

The engine generates a `.shortcut` file (Apple's signed property list format) containing
the automation's actions. The file is saved to:

```
~/.config/homekit-automator/shortcuts/HKA_Morning_Routine.shortcut
```

All generated Shortcuts are prefixed with `HKA:` (HomeKit Automator) to distinguish them
from user-created Shortcuts.

### Step 3: Import via Shortcuts CLI or URL Scheme

Before importing, the engine checks whether a Shortcut with the same name already exists
using `shortcuts list | grep`. If a Shortcut with the same `HKA:` name is found:
- During **create**: the import is skipped and the existing Shortcut is reused
- During **edit**: the old Shortcut is deleted first, then the updated version is imported
- During **delete**: the Shortcut is removed via `shortcuts delete`

This prevents duplicate Shortcuts from accumulating when automations are recreated.

**Method 1: shortcuts CLI** (preferred, macOS 12+)
```bash
# Check existence first
shortcuts list | grep -q "^HKA: Morning Routine$" && echo "exists" || echo "not found"

# Import (only if not already present, or after deleting old version)
shortcuts import "HKA: Morning Routine" < ~/Library/Application\ Support/homekit-automator/shortcuts/HKA_Morning_Routine.shortcut
```

**Method 2: URL scheme** (fallback)
```
shortcuts://import-shortcut?url=file:///path/to/shortcut&name=HKA:%20Morning%20Routine
```

**Method 3: Open file** (most compatible)
```bash
open ~/Library/Application\ Support/homekit-automator/shortcuts/HKA_Morning_Routine.shortcut
```
This opens Shortcuts.app and prompts the user to add it.

### Step 4: Register Personal Automation

Personal Automations (time-triggered, location-triggered) cannot be created programmatically
as of macOS 15. The Shortcut itself is imported as a regular Shortcut, and the skill instructs
the user to:

1. Open Shortcuts app
2. Go to Automations tab
3. Create a new Personal Automation with the desired trigger
4. Set the action to "Run Shortcut" -> select the imported `HKA: Morning Routine`

For `manual` type automations, no Personal Automation is needed — the Shortcut can be run
directly via `shortcuts run "HKA: Morning Routine"` or from the AI agent.

**Future improvement**: If Apple adds programmatic Personal Automation creation (rumored for
macOS 27), the engine can automate this step entirely.

## Shortcut Actions Reference

### Control Home Accessory

The Shortcut action for controlling a HomeKit device:

```xml
<dict>
  <key>WFWorkflowActionIdentifier</key>
  <string>is.workflow.actions.homekit.set</string>
  <key>WFWorkflowActionParameters</key>
  <dict>
    <key>WFHomeAccessory</key>
    <dict>
      <key>id</key>
      <string>device-uuid</string>
      <key>name</key>
      <string>Kitchen Lights</string>
    </dict>
    <key>WFHomeCharacteristic</key>
    <string>brightness</string>
    <key>WFHomeValue</key>
    <integer>60</integer>
  </dict>
</dict>
```

### Trigger Scene

```xml
<dict>
  <key>WFWorkflowActionIdentifier</key>
  <string>is.workflow.actions.homekit.scene</string>
  <key>WFWorkflowActionParameters</key>
  <dict>
    <key>WFHomeScene</key>
    <dict>
      <key>id</key>
      <string>scene-uuid</string>
      <key>name</key>
      <string>Good Morning</string>
    </dict>
  </dict>
</dict>
```

### Wait Action (for delays)

```xml
<dict>
  <key>WFWorkflowActionIdentifier</key>
  <string>is.workflow.actions.delay</string>
  <key>WFWorkflowActionParameters</key>
  <dict>
    <key>WFDelayTime</key>
    <integer>300</integer>
  </dict>
</dict>
```

### If Condition (for conditions)

```xml
<dict>
  <key>WFWorkflowActionIdentifier</key>
  <string>is.workflow.actions.conditional</string>
  <key>WFWorkflowActionParameters</key>
  <dict>
    <key>WFCondition</key>
    <integer>4</integer>
    <key>WFConditionalActionString</key>
    <string>68</string>
  </dict>
</dict>
```

## Shortcut Naming Convention

All Shortcuts created by this skill follow this naming pattern:

```
HKA: {Automation Name}
```

Examples:
- `HKA: Morning Routine`
- `HKA: Bedtime`
- `HKA: Movie Night`
- `HKA: Away Mode`

This prefix makes it easy to identify and manage skill-created Shortcuts in the Shortcuts app.

## Managing Shortcuts

### List created Shortcuts
```bash
shortcuts list | grep "^HKA:"
```

### Run a Shortcut manually
```bash
shortcuts run "HKA: Morning Routine"
```

### Delete a Shortcut
```bash
shortcuts delete "HKA: Morning Routine"
```

### Check if a Shortcut exists
```bash
shortcuts list | grep -q "^HKA: Morning Routine$" && echo "exists" || echo "not found"
```

## iCloud Sync

Shortcuts sync across Apple devices via iCloud. This means:

- An automation created on a Mac can run on an iPhone or iPad
- If the Mac is asleep, the iPhone can still execute the Shortcut
- HomeKit actions in Shortcuts use the HomeKit hub (HomePod or Apple TV) for execution,
  so even if no personal device is awake, the hub can handle it

This is a significant advantage over app-based scheduling — the automation is truly
device-independent once registered.

## Limitations

1. **Personal Automations require manual setup** — The trigger (time, location) must be
   configured by the user in Shortcuts.app. The skill can only import the action Shortcut.
2. **No programmatic trigger creation** — Apple doesn't expose an API for creating Personal
   Automation triggers. This is the main limitation.
3. **Shortcut signing** — Imported Shortcuts may trigger a macOS trust prompt on first run
4. **Complex conditions** — While Shortcuts supports If/Else logic, deeply nested conditions
   are hard to express in the plist format. Keep conditions simple.
5. **Device state triggers** — These can't be done via Shortcuts alone. They require the
   HomeKit Automator app to be running and monitoring device state via the helper.
6. **Overwrite behavior** — The `shortcuts` CLI does not natively support overwriting an
   existing Shortcut. The engine must delete-then-import to update. There is a brief window
   during which the old Shortcut is gone and the new one isn't yet imported.
