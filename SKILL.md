---
name: homekit-automator
description: >
  Full-featured Apple HomeKit smart home automation skill for macOS. Create, manage, and trigger
  complex home automations through natural conversation — lights, thermostats, locks, sensors,
  scenes, and more. Automations are registered as native Apple Shortcuts so they run reliably
  on schedule even when the AI agent isn't active. Use this skill whenever the user mentions
  smart home, HomeKit, home automation, Apple Home, lights, thermostat, locks, garage door,
  scenes, routines, or wants to control or automate anything in their house. Also trigger when
  the user mentions Shortcuts integration with home devices, energy monitoring, or asks about
  the state of devices in their home. This skill should be used even for simple queries like
  "turn off the lights" because it provides richer device context and error handling than
  raw commands.
version: 1.1.0
metadata:
  openclaw:
    emoji: "\U0001F3E0"
    os:
      - macos
    homepage: https://github.com/homekit-automator/homekit-automator
    requires:
      bins:
        - homekitauto
      env: []
    install:
      - kind: brew
        formula: homekit-automator
        bins:
          - homekitauto
---

# HomeKit Automator

A comprehensive Apple HomeKit automation skill that turns natural conversation into reliable
smart home control and scheduling. Built as a standalone macOS app with a native HomeKit bridge,
MCP server, and an automation engine that registers schedules as Apple Shortcuts.

## Quick Reference

Read `references/architecture.md` for the full system architecture and design decisions.
Read `references/mcp-tools.md` for detailed MCP tool specifications and parameters.
Read `references/automation-schema.md` for the automation definition format.
Read `references/shortcuts-integration.md` for how Apple Shortcuts bridging works.

## How This Skill Works

HomeKit Automator is a two-process macOS application:

1. **Main App** — A SwiftUI menu bar app that manages the UI, settings, and helper lifecycle
2. **HomeKit Bridge** — A Mac Catalyst helper that connects to Apple's HomeKit framework via
   `HMHomeManager` and communicates over a Unix domain socket in `~/Library/Application Support/homekit-automator/`

On top of this foundation, the skill provides:

- **MCP Server** (stdio) — 11 tools that Claude/OpenClaw can call for device control,
  automation management, and home intelligence
- **Automation Engine** — Parses natural language intent (via the LLM) into structured
  automation definitions, validates them against discovered devices (with Levenshtein fuzzy
  matching for device names, characteristic writability checks, and value range enforcement),
  evaluates conditions at runtime, and registers automations as native Apple Shortcuts
- **CLI Tool** (`homekitauto`) — Direct terminal access to all capabilities
- **Multi-Home Support** — All commands accept a `--home` flag to target a specific home
  when the user has more than one HomeKit home configured

## When to Use Each Tool

### Device Discovery and Control

Use `home_discover` as the first tool call in any new conversation about the user's home.
It returns a complete map of rooms, devices, and capabilities. Cache this mentally for the
session — you don't need to call it again unless the user adds new devices.

Use `device_control` for immediate, one-off commands. The user says "turn off the kitchen
lights" — that's a `device_control` call, not an automation.

Use `device_status` to check the current state of specific devices or rooms. Good for
answering "is the garage door open?" or "what's the temperature in the bedroom?"
When querying temperature, use the `units` parameter (`celsius` or `fahrenheit`) to return
values in the user's preferred scale. The CLI equivalent is `--units celsius|fahrenheit`.

Use `scene_trigger` when the user wants to activate an existing Apple Home scene. Scenes
are pre-configured in the Home app — this skill can trigger them but not create new ones
(use automations for custom multi-device actions).

### Automation Management

Use `automation_create` when the user wants something to happen automatically or repeatedly.
Key signals: "every morning," "when I leave," "at sunset," "on weekdays," or "set up a routine."

The LLM's job is to parse the user's intent into the automation schema (see
`references/automation-schema.md`). Pass the structured JSON via the `--definition` flag
(not `--json`). The engine runs a full validation pipeline before accepting:
- Device existence check (with Levenshtein fuzzy match for near-miss suggestions)
- Characteristic support and writability verification
- Value range enforcement
- Cron expression parsing and validation
- Duplicate automation name enforcement

Use `automation_list` to show the user their existing automations. Present them in a clean,
readable format — name, trigger, what it does, whether it's enabled.

Use `automation_edit` to modify an existing automation. The user might say "change my morning
routine to start at 7:15 instead of 7:00" — find the automation by name, apply the change.

Use `automation_delete` to remove an automation and its corresponding Apple Shortcut.

Use `automation_test` to dry-run an automation — execute all its device actions immediately
without registering a Shortcut. Great for "let me try my bedtime routine right now."

