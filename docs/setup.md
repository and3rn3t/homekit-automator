# Setup Guide

This guide walks through every step of installing, configuring, and verifying HomeKit Automator on your Mac.

## Table of Contents

1. [System Requirements](#system-requirements)
2. [Apple Developer Setup](#apple-developer-setup)
3. [Building from Source](#building-from-source)
4. [First Launch](#first-launch)
5. [Integrating with OpenClaw](#integrating-with-openclaw)
6. [Integrating with Claude Desktop](#integrating-with-claude-desktop)
7. [Integrating with Claude Code](#integrating-with-claude-code)
8. [Verifying the Installation](#verifying-the-installation)
9. [Multi-Mac Installation](#multi-mac-installation)
10. [Updating](#updating)
11. [Uninstalling](#uninstalling)

## System Requirements

| Requirement | Minimum | Recommended |
|------------|---------|-------------|
| macOS | 14.0 (Sonoma) | 15.0+ (Sequoia) |
| Xcode | 16.0 | 16.2+ |
| Swift | 6.0 | 6.0+ |
| Node.js | 20.0 | 22 LTS |
| XcodeGen | 2.38 | Latest |
| RAM | 4 GB | 8 GB+ |
| Disk | 500 MB | 1 GB |

Additional requirements:

- **Apple Home app** configured with at least one home and one accessory
- **iCloud account** signed in (HomeKit requires iCloud for home data)
- **Apple Developer account** (free tier works; paid account needed for distribution)
- **Shortcuts app** (ships with macOS, do not delete it)

## Apple Developer Setup

HomeKit access requires a development-signed app with the `com.apple.developer.homekit` entitlement. Here's how to set that up:

### Step 1: Register for an Apple Developer Account

If you don't have one, visit [developer.apple.com](https://developer.apple.com) and create a free account. A paid Apple Developer Program membership ($99/year) is only needed if you want to distribute the app to others.

### Step 2: Find Your Team ID

1. Go to [developer.apple.com/account](https://developer.apple.com/account)
2. Look for your **Team ID** in the membership details
3. It's a 10-character alphanumeric string like `ABCDE12345`

### Step 3: Register Your Mac's UDID

Development signing requires your Mac to be registered:

```bash
# Get your Mac's Provisioning UDID
system_profiler SPHardwareDataType | grep "Provisioning UDID"
```

Then register it:

1. Go to [developer.apple.com/account/resources/devices/add](https://developer.apple.com/account/resources/devices/add)
2. Select **macOS** as the platform
3. Enter a name (e.g., "My MacBook Pro") and paste the UDID
4. Click **Continue** and then **Register**

### Step 4: Enable HomeKit Capability

1. Go to [developer.apple.com/account/resources/identifiers](https://developer.apple.com/account/resources/identifiers)
2. Find or create an App ID with bundle identifier `com.homekitautomator.helper`
3. Under **Capabilities**, check **HomeKit**
4. Save

## Building from Source

### Option A: Install via Homebrew (Recommended)

The simplest way to install the CLI tool:

```bash
brew install homekit-automator/tap/homekit-automator
```

This installs the `homekitauto` CLI to your PATH. You still need to build or download the
HomeKit Automator.app separately for the HomeKit bridge component (see Option B below).

### Option B: Clone and Build

```bash
# Clone the repository
git clone https://github.com/and3rn3t/homekit-automator.git
cd homekit-automator

# Set your team ID (from Step 2 above)
echo "HOMEKIT_TEAM_ID=ABCDE12345" > .env.local
```

### Install Build Dependencies

```bash
# Install XcodeGen (generates the Catalyst helper's Xcode project)
brew install xcodegen

# Verify Node.js is installed (for the MCP server)
node --version   # Should be >= 20.0.0

# If Node.js isn't installed:
brew install node
```

### Build

```bash
# Full release build + install to /Applications
./scripts/build.sh --release --install

# Or debug build for development (faster, no install)
./scripts/build.sh

# Clean build artifacts
./scripts/build.sh --clean
```

The build script handles three components:

1. **CLI tool** (`homekitauto`) — Built via Swift Package Manager
2. **HomeKitHelper** — Built via Xcode/xcodebuild as a Mac Catalyst app
3. **MCP server** — Node.js, no compilation needed

### Build Flags

| Flag | Effect |
|------|--------|
| `--release` | Optimized release build (vs. debug) |
| `--install` | Copy to `/Applications` and symlink CLI to PATH |
| `--clean` | Remove all build artifacts |
| `--skip-helper` | Skip the Catalyst helper build (for fast CLI iteration) |
| `--team-id XXXXX` | Override team ID (instead of `.env.local`) |

## First Launch

### Step 1: Open the App

```bash
open "/Applications/HomeKit Automator.app"
```

Or find it in `/Applications` via Finder.

### Step 2: Grant HomeKit Permission

macOS will display a dialog:

> "HomeKit Automator" wants to access your home data.

Click **Allow**. This grants the HomeKitHelper process access to your HomeKit homes, rooms, and devices.

If you accidentally click **Don't Allow**, you can fix it in System Settings → Privacy & Security → HomeKit → Toggle on HomeKit Automator.

### Step 3: Verify Connectivity

```bash
# Check that the helper is running and connected
homekitauto status

# Expected output:
# HomeKit Automator Status
# ========================
# Bridge: Connected
# Homes: 1
#   - My Home (12 accessories)
# Automations: 0
```

If you see "Could not connect to HomeKitHelper," make sure the menu bar app is running.

### Step 4: Discover Your Devices

```bash
# Full device discovery
homekitauto discover

# This lists every room, device, and characteristic in your home
```

Verify that all your HomeKit devices appear. If any are missing, check that they're:
- Powered on and connected to your network
- Added to a room in the Apple Home app
- Not filtered out (see `homekitauto config`)

## Integrating with OpenClaw

### Option 1: Local Plugin Install

```bash
# Navigate to where you cloned the project
cd homekit-automator

# Install the plugin
openclaw plugins install ./scripts/openclaw-plugin
openclaw plugins enable homekit-automator

# Symlink the CLI tool (if not already done by the build script)
ln -sf "/Applications/HomeKit Automator.app/Contents/MacOS/homekitauto" /usr/local/bin/homekitauto

# Restart the gateway so it picks up the new plugin
openclaw gateway restart
```

### Option 2: Install from ClawHub

Once published to ClawHub:

```bash
openclaw install homekit-automator
```

### Verify in OpenClaw

Start a conversation and try:

```
You: What HomeKit devices do I have?
```

The agent should use the `home_discover` tool and return your device list.

## Integrating with Claude Desktop

Add the MCP server configuration to your Claude Desktop config file.

**Config file location:** `~/Library/Application Support/Claude/claude_desktop_config.json`

Add the following entry under `mcpServers`:

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

Then restart Claude Desktop. The HomeKit tools should appear in the tools list.

## Integrating with Claude Code

```bash
# Install as a Claude Code plugin
claude plugin add /path/to/homekit-automator/scripts/openclaw-plugin

# Or reference the MCP server directly in your project's .claude.json:
# {
#   "mcpServers": {
#     "homekit-automator": {
#       "command": "node",
#       "args": ["/Applications/HomeKit Automator.app/Contents/Resources/mcp-server.js"]
#     }
#   }
# }
```

## Verifying the Installation

Run through these checks to confirm everything is working:

```bash
# 1. Helper process is running
homekitauto status
# Expected: Bridge: Connected

# 2. Device discovery works
homekitauto discover --json | head -20
# Expected: JSON with homes, rooms, accessories

# 3. Device control works (use a real device name from your home)
homekitauto get "Kitchen Lights"
# Expected: Device state with characteristics

# 4. MCP server starts without errors
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | node scripts/mcp-server/index.js 2>/dev/null | head -1
# Expected: JSON response with serverInfo

# 5. Automation registry is accessible
homekitauto automation list
# Expected: "No automations configured." (or your existing automations)
```

## Multi-Mac Installation

To install on a second Mac:

1. **Register the target Mac's UDID** (see Apple Developer Setup, Step 3)
2. **Rebuild on your development Mac** — Xcode regenerates the provisioning profile
3. **Copy the app**: `scp -r "/Applications/HomeKit Automator.app" user@othermac:/Applications/`
4. **On the target Mac**: Open the app and grant HomeKit permission
5. **On the target Mac**: The target Mac must be signed into an iCloud account that has HomeKit home data

## Updating

```bash
cd homekit-automator
git pull
./scripts/build.sh --release --install
```

The update preserves your configuration at `~/Library/Application Support/homekit-automator/` — automations, device cache, and settings are not affected by rebuilding.

## Uninstalling

```bash
# Remove the app
rm -rf "/Applications/HomeKit Automator.app"

# Remove the CLI symlink
rm -f /usr/local/bin/homekitauto

# Remove the OpenClaw plugin (if installed)
openclaw plugins disable homekit-automator
openclaw plugins remove homekit-automator

# Remove configuration (optional — only if you want a clean slate)
rm -rf ~/Library/Application\ Support/homekit-automator

# Remove the socket file (cleaned up automatically, but just in case)
rm -f ~/Library/Application\ Support/homekit-automator/homekitauto.sock
```
