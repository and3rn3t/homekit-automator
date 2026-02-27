# Architecture

## System Overview

```
                    ┌─────────────────────────────┐
                    │   Claude / OpenClaw (LLM)    │
                    └──────────────┬──────────────┘
                                   │ MCP (stdio)
                    ┌──────────────▼──────────────┐
                    │      MCP Server (Node.js)    │
                    │   Wraps homekitauto CLI       │
                    └──────────────┬──────────────┘
                                   │ subprocess
                    ┌──────────────▼──────────────┐
                    │    homekitauto CLI (Swift)    │
                    │  Commands → Socket Messages   │
                    │                               │
                    │  Key modules:                 │
                    │  • AutomationValidator        │
                    │  • ConditionEvaluator         │
                    │  • AutomationRegistry         │
                    │  • ShortcutGenerator          │
                    │  • HomeAnalyzer               │
                    │  • Logger (swift-log)         │
                    └──────────────┬──────────────┘
                                   │ Unix socket
                    ┌──────────────▼──────────────┐
                    │  HomeKit Automator.app        │
                    │                               │
                    │  ┌─────────────────────────┐ │
                    │  │  SwiftUI Menu Bar App    │ │
                    │  │  - Dashboard view         │ │
                    │  │  - Settings UI            │ │
                    │  │  - History / log view     │ │
                    │  │  - Helper lifecycle mgmt  │ │
                    │  │  - AutomationStore        │ │
                    │  └────────────┬────────────┘ │
                    │               │ process mgmt  │
                    │  ┌────────────▼────────────┐ │
                    │  │  HomeKitHelper           │ │
                    │  │  (Mac Catalyst)          │ │
                    │  │  - HMHomeManager         │ │
                    │  │  - Socket server         │ │
                    │  │  - Device state cache    │ │
                    │  │  - State change monitor  │ │
                    │  └────────────┬────────────┘ │
                    └───────────────┼──────────────┘
                                    │
                    ┌───────────────▼──────────────┐
                    │       Apple HomeKit           │
                    │   (Devices, Scenes, Homes)    │
                    └──────────────────────────────┘
                                    │
                    ┌───────────────▼──────────────┐
                    │      Apple Shortcuts          │
                    │  (Registered Automations)     │
                    │  Runs on schedule via Apple    │
                    └──────────────────────────────┘
```

## Process Communication

### Unix Domain Socket Protocol

Location: `~/Library/Application Support/homekit-automator/homekitauto.sock`
Format: JSON messages delimited by newline (`\n`)

**Request format:**
```json
{
  "id": "uuid-string",
  "command": "command_name",
  "params": { ... },
  "token": "auth-token-string",
  "version": 1
}
```

**Response format:**
```json
{
  "id": "uuid-string",
  "status": "ok" | "error",
  "data": { ... },
  "error": "message if status is error"
}
```

### Commands

| Command | Params | Returns |
|---------|--------|---------|
| `status` | none | Bridge status, home names, accessory count |
| `discover` | `home?` | Full device map: homes, rooms, accessories, characteristics |
| `get_device` | `name` or `uuid`, `home?`, `units?` | Device state with all characteristics |
| `set_device` | `uuid`, `characteristic`, `value`, `home?`, `units?` | Confirmation |
| `list_rooms` | `home?` | Rooms with accessory summaries |
| `list_scenes` | `home?` | Available scenes |
| `trigger_scene` | `name` or `uuid`, `home?` | Confirmation |
| `get_config` | none | Current configuration |
| `set_config` | key-value pairs | Updated configuration |
| `state_changes` | `home?` | Recent device state changes |
| `subscribe` | `device`, `home?` | Subscribe to live device state updates |

## Helper Process Management

The main app supervises the Catalyst helper:

- **Launch**: On app start, spawns helper as a child process
- **Health check**: Every 30 seconds, sends `status` command with 5-second timeout
- **Auto-restart**: Up to 5 restarts per 15-minute window
- **Graceful shutdown**: Sends `shutdown` command, waits 3 seconds, then SIGTERM

## Why Mac Catalyst?

Apple restricts `HMHomeManager` to apps with the HomeKit entitlement, which requires either:
- App Store distribution, or
- Development signing with a registered device UDID

Plain command-line Swift executables cannot hold this entitlement. The Catalyst helper is a
headless iOS app compiled for macOS — it has a UIKit app delegate context that satisfies
Apple's requirements without displaying any UI.

## Data Flow: Creating an Automation

