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
version: 1.0.0
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
   `HMHomeManager` and communicates over a Unix domain socket at `/tmp/homekitauto.sock`

On top of this foundation, the skill provides:

- **MCP Server** (stdio) — 10 tools that Claude/OpenClaw can call for device control,
  automation management, and home intelligence
- **Automation Engine** — Parses natural language intent (via the LLM) into structured
  automation definitions, validates them against discovered devices, and registers them
  as native Apple Shortcuts
- **CLI Tool** (`homekitauto`) — Direct terminal access to all capabilities

## When to Use Each Tool

### Device Discovery and Control

Use `home_discover` as the first tool call in any new conversation about the user's home.
It returns a complete map of rooms, devices, and capabilities. Cache this mentally for the
session — you don't need to call it again unless the user adds new devices.

Use `device_control` for immediate, one-off commands. The user says "turn off the kitchen
lights" — that's a `device_control` call, not an automation.

Use `device_status` to check the current state of specific devices or rooms. Good for
answering "is the garage door open?" or "what's the temperature in the bedroom?"

Use `scene_trigger` when the user wants to activate an existing Apple Home scene. Scenes
are pre-configured in the Home app — this skill can trigger them but not create new ones
(use automations for custom multi-device actions).

### Automation Management

Use `automation_create` when the user wants something to happen automatically or repeatedly.
Key signals: "every morning," "when I leave," "at sunset," "on weekdays," or "set up a routine."

The LLM's job is to parse the user's intent into the automation schema (see
`references/automation-schema.md`). The engine handles validation and Shortcut registration.

Use `automation_list` to show the user their existing automations. Present them in a clean,
readable format — name, trigger, what it does, whether it's enabled.

Use `automation_edit` to modify an existing automation. The user might say "change my morning
routine to start at 7:15 instead of 7:00" — find the automation by name, apply the change.

Use `automation_delete` to remove an automation and its corresponding Apple Shortcut.

Use `automation_test` to dry-run an automation — execute all its device actions immediately
without registering a Shortcut. Great for "let me try my bedtime routine right now."

### Intelligence

Use `home_suggest` when the user asks for recommendations. This tool analyzes the device map
and current automations to suggest useful routines the user hasn't set up yet. For example,
if they have motion sensors and lights but no motion-triggered lighting automation.

Use `energy_summary` for usage insights. This queries device states and automation history
to provide information about which devices are running, how often automations fire, and
potential optimizations.

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
requested characteristics. If a device name is ambiguous ("the lights" when there are lights
in multiple rooms), ask the user to clarify. If a characteristic isn't supported (e.g.,
"dim the front door lock"), explain the limitation.

### Step 5: Confirm With the User

Present a clean summary before creating:

```
Here's what I'll set up:

**Morning Routine** (weekdays at 6:45 AM)
1. Kitchen Lights -> on, brightness 60%
2. Thermostat -> heat to 72 F
3. Front Door Lock -> unlock
4. [after 5 min] Coffee Maker -> on

This will be registered as an Apple Shortcut that runs automatically.
Want me to create this?
```

### Step 6: Create and Register

Call `automation_create` with the structured definition. The engine validates, creates the
Apple Shortcut, and confirms registration.

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

## Templates

When the user asks to "set up a routine" without specifics, offer these templates based on
their discovered devices:

- **Morning** — Lights on (warm, gradual), thermostat to comfort, unlock doors
- **Bedtime** — Lights off (or dim to nightlight), doors locked, thermostat to sleep temp
- **Away** — All lights off, doors locked, thermostat to eco mode
- **Movie Night** — Living room lights dim to 10%, other rooms off
- **Guest Mode** — Guest room lights on, front door unlocked temporarily
- **Good Morning (weekend)** — Similar to morning but later, gentler lighting

Only suggest templates that are possible given the user's actual devices.

## Configuration

The skill stores its configuration at `~/.config/homekit-automator/`:

- `config.json` — Active home, device filters, preferences
- `automations.json` — Local automation registry (source of truth for what's been created)
- `device-cache.json` — Cached device map (refreshed on each `home_discover` call)

## Prerequisites

- macOS 14.0 (Sonoma) or later
- Apple Home app configured with at least one home and device
- iCloud signed in (HomeKit requires it)
- Apple Developer account (for HomeKit entitlement during development signing)
- Shortcuts app available (ships with macOS)