`automation_test` now evaluates conditions at runtime before executing actions. If the
automation has conditions (e.g., "only if temperature is below 70"), the test checks those
conditions against live device state and reports whether they passed or were skipped.

### Intelligence

Use `home_suggest` when the user asks for recommendations. This tool analyzes the device map
and current automations to suggest useful routines the user hasn't set up yet. The suggestion
engine includes seasonal awareness (e.g., heating suggestions in winter, fan/cooling in summer)
and pattern-based analysis (detecting repeated manual commands that could be automated).
For example, if they have motion sensors and lights but no motion-triggered lighting automation.

Use `energy_summary` for usage insights. This queries device states and automation history
to provide information about which devices are running, how often automations fire, and
potential optimizations. Pass `--history` to get week-over-week energy comparison data
for trend analysis.

## Parsing Natural Language Into Automations

This is the core intelligence the skill provides. When the user describes an automation in
natural language, follow this process:

### Step 1: Identify the Trigger

| User says | Trigger type | Parameters |
|-----------|-------------|------------|
| "every morning at 7" | `schedule` | cron: `0 7 * * *` |
| "on weekdays at 6:45am" | `schedule` | cron: `45 6 * * 1-5` |
| "at sunset" | `solar` | event: `sunset`, offset: 0 |
| "30 minutes before sunrise" | `solar` | event: `sunrise`, offset: -30 |
| "when I say bedtime" | `manual` | keyword: `bedtime` |
| "when the front door opens" | `device_state` | device, characteristic, value |

### Step 2: Identify Conditions (if any)

Conditions are optional guards. Examples:
- "only on weekdays" -> `day_of_week` condition
- "if it's after dark" -> `solar` condition
- "unless the temperature is above 75" -> `device_state` condition
- "only if I'm home" -> `occupancy` condition (requires presence sensor)

### Step 3: Identify Actions

Map each requested action to a device + characteristic + value:
- "turn on the kitchen lights" -> device: Kitchen Lights, characteristic: power, value: true
- "set brightness to 60%" -> device: (context), characteristic: brightness, value: 60
- "lock the front door" -> device: Front Door Lock, characteristic: lockState, value: locked
- "set the thermostat to 72" -> device: Thermostat, characteristic: targetTemp, value: 72

Actions can have delays between them: "turn on the lights, then after 5 minutes start the coffee maker"

### Step 4: Validate Against Device Map

Before creating the automation, verify every referenced device exists and supports the
requested characteristics. The validation engine handles this automatically with these checks:

- **Device not found** — Uses Levenshtein distance to suggest similar device names.
  If the user says "bedroom lamp" but the device is "Bedroom Light," the engine suggests it.
- **Read-only characteristic** — e.g., `currentTemperature` is read-only; suggest `targetTemperature` instead.
- **Value out of range** — e.g., brightness must be 0–100; the engine reports the valid range.
- **Characteristic not supported** — e.g., a basic switch doesn't have brightness.

If a device name is ambiguous ("the lights" when there are lights in multiple rooms),
ask the user to clarify.

### Step 5: Confirm With the User

Present a clean summary before creating:

```
Here's what I'll set up:

**Morning Routine** (weekdays at 6:45 AM)
Conditions: temperature below 70°F
1. Kitchen Lights -> on, brightness 60%
2. Thermostat -> heat to 72°F
3. Front Door Lock -> unlock
4. [after 5 min] Coffee Maker -> on

This will be registered as an Apple Shortcut that runs automatically.
Want me to create this?
```

Always show conditions in the summary so the user understands when the automation will
and won't fire.

### Step 6: Create and Register

Call `automation_create` with the structured definition via `--definition`. The engine
validates all devices, characteristics, value ranges, and cron expressions, then creates
the Apple Shortcut (checking for existing shortcuts with the same name first) and confirms
registration.

## Handling Ambiguity

Smart home commands are often ambiguous. Handle these gracefully:

- **"Turn off the lights"** — If there are lights in multiple rooms, ask which room, or offer
  "all lights." If the conversation has established a room context, use that.
- **"Make it warmer"** — Check current thermostat setting, suggest +2 degrees. If multiple
  thermostats, ask which zone.
- **"Set up a routine"** — Ask what the routine should be called and what it should do. Offer
  template suggestions based on discovered devices.
- **Device not found** — Suggest similar device names. Maybe they said "bedroom lamp" but the
  device is named "Bedroom Light."

## Error Handling