1. User: "Every morning at 7am, turn on kitchen lights and set thermostat to 72"
2. LLM parses intent using SKILL.md guidance -> structured automation JSON
3. LLM calls `automation_create` MCP tool with the JSON
4. MCP server invokes `homekitauto automation create --definition '{...}'`
5. CLI sends `discover` to helper to validate devices exist
6. CLI runs full validation pipeline:
   - Device existence check (with Levenshtein fuzzy matching for near-miss suggestions)
   - Characteristic support and writability verification
   - Value range enforcement (min/max from device metadata)
   - Cron expression parsing and validation
   - Duplicate automation name check
7. CLI generates Apple Shortcut definition (`.shortcut` file)
8. CLI checks for existing Shortcut with same name before import
9. CLI registers Shortcut via `shortcuts` CLI or `open shortcuts://` URL scheme
9. CLI saves automation to `~/Library/Application Support/homekit-automator/automations.json`
10. Response flows back through MCP to LLM
11. LLM confirms to user: "Done! Your Morning Routine will run at 7 AM daily."

## Data Flow: Shortcut Execution (Unattended)

1. Apple's scheduler fires the registered Shortcut at the trigger time
2. The Shortcut contains HomeKit actions (Set Scene, Control Accessory)
3. HomeKit executes the actions directly — no involvement from this app
4. If the app is running, it receives delegate callbacks and updates its log

This is the key insight: once registered as a Shortcut, the automation is fully Apple-native.
It runs even if HomeKit Automator is quit, the Mac is asleep (if using iPhone/iPad via iCloud
sync), or the AI agent is disconnected.

## Data Flow: Automation Test with Condition Evaluation

1. User (or LLM) calls `automation_test` with an automation name/ID
2. CLI loads the automation definition from the registry
3. ConditionEvaluator checks each condition against live state:
   - Time/day-of-week conditions: evaluated locally
   - Device state conditions: queries helper for current device values
   - Solar conditions: checks current time vs. computed sunrise/sunset
4. If all conditions pass, actions are executed sequentially via the helper
5. If any condition fails, the test reports which conditions failed and skips actions
6. Results (condition outcomes + action results) flow back through MCP to the LLM

## Device State Monitoring

The HomeKitHelper process monitors device state changes in real time using
`HMHomeManager` delegate callbacks:

1. **`state_changes`** command — Returns a list of recent state changes (device, characteristic,
   old value, new value, timestamp). Useful for reviewing what happened while the agent
   was offline.
2. **`subscribe`** command — Opens a persistent socket channel for live device updates.
   The helper pushes change events as they occur. Used by `device_state` triggers to
   fire automations when a device reaches a specified value.

This architecture allows the app to react to physical device changes (e.g., someone
manually unlocking a door) without polling.

## Configuration Storage

```
~/Library/Application Support/homekit-automator/
├── homekitauto.sock         # Unix domain socket for IPC
├── .auth_token              # Shared authentication token (mode 0600)
├── config.json              # App settings (active home, filters, preferences)
├── automations.json         # Registry of created automations + Shortcut mappings
├── device-cache.json        # Last-known device map (refreshed on discover)
└── logs/
    └── automation-log.json  # History of automation executions and outcomes
```

## Structured Logging

The CLI uses [swift-log](https://github.com/apple/swift-log) for structured logging.
Log levels are controlled via the `--log-level` flag or the `LOG_LEVEL` environment variable:

| Level | Usage |
|-------|-------|
| `trace` | Socket message payloads, raw HomeKit values |
| `debug` | Validation steps, condition evaluation details |
| `info` | Command execution, automation lifecycle events (default) |
| `warning` | Recoverable errors, device unreachable, deprecated flags |
| `error` | Command failures, validation rejections |
| `critical` | Socket connection failure, helper crash |

Logs are written to stderr by default. Set `LOG_LEVEL=debug` for verbose troubleshooting.

## Security Considerations

- **HomeKit entitlement**: Only development-signed or App Store builds can access HomeKit
- **Socket permissions**: `~/Library/Application Support/homekit-automator/homekitauto.sock` is user-owned, mode 0600
- **Auth token**: Shared token at `~/Library/Application Support/homekit-automator/.auth_token`, mode 0600
- **No cloud dependency**: All communication is local — no data leaves the machine
- **iCloud sync**: HomeKit data syncs via iCloud; this app doesn't add any cloud endpoints
- **Shortcut trust**: macOS may prompt user to trust each automation Shortcut on first install
