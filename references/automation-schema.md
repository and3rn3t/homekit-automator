# Automation Schema

This document defines the JSON schema for automations. The LLM constructs these from natural
language; the engine validates and executes them.

## Top-Level Structure

```json
{
  "id": "uuid-auto-generated",
  "name": "Morning Routine",
  "description": "Warm up the house and get ready for the day",
  "trigger": { ... },
  "conditions": [ ... ],
  "actions": [ ... ],
  "enabled": true,
  "createdAt": "2026-02-25T10:30:00Z",
  "shortcutName": "HKA: Morning Routine",
  "shortcutId": "shortcut-uuid"
}
```

## Triggers

An automation has exactly one trigger. The trigger determines when the automation fires.

### Schedule Trigger

Fires on a cron-style schedule.

```json
{
  "type": "schedule",
  "cron": "45 6 * * 1-5",
  "humanReadable": "weekdays at 6:45 AM",
  "timezone": "America/New_York"
}
```

**Cron format:** `minute hour dayOfMonth month dayOfWeek`
- `0 7 * * *` — every day at 7:00 AM
- `45 6 * * 1-5` — weekdays at 6:45 AM
- `0 22 * * 0,6` — weekends at 10:00 PM
- `0 8 1 * *` — first of every month at 8:00 AM

The engine parses cron expressions and generates a `humanReadable` description automatically
if one is not provided. Invalid cron expressions (e.g., minute > 59, invalid day ranges) are
rejected with a descriptive error.

### Solar Trigger

Fires relative to sunrise or sunset.

```json
{
  "type": "solar",
  "event": "sunset",
  "offsetMinutes": -30,
  "humanReadable": "30 minutes before sunset"
}
```

- `event`: `"sunrise"` or `"sunset"`
- `offsetMinutes`: negative = before, positive = after, 0 = at the event

### Manual Trigger

Fires only when explicitly invoked by the user or the `automation_test` tool.

```json
{
  "type": "manual",
  "keyword": "bedtime",
  "humanReadable": "when you say 'bedtime'"
}
```

The `keyword` is what the LLM watches for. When the user says "run bedtime" or "time for bed,"
the LLM matches this keyword and calls `automation_test` with the automation's ID.

### Device State Trigger

Fires when a device characteristic reaches a specified value. Note: this type requires
the HomeKit Automator app to be running (it monitors device state via the helper).

```json
{
  "type": "device_state",
  "deviceUuid": "abc-123",
  "deviceName": "Front Door Lock",
  "characteristic": "lockState",
  "operator": "equals",
  "value": "unlocked",
  "humanReadable": "when Front Door Lock is unlocked"
}
```

**Operators:** `equals`, `notEquals`, `greaterThan`, `lessThan`, `greaterOrEqual`, `lessOrEqual`

## Conditions

Conditions are optional guards that must be true for the automation to execute. An automation
with conditions will only fire if the trigger fires AND all conditions are met.

### Time Condition

```json
{
  "type": "time",
  "after": "06:00",
  "before": "22:00",
  "humanReadable": "between 6 AM and 10 PM"
}
```

### Day of Week Condition

```json
{
  "type": "dayOfWeek",
  "days": [1, 2, 3, 4, 5],
  "humanReadable": "weekdays only"
}
```

Days: 0 = Sunday, 1 = Monday, ..., 6 = Saturday

### Device State Condition

```json
{
  "type": "deviceState",
  "deviceUuid": "xyz-789",
  "deviceName": "Thermostat",
  "characteristic": "currentTemperature",
  "operator": "lessThan",
  "value": 68,
  "humanReadable": "if temperature is below 68 F"
}
```

### Solar Condition

```json
{
  "type": "solar",
  "requirement": "after_sunset",
  "humanReadable": "only after dark"
}
```

Values: `after_sunset`, `before_sunset`, `after_sunrise`, `before_sunrise`

## Actions

Actions are executed in order. Each action targets a specific device and characteristic.

### Basic Action

```json
{
  "deviceUuid": "abc-123",
  "deviceName": "Kitchen Lights",
  "room": "Kitchen",
  "characteristic": "power",
  "value": true,
  "delaySeconds": 0
}
```

### Action With Delay

```json
{
  "deviceUuid": "abc-123",
  "deviceName": "Kitchen Lights",
  "room": "Kitchen",
  "characteristic": "brightness",
  "value": 60,
  "delaySeconds": 5
}
```

The `delaySeconds` field introduces a pause before this action executes. Use this for
sequences like "turn on the lights, then after 5 seconds set brightness to 60%."

### Multi-Characteristic Action

To set multiple characteristics on the same device (e.g., turn on a light AND set brightness),
create separate action entries. They'll execute in sequence:

```json
[
  { "deviceUuid": "abc-123", "deviceName": "Kitchen Lights", "characteristic": "power", "value": true, "delaySeconds": 0 },
  { "deviceUuid": "abc-123", "deviceName": "Kitchen Lights", "characteristic": "brightness", "value": 60, "delaySeconds": 0 },
  { "deviceUuid": "abc-123", "deviceName": "Kitchen Lights", "characteristic": "colorTemperature", "value": 350, "delaySeconds": 0 }
]
```

### Scene Action

Trigger an Apple Home scene as part of an automation:

```json
{
  "type": "scene",
  "sceneUuid": "def-456",
  "sceneName": "Good Morning",
  "delaySeconds": 0
}
```

## Complete Example

User: "Every weekday at 6:45am, if the temperature is below 70, turn on the kitchen lights
to a warm 60% brightness, heat the house to 72, and unlock the front door. Then after
5 minutes, turn on the coffee maker."

```json
{
  "name": "Weekday Morning Routine",
  "description": "Warm up the house and prep for the day on weekdays",
  "trigger": {
    "type": "schedule",
    "cron": "45 6 * * 1-5",
    "humanReadable": "weekdays at 6:45 AM",
    "timezone": "America/Chicago"
  },
  "conditions": [
    {
      "type": "deviceState",
      "deviceUuid": "therm-001",
      "deviceName": "Living Room Thermostat",
      "characteristic": "currentTemperature",
      "operator": "lessThan",
      "value": 70,
      "humanReadable": "if temperature is below 70 F"
    }
  ],
  "actions": [
    {
      "deviceUuid": "light-001",
      "deviceName": "Kitchen Lights",
      "room": "Kitchen",
      "characteristic": "power",
      "value": true,
      "delaySeconds": 0
    },
    {
      "deviceUuid": "light-001",
      "deviceName": "Kitchen Lights",
      "room": "Kitchen",
      "characteristic": "brightness",
      "value": 60,
      "delaySeconds": 0
    },
    {
      "deviceUuid": "light-001",
      "deviceName": "Kitchen Lights",
      "room": "Kitchen",
      "characteristic": "colorTemperature",
      "value": 350,
      "delaySeconds": 0
    },
    {
      "deviceUuid": "therm-001",
      "deviceName": "Living Room Thermostat",
      "room": "Living Room",
      "characteristic": "targetTemperature",
      "value": 72,
      "delaySeconds": 0
    },
    {
      "deviceUuid": "lock-001",
      "deviceName": "Front Door Lock",
      "room": "Entryway",
      "characteristic": "lockState",
      "value": "unlocked",
      "delaySeconds": 0
    },
    {
      "deviceUuid": "switch-001",
      "deviceName": "Coffee Maker",
      "room": "Kitchen",
      "characteristic": "power",
      "value": true,
      "delaySeconds": 300
    }
  ],
  "enabled": true
}
```

## Validation Rules

The automation engine enforces these rules before accepting an automation. All 7 rules are
fully implemented and run as a pipeline during `automation_create` and `automation_edit`:

1. **Device existence** — Every `deviceUuid` or `deviceName` must match a device in the current device map. If a name doesn't match exactly, the engine uses Levenshtein distance to suggest the closest match (e.g., "Bedroom Lamp" → "Did you mean 'Bedroom Light'?").
2. **Characteristic support** — Each device must support the referenced characteristic. The engine checks the device's reported characteristic list and returns available characteristics if the requested one is missing.
3. **Value range** — Numeric values must be within the device's reported min/max (e.g., brightness 0–100, hue 0–360, targetTemperature 10–38°C). The error includes the valid range.
4. **Writable check** — Cannot target read-only characteristics. For example, `currentTemperature` on a thermostat is read-only; the engine suggests `targetTemperature` instead. Read-only characteristics include `currentTemperature`, `currentHumidity`, `currentLockState`, `currentPosition`, `currentHeatingCoolingState`, `motionDetected`, `contactState`, `lightLevel`, `batteryLevel`, and `outletInUse`.
5. **Unique name** — Automation names must be unique across the registry. Duplicate names are rejected with an error since names map 1:1 to Shortcut identifiers.
6. **Non-empty actions** — Must have at least one action. Automations with zero actions are rejected.
7. **Valid cron** — Schedule triggers must have valid 5-field cron expressions. The parser validates field ranges (minute 0–59, hour 0–23, day 1–31, month 1–12, weekday 0–6) and generates a human-readable description.
8. **Delay limits** — `delaySeconds` must be between 0 and 3600 (1 hour max)

## Condition Evaluation

When `automation_test` is called, the `ConditionEvaluator` module checks all conditions
against live state before executing actions:

### Evaluation Flow

1. Load all conditions from the automation definition
2. For each condition, query the relevant data source:
   - **Time conditions** — compared against current system time
   - **Day-of-week conditions** — compared against current weekday
   - **Device state conditions** — queries the helper for the device's current characteristic value, then applies the operator (equals, lessThan, greaterThan, etc.)
   - **Solar conditions** — computes sunrise/sunset for the current date and location, then checks the requirement
3. If **all** conditions pass, actions are executed in order
4. If **any** condition fails, the test reports which conditions passed/failed and skips action execution

### Example Output

```json
{
  "tested": "Weekday Morning Routine",
  "conditionResults": [
    {
      "type": "deviceState",
      "description": "Living Room Thermostat currentTemperature < 70",
      "currentValue": 73,
      "passed": false,
      "reason": "Current value 73 is not less than 70"
    }
  ],
  "conditionsPassed": false,
  "actionsSkipped": true,
  "message": "1 of 1 conditions failed. Actions were not executed."
}
```

Condition evaluation is skipped when testing with raw `actions` (ad-hoc testing without
a saved automation) since there is no condition context.
