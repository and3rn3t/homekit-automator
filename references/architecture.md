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
                    └──────────────┬──────────────┘
                                   │ Unix socket
                    ┌──────────────▼──────────────┐
                    │  HomeKit Automator.app        │
                    │                               │
                    │  ┌─────────────────────────┐ │
                    │  │  SwiftUI Menu Bar App    │ │
                    │  │  - Settings UI           │ │
                    │  │  - Helper lifecycle      │ │
                    │  │  - Automation registry    │ │
                    │  └────────────┬────────────┘ │
                    │               │ process mgmt  │
                    │  ┌────────────▼────────────┐ │
                    │  │  HomeKitHelper           │ │
                    │  │  (Mac Catalyst)          │ │
                    │  │  - HMHomeManager         │ │
                    │  │  - Socket server         │ │
                    │  │  - Device state cache    │ │
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

Location: `/tmp/homekitauto.sock`
Format: JSON messages delimited by newline (`\n`)

**Request format:**
```json
{
  "id": "uuid-string",
  "command": "command_name",
  "params": { ... }
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
| `discover` | none | Full device map: homes, rooms, accessories, characteristics |
| `get_device` | `name` or `uuid` | Device state with all characteristics |
| `set_device` | `uuid`, `characteristic`, `value` | Confirmation |
| `list_rooms` | `home?` | Rooms with accessory summaries |
| `list_scenes` | `home?` | Available scenes |
| `trigger_scene` | `name` or `uuid` | Confirmation |
| `get_config` | none | Current configuration |
| `set_config` | key-value pairs | Updated configuration |

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
4. MCP server invokes `homekitauto automation create --json '{...}'`
5. CLI sends `discover` to helper to validate devices exist
6. CLI validates all referenced devices and characteristics
7. CLI generates Apple Shortcut definition (`.shortcut` file)
8. CLI registers Shortcut via `shortcuts` CLI or `open shortcuts://` URL scheme
9. CLI saves automation to `~/.config/homekit-automator/automations.json`
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

## Configuration Storage

```
~/.config/homekit-automator/
├── config.json              # App settings (active home, filters, preferences)
├── automations.json         # Registry of created automations + Shortcut mappings
├── device-cache.json        # Last-known device map (refreshed on discover)
└── logs/
    └── automation-log.json  # History of automation executions and outcomes
```

## Security Considerations

- **HomeKit entitlement**: Only development-signed or App Store builds can access HomeKit
- **Socket permissions**: `/tmp/homekitauto.sock` is user-owned, mode 0600
- **No cloud dependency**: All communication is local — no data leaves the machine
- **iCloud sync**: HomeKit data syncs via iCloud; this app doesn't add any cloud endpoints
- **Shortcut trust**: macOS may prompt user to trust each automation Shortcut on first install