| Error | User-friendly response |
|-------|----------------------|
| Socket not connected | "HomeKit Automator doesn't seem to be running. Make sure the menu bar app is open." |
| Device not responding | "The [device] isn't responding. It might be offline or out of range." |
| Characteristic not supported | "The [device] doesn't support [action]. Here's what it can do: [list]." |
| Shortcut registration failed | "I couldn't register the automation as a Shortcut. Try opening the Shortcuts app and granting permission." |
| HomeKit unavailable | "HomeKit isn't available. Make sure you're signed into iCloud and have a Home set up in the Home app." |
| Device not found (with suggestion) | "I couldn't find 'Bedroom Lamp'. Did you mean 'Bedroom Light'?" (Levenshtein fuzzy match) |
| Read-only characteristic | "'currentTemperature' is read-only on the thermostat. Use 'targetTemperature' to set the desired temperature." |
| Value out of range | "Brightness must be between 0 and 100. You specified 150." |
| Duplicate automation name | "An automation named 'Morning Routine' already exists. Choose a different name or delete the existing one." |
| Cron parse error | "Invalid cron expression '60 7 * * *'. Minute must be 0–59." |
| Condition not met (during test) | "Condition not met: temperature is 73°F (expected below 70°F). Actions were skipped." |

## Templates

When the user asks to "set up a routine" without specifics, offer these templates based on
their discovered devices:

- **Morning** — Lights on (warm, gradual), thermostat to comfort, unlock doors
- **Bedtime** — Lights off (or dim to nightlight), doors locked, thermostat to sleep temp
- **Away** — All lights off, doors locked, thermostat to eco mode
- **Movie Night** — Living room lights dim to 10%, other rooms off
- **Guest Mode** — Guest room lights on, front door unlocked temporarily
- **Good Morning (weekend)** — Similar to morning but later, gentler lighting

The `home_suggest` tool also generates **seasonal suggestions** (e.g., winter heating
schedules, summer fan/cooling routines) and **pattern-based suggestions** (detecting
repeated manual commands that could be automated). Use these to proactively recommend
automations even when the user hasn't asked.

Only suggest templates that are possible given the user's actual devices.

## Multi-Home Support

When the user has multiple HomeKit homes (e.g., "Main House" and "Beach House"), all
commands accept a `--home` parameter to target a specific home. If not specified, the
default/primary home is used.

Examples:
- `home_discover` with `home: "Beach House"` — discover devices in that home only
- `device_control` with `home: "Beach House"`, `device: "Porch Lights"` — control a
  device in the Beach House
- `automation_create` with `home: "Beach House"` — register automation to the correct home

Always ask the user which home they mean if the conversation is ambiguous and they have
multiple homes.

## Temperature Units

The `device_status` and `device_control` tools accept a `units` parameter (`celsius` or
`fahrenheit`) for temperature values. The CLI equivalent is `--units celsius|fahrenheit`.

- When reading temperature: values are converted to the requested unit before display
- When setting temperature: the provided value is interpreted in the requested unit and
  converted to the device's native unit (Celsius for HomeKit) before sending
- Default behavior: uses the system locale to determine the preferred unit

Always match the user's preferred unit. If they say "72 degrees" in the US, that's Fahrenheit.
If they say "22 degrees" in Europe, that's Celsius.

## Energy History

The `energy_summary` tool supports a `--history` flag that returns week-over-week energy
comparison data. This includes:

- Total device on-time for the current vs. previous week
- Automation execution counts with trend direction (up/down/stable)
- Per-device usage deltas highlighting which devices are consuming more or less
- Actionable insights like "Thermostat ran 23% more this week — consider lowering target temp"

Use this when the user asks about energy trends, usage changes, or wants to optimize their
home's efficiency over time.

## Condition Evaluation

When `automation_test` is called on an automation with conditions, the engine evaluates
each condition against live device state before executing actions:

- **Time conditions** — checked against current system time
- **Day-of-week conditions** — checked against current day
- **Device state conditions** — queries the actual device value from HomeKit
- **Solar conditions** — checks current time against sunrise/sunset

If any condition is not met, the test reports which conditions failed and skips action
execution. This lets the user verify their conditions are correctly configured.

Example output when a condition blocks execution:
```
Condition check: Living Room Thermostat currentTemperature < 70
Current value: 73°F — condition NOT MET
Actions skipped (1 of 1 conditions failed)
```

## Configuration

The skill stores its configuration at `~/Library/Application Support/homekit-automator/`:

- `config.json` — Active home, device filters, preferences
- `automations.json` — Local automation registry (source of truth for what's been created)
- `device-cache.json` — Cached device map (refreshed on each `home_discover` call)

## Prerequisites

- macOS 14.0 (Sonoma) or later
- Apple Home app configured with at least one home and device
- iCloud signed in (HomeKit requires it)
- Apple Developer account (for HomeKit entitlement during development signing)
- Shortcuts app available (ships with macOS)
