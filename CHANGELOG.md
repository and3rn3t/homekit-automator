# Changelog

All notable changes to HomeKit Automator are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-25

### Added

**Core Infrastructure**
- Two-process architecture: SwiftUI menu bar app + Mac Catalyst HomeKit helper
- Unix domain socket communication protocol (JSON newline-delimited)
- Helper process health monitoring with auto-restart (up to 5 per 15-minute window)
- Configuration persistence at `~/.config/homekit-automator/`

**Device Control**
- Full HomeKit device discovery: homes, rooms, accessories, characteristics
- Real-time device state queries with JSON output
- Device control for all standard HomeKit categories: lights, thermostats, locks, doors, garage doors, fans, window coverings, switches, outlets
- Read-only sensor support: motion, contact, temperature, humidity, light level, battery
- Fuzzy device name matching (case-insensitive substring search)
- Apple Home scene listing and triggering

**Automation Engine**
- Create automations from structured JSON definitions
- Four trigger types: schedule (cron), solar (sunrise/sunset with offset), manual (keyword), device state
- Conditional guards: time-of-day, day-of-week, device state, solar position
- Ordered action sequences with configurable delays between actions
- Scene actions within automations
- Full CRUD: create, list, edit, delete automations
- Dry-run testing: execute automation actions immediately without scheduling
- Validation against live device map (device existence, characteristic support, value ranges, writable check)

**Apple Shortcuts Integration**
- Automatic generation of `.shortcut` plist files from automation definitions
- Import via `shortcuts` CLI with fallback to file-open import
- `HKA:` prefix naming convention for all generated Shortcuts
- Shortcut deletion when automations are removed
- iCloud sync: automations work across Mac, iPhone, iPad via Shortcuts

**Home Intelligence**
- Suggestion engine: analyzes devices and existing automations to recommend new routines
- Four focus areas: security, comfort, convenience, energy
- Energy summary: current device states, automation run counts, usage insights
- Automation execution logging with history

**CLI Tool (`homekitauto`)**
- 10 subcommands: status, discover, get, set, rooms, scenes, trigger, automation, suggest, energy, config
- `--json` flag on all commands for machine-readable output
- `--compact` mode for LLM-optimized device discovery
- Built with Swift ArgumentParser for auto-generated help text

**MCP Server**
- Node.js stdio server implementing MCP protocol (2024-11-05)
- 10 tools mapped to CLI commands with full JSON Schema input definitions
- Error handling with user-friendly messages
- Zero external dependencies (Node.js built-ins only)

**OpenClaw Integration**
- `plugin.json` manifest for ClawHub publishing
- Platform requirement declarations (macOS 14+, Swift 6, Node 20+)
- Skill definition (`SKILL.md`) with comprehensive LLM guidance for natural language parsing

**Documentation**
- Complete README with architecture overview, usage examples, and CLI reference
- Detailed setup guide (SETUP.md) covering Apple Developer configuration, building, and integration
- Contributing guide (CONTRIBUTING.md) with development workflow and code conventions
- Architecture reference with data flow diagrams
- Full MCP tool specifications with parameter tables and example responses
- Automation JSON schema reference with complete examples
- Apple Shortcuts integration technical documentation
- Device category reference with all HomeKit characteristics
- Troubleshooting guide organized by symptom
- Evaluation test cases for skill quality measurement

### Known Limitations

- Personal Automation triggers in Shortcuts cannot be created programmatically (Apple API limitation)
- Device state triggers require the app to be running
- Development signing requires UDID registration for each Mac
- HomeKit access requires iCloud sign-in
