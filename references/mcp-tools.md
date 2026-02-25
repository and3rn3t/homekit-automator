# MCP Tool Specifications

The HomeKit Automator MCP server exposes 10 tools via stdio transport.

## Discovery & Status

### home_discover

Returns a complete map of the user's HomeKit setup. Call this first in every new conversation.

**Parameters:** none

**Returns:**
```json
{
  "homes": [
    {
      "name": "My Home",
      "isPrimary": true,
      "rooms": [
        {
          "name": "Kitchen",
          "accessories": [
            {
              "uuid": "abc-123",
              "name": "Kitchen Lights",
              "category": "light",
              "reachable": true,
              "characteristics": [
                { "type": "power", "value": true, "writable": true },
                { "type": "brightness", "value": 80, "writable": true, "min": 0, "max": 100 },
                { "type": "hue", "value": 30, "writable": true, "min": 0, "max": 360 },
                { "type": "saturation", "value": 50, "writable": true, "min": 0, "max": 100 },
                { "type": "colorTemperature", "value": 300, "writable": true, "min": 140, "max": 500 }
              ]
            }
          ]
        }
      ],
      "scenes": [
        { "uuid": "def-456", "name": "Good Morning", "actions": 4 }
      ]
    }
  ],
  "automationCount": 3,
  "summary": "1 home, 4 rooms, 12 accessories, 2 scenes, 3 automations"
}
```

### device_status

Query the current state of one or more devices.

**Parameters:**
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `device` | string | yes* | Device name or UUID |
| `room` | string | yes* | Room name (returns all devices in room) |

*Provide either `device` or `room`, not both.

**Returns:**
```json
{
  "device": "Kitchen Lights",
  "uuid": "abc-123",
  "room": "Kitchen",
  "reachable": true,
  "state": {
    "power": true,
    "brightness": 80,
    "hue": 30,
    "saturation": 50,
    "colorTemperature": 300
  }
}
```

## Device Control

### device_control

Send an immediate command to a device.

**Parameters:**
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `device` | string | yes | Device name or UUID |
| `characteristic` | string | yes | What to change (power, brightness, targetTemperature, etc.) |
| `value` | any | yes | Target value (true/false, number, string) |

**Supported characteristics by category:**

| Category | Characteristics |
|----------|----------------|
| Lights | `power` (bool), `brightness` (0-100), `hue` (0-360), `saturation` (0-100), `colorTemperature` (140-500) |
| Thermostats | `targetTemperature` (number), `hvacMode` (off/heat/cool/auto), `targetHumidity` (0-100) |
| Locks | `lockState` (locked/unlocked) |
| Doors/Garage | `targetPosition` (open/closed or 0-100) |
| Fans | `active` (bool), `rotationSpeed` (0-100), `rotationDirection` (clockwise/counterclockwise), `swingMode` (bool) |
| Window Coverings | `targetPosition` (0-100) |
| Switches/Outlets | `power` (bool) |

**Returns:**
```json
{
  "device": "Kitchen Lights",
  "characteristic": "brightness",
  "previousValue": 80,
  "newValue": 60,
  "confirmed": true
}
```

### scene_trigger

Activate an Apple Home scene.

**Parameters:**
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `scene` | string | yes | Scene name or UUID |

**Returns:**
```json
{
  "scene": "Good Morning",
  "actionsExecuted": 4,
  "confirmed": true
}
```

## Automation Management

### automation_create

Create a new automation and register it as an Apple Shortcut.

**Parameters:**
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | yes | Human-readable automation name |
| `trigger` | object | yes | When the automation fires (see schema) |
| `conditions` | array | no | Optional guards |
| `actions` | array | yes | Ordered list of device actions |
| `enabled` | bool | no | Default: true |

See `references/automation-schema.md` for the full trigger, condition, and action schemas.

**Returns:**
```json
{
  "id": "auto-uuid-789",
  "name": "Morning Routine",
  "shortcutName": "HKA: Morning Routine",
  "registered": true,
  "trigger": "weekdays at 6:45 AM",
  "actionCount": 4
}
```

### automation_list

List all automations managed by this skill.

**Parameters:**
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `filter` | string | no | Filter by: "enabled", "disabled", "schedule", "manual" |

**Returns:**
```json
{
  "automations": [
    {
      "id": "auto-uuid-789",
      "name": "Morning Routine",
      "trigger": "weekdays at 6:45 AM",
      "actions": "4 actions (Kitchen Lights, Thermostat, Front Door, Coffee Maker)",
      "enabled": true,
      "lastRun": "2026-02-25T06:45:00Z",
      "shortcutName": "HKA: Morning Routine"
    }
  ],
  "total": 3,
  "enabled": 2,
  "disabled": 1
}
```

### automation_edit

Modify an existing automation.

**Parameters:**
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | yes* | Automation UUID |
| `name` | string | yes* | Automation name (alternative to id) |
| `changes` | object | yes | Partial automation object with fields to update |

*Provide either `id` or `name`.

**Returns:** Updated automation object (same format as `automation_create` response)

### automation_delete

Remove an automation and its Apple Shortcut.

**Parameters:**
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | yes* | Automation UUID |
| `name` | string | yes* | Automation name |

**Returns:**
```json
{
  "deleted": true,
  "name": "Morning Routine",
  "shortcutRemoved": true
}
```

### automation_test

Dry-run an automation — execute all its actions immediately without scheduling.

**Parameters:**
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | yes* | Automation UUID |
| `name` | string | yes* | Automation name |
| `actions` | array | yes* | Or provide raw actions to test without a saved automation |

*Provide `id`/`name` for an existing automation, or `actions` for ad-hoc testing.

**Returns:**
```json
{
  "tested": "Morning Routine",
  "results": [
    { "device": "Kitchen Lights", "action": "power -> true", "success": true },
    { "device": "Thermostat", "action": "targetTemperature -> 72", "success": true },
    { "device": "Front Door Lock", "action": "lockState -> unlocked", "success": true },
    { "device": "Coffee Maker", "action": "power -> true", "success": false, "error": "Device not reachable" }
  ],
  "succeeded": 3,
  "failed": 1
}
```

## Intelligence

### home_suggest

Analyze the user's home setup and suggest useful automations they haven't created yet.

**Parameters:**
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `focus` | string | no | Narrow suggestions: "energy", "security", "comfort", "convenience" |

**Returns:**
```json
{
  "suggestions": [
    {
      "name": "Auto-lock at Night",
      "reason": "You have a smart lock but no nighttime locking automation",
      "trigger": "daily at 10:00 PM",
      "actions": ["Front Door Lock -> locked"],
      "category": "security"
    },
    {
      "name": "Motion-Activated Hallway",
      "reason": "Hallway has a motion sensor and lights but they're not connected",
      "trigger": "when Hallway Motion Sensor detects motion",
      "actions": ["Hallway Lights -> on, brightness 40%"],
      "category": "convenience"
    }
  ]
}
```

### energy_summary

Provide insights about device usage and automation patterns.

**Parameters:**
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `period` | string | no | "today", "week", "month" (default: "week") |

**Returns:**
```json
{
  "period": "week",
  "devicesCurrentlyOn": ["Kitchen Lights", "Living Room TV", "Thermostat (heating)"],
  "automationRuns": 14,
  "mostActiveAutomation": "Morning Routine (7 runs)",
  "insights": [
    "The hallway lights have been on for 6 hours — they might have been left on accidentally",
    "Your thermostat has been in heating mode continuously since Tuesday — consider an eco schedule"
  ]
}
```
