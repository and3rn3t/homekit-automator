# HomeKit Automator

[![CI](https://github.com/homekit-automator/homekit-automator/actions/workflows/ci.yml/badge.svg)](https://github.com/homekit-automator/homekit-automator/actions/workflows/ci.yml)

A comprehensive Apple HomeKit smart home automation skill for [OpenClaw](https://openclaw.ai) and Claude. Control devices, create complex automations via natural conversation, and register them as native Apple Shortcuts so they run reliably on schedule — even when the AI agent isn't active.

## What It Does

HomeKit Automator bridges the gap between Apple's HomeKit smart home platform and AI assistants. Instead of tapping through the Home app or writing Shortcuts by hand, you describe what you want in plain English:

> "Every weekday at 6:45am, turn on the kitchen lights to a warm 60%, set the thermostat to 72, and unlock the front door. Then after 5 minutes, start the coffee maker."

The skill parses your intent, validates it against your actual devices, generates an Apple Shortcut, and registers it with macOS. Apple's native scheduler handles the rest — your automation runs even if the Mac is asleep, because Shortcuts sync to iPhone/iPad via iCloud.

## Key Features

**Device Control** — Turn lights on/off, adjust brightness and color, set thermostats, lock/unlock doors, trigger scenes, and more. Supports all standard HomeKit accessory categories: lights, thermostats, locks, doors, garage doors, fans, window coverings, switches, outlets, and sensors. Temperature values support F↔C conversion with `--units celsius|fahrenheit`.

**Automation Builder** — Create time-based, solar-based (sunrise/sunset), and manual automations through conversation. Supports conditions ("only on weekdays," "if the temperature is below 70"), delays between actions, and multi-device orchestration. Full validation pipeline catches errors before registration: device existence (with fuzzy name matching), characteristic support, writability checks, value ranges, and cron parsing.

**Apple Shortcuts Integration** — Every automation is registered as a native Apple Shortcut prefixed with `HKA:`. Includes existence checking before import to prevent duplicates. Automations survive app closure, sync across devices, and leverage Apple's proven scheduling infrastructure.

**Home Intelligence** — Analyzes your device setup and existing automations to suggest useful routines you haven't created yet, with seasonal awareness and pattern-based detection of repeated manual commands. Provides energy insights with week-over-week history and per-device usage trends.

**Multi-Home Support** — All commands accept a `--home` flag for users with multiple HomeKit homes (e.g., "Main House" and "Beach House").

**Condition Evaluation** — `automation_test` evaluates conditions against live device state before executing actions, so you can verify your automation logic works correctly.

**Full CLI** — The `homekitauto` command-line tool provides direct access to all capabilities without needing an AI agent. Useful for scripting, debugging, and manual control.

**Menu Bar App** — Native SwiftUI menu bar app with dashboard, settings, and history views for managing automations and monitoring helper process health.

**Tested & CI** — 50 Swift unit tests, 14 MCP integration tests, 24 eval cases. GitHub Actions CI/CD pipeline for automated builds and tests.

## Architecture Overview

HomeKit Automator is a three-component system:

```
Claude/OpenClaw ──MCP──> MCP Server (Node.js) ──CLI──> homekitauto (Swift)
                                                              │
                                                    Unix Socket (~/Library/Application Support/homekit-automator/)
                                                              │
                                                    HomeKitHelper (Mac Catalyst)
                                                              │
                                                    Apple HomeKit + Shortcuts
```

The separation into multiple processes exists because Apple restricts HomeKit access to apps with a specific entitlement — plain command-line tools can't access `HMHomeManager`. The Mac Catalyst helper satisfies Apple's requirements while running headlessly as a background service.

For a detailed architecture walkthrough, see [docs/architecture.md](docs/architecture.md).

## Quick Start

### Prerequisites

- macOS 14.0 (Sonoma) or later
- Xcode 16+ with Swift 6.0
- XcodeGen (`brew install xcodegen`)
- Node.js 20+
- Apple Developer account (free tier works, but you need HomeKit capability)
- At least one HomeKit-compatible device configured in Apple Home

### Build

```bash
git clone https://github.com/homekit-automator/homekit-automator.git
cd homekit-automator

# Set your Apple Developer team ID
echo "HOMEKIT_TEAM_ID=YOUR_TEAM_ID" > .env.local

# Build everything
./scripts/build.sh --release --install
```

### Configure for OpenClaw

```bash
# Install the plugin
openclaw plugins install ./scripts/openclaw-plugin
openclaw plugins enable homekit-automator
openclaw gateway restart
```

### Configure for Claude Desktop

Add to your `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "homekit-automator": {
      "command": "node",
      "args": ["/Applications/HomeKit Automator.app/Contents/Resources/mcp-server.js"]
    }
  }
}
```

For detailed setup instructions, see [docs/setup.md](docs/setup.md).

## Usage Examples

### Direct Device Control

```
You:    "Turn off the living room lights"
Agent:  Sets Living Room Lights power to false. Done.

You:    "What's the temperature in the bedroom?"
Agent:  The bedroom thermostat reads 71°F. It's currently in cooling mode, target is 70°F.

You:    "Set the thermostat to 68 and lock the front door"
Agent:  Done. Thermostat set to 68°F (was 70°F). Front door locked.
```

### Creating Automations

```
You:    "Set up a bedtime routine that turns off all lights, locks the doors,
         and sets the thermostat to 67"
Agent:  Here's what I'll set up:

        **Bedtime** (manual — say "bedtime" to run)
        1. Kitchen Lights → off
        2. Living Room Lights → off
        3. Bedroom Lights → off
        4. Front Door Lock → locked
        5. Thermostat → 67°F

        This will be registered as an Apple Shortcut. Want me to create it?

You:    "Yes, and make it run automatically at 10:30pm every night"
Agent:  Created and registered as "HKA: Bedtime". It will run nightly at 10:30 PM.
        To set up the automatic trigger, open Shortcuts → Automations →
        Create Personal Automation → Time of Day → 10:30 PM → Run Shortcut →
        select "HKA: Bedtime".
```

### Getting Suggestions

```
You:    "What automations should I set up?"
Agent:  Based on your devices, here are some suggestions:

        1. Auto-lock at Night [security]
           You have 2 smart locks but no nighttime locking automation
           Trigger: daily at 10:00 PM

        2. Motion-Activated Hallway [convenience]
           Your hallway has a motion sensor and lights but they're not connected
           Trigger: when hallway motion sensor detects motion

        Want me to set any of these up?
```

## CLI Reference

The `homekitauto` CLI provides direct terminal access to all features:

```bash
# Connection and discovery
homekitauto status                    # Check bridge connectivity
homekitauto discover                  # List all homes, rooms, devices
homekitauto discover --compact        # LLM-optimized compact output

# Device control
homekitauto get "Kitchen Lights"      # Get device state
homekitauto set "Kitchen Lights" power on           # Turn on
homekitauto set "Kitchen Lights" brightness 60      # Set brightness
homekitauto set "Thermostat" targetTemperature 72   # Set temperature
homekitauto set "Thermostat" targetTemperature 22 --units celsius  # Set in Celsius
homekitauto set "Front Door" lockState locked       # Lock door

# Rooms and scenes
homekitauto rooms                     # List all rooms
homekitauto scenes                    # List all scenes
homekitauto trigger "Good Morning"    # Trigger a scene

# Automation management
homekitauto automation list                           # List all automations
homekitauto automation create --file routine.json     # Create from file
homekitauto automation create --definition '{...}'    # Create from inline JSON
homekitauto automation test --name "Bedtime"          # Dry-run (evaluates conditions)
homekitauto automation delete --name "Bedtime"        # Delete an automation

# Intelligence
homekitauto suggest                   # Get automation suggestions
homekitauto suggest --focus security  # Focus on security suggestions
homekitauto energy                    # Energy and usage insights
homekitauto energy --period month     # Monthly energy summary
homekitauto energy --history          # Week-over-week comparison

# Multi-home
homekitauto discover --home "Beach House"   # Discover devices in specific home
homekitauto set "Porch Lights" power on --home "Beach House"

# Configuration
homekitauto config                    # Show current config
homekitauto config --default-home "Beach House"    # Switch active home
```

All commands support `--json` for machine-readable output. Use `--home "Name"` to target a specific home.

## MCP Tools

The MCP server exposes 11 tools for AI agents. See [docs/mcp-tools.md](docs/mcp-tools.md) for full specifications.

| Tool | Purpose |
|------|---------|
| `home_discover` | Discover all rooms, devices, scenes, and capabilities |
| `device_status` | Get current state of a device or room |
| `device_control` | Send an immediate control command |
| `scene_trigger` | Activate an Apple Home scene |
| `automation_create` | Create an automation and register it as a Shortcut |
| `automation_list` | List all registered automations |
| `automation_edit` | Modify an existing automation |
| `automation_delete` | Remove an automation and its Shortcut |
| `automation_test` | Dry-run an automation (evaluates conditions first) |
| `home_suggest` | Get intelligent automation suggestions (seasonal + pattern-based) |
| `energy_summary` | Device usage, automation activity, and week-over-week history |

## Project Structure

```
homekit-automator/
├── README.md                         # This file
├── CONTRIBUTING.md                   # Development and contribution guide
├── CHANGELOG.md                      # Version history
├── LICENSE                           # MIT license
│
├── docs/                             # All project documentation
│   ├── skill.md                      # OpenClaw skill definition (the AI instructions)
│   ├── setup.md                      # Detailed installation guide
│   ├── architecture.md               # System design and data flow
│   ├── mcp-tools.md                  # MCP tool specifications
│   ├── automation-schema.md          # Automation JSON schema
│   ├── shortcuts-integration.md      # Apple Shortcuts bridging
│   ├── device-categories.md          # Full HomeKit characteristic reference
│   ├── troubleshooting.md            # Common issues and solutions
│   └── xcode-notes/                  # Xcode build and project notes
│
├── evals/                            # Skill evaluation test cases
│   └── evals.json
│
├── scripts/
│   ├── build.sh                      # Build script
│   │
│   ├── swift/                        # Swift source code
│   │   ├── Package.swift             # SPM manifest
│   │   ├── Sources/
│   │   │   ├── HomeKitCore/          # Shared library (models, socket constants)
│   │   │   │   ├── Models.swift
│   │   │   │   ├── AnyCodableValue.swift
│   │   │   │   └── SocketConstants.swift
│   │   │   │
│   │   │   ├── homekitauto/          # CLI tool
│   │   │   │   ├── main.swift
│   │   │   │   ├── SocketClient.swift
│   │   │   │   ├── AnyCodableValue.swift
│   │   │   │   ├── Models.swift
│   │   │   │   ├── AutomationRegistry.swift
│   │   │   │   ├── AutomationValidator.swift
│   │   │   │   ├── ConditionEvaluator.swift
│   │   │   │   ├── ShortcutGenerator.swift
│   │   │   │   ├── HomeAnalyzer.swift
│   │   │   │   ├── Logger.swift
│   │   │   │   └── Commands/
│   │   │   │       ├── StatusCommand.swift
│   │   │   │       ├── DiscoverCommand.swift
│   │   │   │       ├── DeviceCommands.swift
│   │   │   │       ├── RoomAndSceneCommands.swift
│   │   │   │       ├── AutomationCommand.swift
│   │   │   │       └── IntelligenceCommands.swift
│   │   │   │
│   │   │   ├── HomeKitAutomator/     # SwiftUI menu bar app
│   │   │   │   ├── App/
│   │   │   │   ├── Automation/
│   │   │   │   ├── Config/
│   │   │   │   ├── HomeKit/
│   │   │   │   └── Views/
│   │   │   │
│   │   │   └── HomeKitHelper/        # Mac Catalyst helper
│   │   │       ├── project.yml       # XcodeGen specification
│   │   │       ├── Info.plist
│   │   │       ├── HomeKitHelper.entitlements
│   │   │       ├── AppDelegate.swift
│   │   │       ├── HomeKitManager.swift
│   │   │       └── HelperSocketServer.swift
│   │   │
│   │   └── Tests/
│   │       └── HomeKitAutomatorTests/
│   │           ├── AutomationRegistryTests.swift
│   │           ├── AutomationRegistryCRUDTests.swift
│   │           ├── HomeAnalyzerTests.swift
│   │           ├── ShortcutGeneratorTests.swift
│   │           └── ValidationTests.swift
│   │
│   ├── mcp-server/                   # Node.js MCP server
│   │   ├── package.json
│   │   └── index.js
│   │
│   └── openclaw-plugin/              # OpenClaw plugin manifest
│       └── plugin.json
```

## Supported Devices

HomeKit Automator supports all standard HomeKit accessory categories. See [docs/device-categories.md](docs/device-categories.md) for the full list of controllable characteristics per device type.

| Category | Key Characteristics |
|----------|-------------------|
| Lights | power, brightness, hue, saturation, color temperature |
| Thermostats | target temperature, HVAC mode, target humidity |
| Locks | lock/unlock |
| Doors & Garage | open/close, obstruction detection |
| Fans | active, rotation speed/direction, swing mode |
| Window Coverings | target position (0-100%) |
| Switches & Outlets | power on/off |
| Sensors | motion, contact, temperature, humidity, light level, battery (read-only) |

## Configuration

Configuration is stored at `~/Library/Application Support/homekit-automator/`:

| File | Purpose |
|------|---------|
| `config.json` | Active home, device filters, general preferences |
| `automations.json` | Registry of all created automations and their Shortcut mappings |
| `device-cache.json` | Cached device map, refreshed on each discovery call |
| `shortcuts/` | Generated `.shortcut` files before import |
| `logs/automation-log.json` | History of automation executions |

## Known Limitations

- **Personal Automations require manual setup**: Apple doesn't provide a programmatic API for creating Personal Automation triggers in the Shortcuts app. The skill creates the Shortcut itself, but the time/location trigger must be configured manually by the user.
- **macOS only**: HomeKit requires a Mac with iCloud sign-in. The skill cannot run on Linux or Windows.
- **Development signing**: Apple restricts HomeKit access to development-signed or App Store builds. Each Mac must be registered with your Apple Developer account.
- **Device state triggers require app running**: Schedule and manual triggers work via Apple Shortcuts (app can be closed). Device state triggers (e.g., "when the door opens") require the HomeKit Automator app to be running to monitor state changes.

## Testing

The project includes comprehensive test coverage:

- **50 Swift unit tests** — Validation pipeline, registry CRUD, shortcut generation, home analysis
- **14 MCP integration tests** — Server protocol, tool invocation, error handling
- **24 evaluation test cases** — Skill quality measurement for natural language parsing

```bash
# Run Swift tests
cd scripts/swift && swift test

# Run MCP server tests
cd scripts/mcp-server && npm test
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, coding conventions, and how to submit changes.

## License

MIT License. See [LICENSE](LICENSE) for details.

## Acknowledgments

This project was inspired by [HomeClaw](https://github.com/omarshahine/HomeClaw) and the growing ecosystem of Apple-native MCP tools. It builds on Apple's HomeKit framework, the Model Context Protocol, and the OpenClaw skill architecture.
