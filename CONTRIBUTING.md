# Contributing to HomeKit Automator

Thank you for your interest in contributing! This guide covers everything you need to get started developing, testing, and submitting changes.

## Development Environment Setup

### Prerequisites

Follow the [docs/setup.md](docs/setup.md) guide through the "Building from Source" section. In addition, for development you'll want:

- Xcode (for the Catalyst helper and debugging)
- A HomeKit-compatible device (or the HomeKit Accessory Simulator from Xcode's developer tools)
- `swiftlint` (optional but recommended): `brew install swiftlint`

### Project Layout

The codebase is organized into three main components:

| Component | Location | Language | Build Tool |
|-----------|----------|----------|------------|
| CLI (`homekitauto`) | `scripts/swift/Sources/homekitauto/` | Swift 6.0 | SPM |
| Shared Models (`HomeKitCore`) | `scripts/swift/Sources/HomeKitCore/` | Swift 6.0 | SPM |
| HomeKit Helper | `scripts/swift/Sources/HomeKitHelper/` | Swift 6.0 | XcodeGen + xcodebuild |
| SwiftUI Menu Bar App | `scripts/swift/Sources/HomeKitAutomator/` | Swift 6.0 | XcodeGen + xcodebuild |
| MCP Server | `scripts/mcp-server/` | JavaScript (ES modules) | Node.js |
| Skill Definition | `docs/skill.md` + `docs/` | Markdown | N/A |
| Plugin Manifest | `scripts/openclaw-plugin/` | JSON | N/A |

### Fast Development Loop

For CLI development, you can skip rebuilding the Catalyst helper:

```bash
# Build just the CLI (fast — a few seconds)
cd scripts/swift
swift build

# Run directly from the build folder
.build/debug/homekitauto status

# Or use the build script with --skip-helper
./scripts/build.sh --skip-helper
```

For MCP server development, no build step is needed — just edit `scripts/mcp-server/index.js` and restart.

For Catalyst helper changes, you'll need a full build:

```bash
./scripts/build.sh --release --install
```

### SwiftUI Menu Bar App (HomeKitAutomator)

The `HomeKitAutomator` target is a SwiftUI menu bar app that provides:

- A dashboard view of automation status
- History and execution log
- Settings UI for configuration
- Lifecycle management for the HomeKitHelper process

It lives under `scripts/swift/Sources/HomeKitAutomator/` and is built via XcodeGen + xcodebuild (not SPM).
Because the Xcode target cannot import SPM modules directly, the `App/Models.swift` file is a
manual copy of `HomeKitCore/Models.swift` + `HomeKitCore/AnyCodableValue.swift`. After changing
any model types in `HomeKitCore`, run the sync script to keep the copy in sync:

```bash
./scripts/sync-models.sh
```

The app communicates with the HomeKitHelper via the same Unix domain socket that the CLI uses.
The socket client logic is in `HomeKit/HelperManager.swift`.

### Using the HomeKit Accessory Simulator

If you don't have physical HomeKit devices for testing, use Apple's simulator:

1. Open Xcode → Window → Devices and Simulators
2. Install the HomeKit Accessory Simulator (or download from [Additional Tools for Xcode](https://developer.apple.com/download/all/?q=additional%20tools))
3. Create virtual accessories (lights, thermostats, locks, etc.)
4. Add them to your Home in the Apple Home app

These virtual devices behave identically to real ones for development purposes.

## Code Style and Conventions

### Swift

- **Swift 6.0** with strict concurrency checking
- **`@MainActor`** for all HomeKit API access (required by Apple's framework)
- **`actor`** isolation for the socket client (thread-safe by design)
- **`async/await`** everywhere — no completion handler callbacks
- **`Codable`** for all data models that cross process or serialization boundaries
- Prefer `struct` over `class` unless reference semantics are needed
- Use `MARK:` comments to organize sections within files
- Document all public APIs with `///` doc comments

### JavaScript (MCP Server)

- **ES modules** (`import`/`export`, not `require`)
- **No external dependencies** — the MCP server uses only Node.js built-ins
- Use `const` by default, `let` when reassignment is needed, never `var`

### Markdown (Documentation)

- One sentence per line (makes diffs cleaner)
- Use ATX-style headers (`#` not underlines)
- Code blocks always specify a language (` ```swift `, ` ```bash `, etc.)

## Adding a New MCP Tool

To add a new tool to the MCP server:

### Step 1: Define the Tool Schema

Add the tool definition to the `TOOLS` array in `scripts/mcp-server/index.js`:

```javascript
{
  name: "your_tool_name",
  description: "What it does and when to use it",
  inputSchema: {
    type: "object",
    properties: {
      param1: { type: "string", description: "..." },
    },
    required: ["param1"],
  },
},
```

### Step 2: Add the CLI Command

Create a new `ParsableCommand` in `scripts/swift/Sources/homekitauto/Commands/`:

```swift
struct YourCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "yourcommand",
        abstract: "What it does."
    )

    @Argument(help: "Description")
    var param1: String

    @Flag(name: .long, help: "Output as JSON")
    var json = false

    func run() async throws {
        // Implementation
    }
}
```

Register it in `main.swift`'s subcommands array.

### Step 3: Add the Handler

Add a case to the `handleTool` switch in `index.js`:

```javascript
case "your_tool_name":
  return await runCli(["yourcommand", args.param1]);
```

### Step 4: Document It

1. Add the tool to `docs/mcp-tools.md` with full parameter and return documentation
2. Update the tool table in `README.md`
3. Add guidance for when to use it in `docs/skill.md` under "When to Use Each Tool"

### Step 5: Add a Test Case

Add an eval to `evals/evals.json` that exercises the new tool.

## Adding a New Device Category

If Apple adds new HomeKit accessory types, or if existing mappings need updating:

### Step 1: Update the Characteristic Map

In `HomeKitManager.swift`, add entries to both:

- `characteristicTypeName(_:)` — maps Apple's UUID constant to a friendly name
- `characteristicUUID(for:)` — maps the friendly name back to Apple's UUID

### Step 2: Update the Category Map

In `HomeKitManager.swift`, add the new category to `categoryName(_:)`.

### Step 3: Update the Reference Documentation

Add the new category and its characteristics to `docs/device-categories.md`.

### Step 4: Update the Suggestion Engine

If the new device type can participate in automation suggestions, add logic to `HomeAnalyzer.swift`'s `generateSuggestions()` method.

## Testing

### Unit Tests

```bash
cd scripts/swift
swift test
```

The test suite covers:

- Model encoding/decoding roundtrips
- `AnyCodableValue` type handling
- Trigger type construction
- Automation definition parsing

### Integration Testing

Integration tests require a running HomeKitHelper with actual (or simulated) devices:

```bash
# Verify the full stack end-to-end
homekitauto status          # Helper connection
homekitauto discover        # Device enumeration
homekitauto get "Device"    # State read
homekitauto set "Device" power on  # State write
```

### MCP Server Testing

```bash
# Send a test initialize message
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | node scripts/mcp-server/index.js 2>/dev/null

# List tools
echo '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' | node scripts/mcp-server/index.js 2>/dev/null
```

## Submitting Changes

### Before Submitting

1. Run `swift build` and verify no compiler warnings
2. Run `swift test` and verify all tests pass
3. If you changed `docs/skill.md` or MCP tools, test with an actual AI agent conversation
4. Update relevant documentation (README, docs/, CHANGELOG)

### Pull Request Process

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Make your changes with clear, descriptive commits
4. Push to your fork and open a pull request
5. Describe what changed, why, and how to test it

### Commit Message Format

Use conventional commits:

```
feat(automation): add sunrise/sunset offset support
fix(socket): handle connection timeout gracefully
docs(readme): add troubleshooting section
test(registry): add roundtrip encoding tests
```

## Reporting Issues

When reporting a bug, please include:

1. macOS version and hardware (Intel or Apple Silicon)
2. Output of `homekitauto status --json`
3. The error message or unexpected behavior
4. Steps to reproduce
5. Helper logs: `log show --predicate 'process == "HomeKitHelper"' --last 10m --style compact`
