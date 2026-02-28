# Changelog

All notable changes to HomeKit Automator are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-02-25

### Added

**Validation Pipeline**

- Full validation pipeline for automation create and edit: device existence, characteristic support, writability, value ranges, cron parsing
- Levenshtein distance fuzzy matching for device names with "Did you mean?" suggestions
- Read-only characteristic detection with writable alternative suggestions
- Value range enforcement using device-reported min/max metadata
- Cron expression parser with human-readable description generation
- Duplicate automation name enforcement in the registry

**Condition Evaluation**

- Runtime condition evaluation in `automation_test` — checks time, day-of-week, device state, and solar conditions against live state before executing actions
- Detailed condition result reporting (which conditions passed/failed and why)
- Actions skipped with explanatory message when conditions are not met

**Multi-Home Support**

- `--home` flag threaded through all CLI commands and MCP tools
- Target a specific home when multiple HomeKit homes are configured
- Per-home device discovery, control, automation management, and energy insights

**Temperature Units**

- `--units celsius|fahrenheit` flag for temperature conversion
- Automatic F↔C conversion for device status reads and control writes
- System locale detection for default unit preference

**Device State Monitoring**

- `state_changes` socket command — returns recent device state changes
- `subscribe` socket command — opens persistent channel for live device updates
- Foundation for device-state-triggered automations

**Energy History**

- `--history` flag for `energy_summary` providing week-over-week comparison data
- Per-device usage deltas with trend direction and actionable insights

**Suggestion Engine Enhancements**

- Seasonal awareness — heating suggestions in winter, cooling/fan routines in summer
- Pattern-based analysis — detects repeated manual commands that could be automated

**Structured Logging**

- Integrated swift-log with configurable log levels (trace through critical)
- `LOG_LEVEL` environment variable and `--log-level` CLI flag
- Logs written to stderr to avoid interfering with JSON output

**SwiftUI Menu Bar App**

- Dashboard view with device overview and automation status
- Settings view for configuration management
- History view with automation execution log
- Helper process lifecycle management UI
- AutomationStore for reactive state management

**Testing & CI**

- 50 Swift unit tests covering validation, registry CRUD, shortcut generation, and home analysis
- 14 MCP server integration tests
- 24 evaluation test cases for skill quality measurement
- GitHub Actions CI/CD pipeline for automated builds and tests

**Distribution**

- Homebrew formula (`brew install homekit-automator/tap/homekit-automator`)
- Updated OpenClaw plugin manifest with features list and changelog

### Changed

- Renamed `--json` to `--definition` for `automation create` inline JSON input
- `automation_edit` now fully decodes and applies new actions, triggers, and conditions (not just metadata)
- `device_status` with `room` parameter now correctly routes to room-level queries
- Shortcut import now checks for existing Shortcut with same name before importing (prevents duplicates)
- Consolidated `AnyCodableJSON` into `AnyCodableValue` for consistent JSON handling

### Fixed

- Fixed automation edit not applying new actions and triggers
- Fixed `device_status` room routing returning incorrect results
- Fixed shortcut import creating duplicates when automation is recreated

## [1.0.0] - 2026-02-25

### Added

**Core Infrastructure**

- Two-process architecture: SwiftUI menu bar app + Mac Catalyst HomeKit helper
- Unix domain socket communication protocol (JSON newline-delimited)
- Helper process health monitoring with auto-restart (up to 5 per 15-minute window)
- Configuration persistence at `~/Library/Application Support/homekit-automator/`

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
- Skill definition (`docs/skill.md`) with comprehensive LLM guidance for natural language parsing

**Documentation**

- Complete README with architecture overview, usage examples, and CLI reference
- Detailed setup guide (docs/setup.md) covering Apple Developer configuration, building, and integration
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
