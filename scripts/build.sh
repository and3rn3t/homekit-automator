#!/usr/bin/env bash
# build.sh — Build HomeKit Automator from source
#
# This script orchestrates a three-phase build process:
#   1. CLI tool (Swift Package Manager) — The `homekitauto` binary
#   2. HomeKitHelper (Xcode / Mac Catalyst) — The HomeKit bridge app
#   3. MCP server (Node.js) — The AI agent integration layer
#
# The build produces three artifacts that work together:
#   homekitauto CLI  ←→  HomeKitHelper.app  (via Unix socket)
#   MCP server       ←→  homekitauto CLI    (via child_process)
#
# Usage:
#   ./scripts/build.sh                    # Debug build (CLI + Helper + MCP)
#   ./scripts/build.sh --release          # Optimized release build
#   ./scripts/build.sh --release --install  # Build + install to /Applications
#   ./scripts/build.sh --clean            # Remove all build artifacts
#   ./scripts/build.sh --skip-helper      # Build CLI + MCP only (no Xcode needed)
#   ./scripts/build.sh --team-id ABC123   # Override Apple Developer Team ID
#
# Prerequisites:
#   - macOS 14.0+ (Sonoma or later)
#   - Xcode 16+ with Swift 6.0 toolchain
#   - XcodeGen: brew install xcodegen (only needed for Helper)
#   - Node.js 20+ (only needed for MCP server)
#   - Apple Developer account with HomeKit capability enabled
#
# Configuration:
#   Set your Apple Developer Team ID via .env.local:
#     echo "HOMEKIT_TEAM_ID=YOUR_TEAM_ID" > .env.local
#   Or pass it directly: ./scripts/build.sh --team-id YOUR_TEAM_ID

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SWIFT_DIR="$SCRIPT_DIR/swift"
MCP_DIR="$SCRIPT_DIR/mcp-server"
BUILD_CONFIG="debug"
SHOULD_INSTALL=false
SHOULD_CLEAN=false
SKIP_HELPER=false
TEAM_ID=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --release) BUILD_CONFIG="release"; shift ;;
        --install) SHOULD_INSTALL=true; shift ;;
        --clean) SHOULD_CLEAN=true; shift ;;
        --skip-helper) SKIP_HELPER=true; shift ;;
        --team-id) TEAM_ID="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Load team ID from .env.local if not provided
if [[ -z "$TEAM_ID" && -f "$PROJECT_DIR/.env.local" ]]; then
    TEAM_ID=$(grep HOMEKIT_TEAM_ID "$PROJECT_DIR/.env.local" | cut -d= -f2)
fi

# Clean
if $SHOULD_CLEAN; then
    echo "==> Cleaning build artifacts..."
    rm -rf "$SWIFT_DIR/.build"
    rm -rf "$SWIFT_DIR/Sources/HomeKitHelper/HomeKitHelper.xcodeproj"
    echo "    Done."
    exit 0
fi

echo "==> HomeKit Automator Build"
echo "    Configuration: $BUILD_CONFIG"
echo "    Team ID: ${TEAM_ID:-not set}"
echo ""

# Step 1: Build the CLI tool via Swift Package Manager
echo "==> Building homekitauto CLI..."
cd "$SWIFT_DIR"
if [[ "$BUILD_CONFIG" == "release" ]]; then
    swift build -c release
    CLI_PATH="$SWIFT_DIR/.build/release/homekitauto"
else
    swift build
    CLI_PATH="$SWIFT_DIR/.build/debug/homekitauto"
fi
echo "    CLI built: $CLI_PATH"

# Step 2: Build the HomeKitHelper (Catalyst app) via Xcode
if ! $SKIP_HELPER; then
    echo "==> Building HomeKitHelper..."

    HELPER_DIR="$SWIFT_DIR/Sources/HomeKitHelper"
    cd "$HELPER_DIR"

    # Generate Xcode project
    if ! command -v xcodegen &>/dev/null; then
        echo "    ERROR: xcodegen not found. Install with: brew install xcodegen"
        exit 1
    fi

    # Set team ID in environment for XcodeGen
    export HOMEKIT_TEAM_ID="${TEAM_ID}"
    xcodegen generate --quiet

    # Build with xcodebuild
    DERIVED_DATA="$SWIFT_DIR/.build/DerivedData"
    xcodebuild \
        -project HomeKitHelper.xcodeproj \
        -scheme HomeKitHelper \
        -configuration "$(echo "$BUILD_CONFIG" | sed 's/release/Release/;s/debug/Debug/')" \
        -destination "platform=macOS,variant=Mac Catalyst" \
        -derivedDataPath "$DERIVED_DATA" \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        CODE_SIGN_IDENTITY="Apple Development" \
        -quiet

    HELPER_APP=$(find "$DERIVED_DATA" -name "HomeKitHelper.app" -type d | head -1)
    echo "    Helper built: $HELPER_APP"
else
    echo "==> Skipping HomeKitHelper build (--skip-helper)"
fi

# Step 3: Install MCP server dependencies
echo "==> Setting up MCP server..."
cd "$MCP_DIR"
if [[ -f "package.json" ]]; then
    # No dependencies currently, but future-proof
    npm install --production --silent 2>/dev/null || true
fi
echo "    MCP server ready: $MCP_DIR/index.js"

# Step 4: Install (optional)
if $SHOULD_INSTALL; then
    echo "==> Installing..."

    APP_DIR="/Applications/HomeKit Automator.app"
    APP_CONTENTS="$APP_DIR/Contents"

    # Create app bundle structure
    mkdir -p "$APP_CONTENTS/MacOS"
    mkdir -p "$APP_CONTENTS/Helpers"
    mkdir -p "$APP_CONTENTS/Resources"

    # Copy CLI
    cp "$CLI_PATH" "$APP_CONTENTS/MacOS/homekitauto"

    # Copy Helper
    if ! $SKIP_HELPER && [[ -n "${HELPER_APP:-}" ]]; then
        cp -R "$HELPER_APP" "$APP_CONTENTS/Helpers/"
    fi

    # Copy MCP server
    cp "$MCP_DIR/index.js" "$APP_CONTENTS/Resources/mcp-server.js"
    cp "$MCP_DIR/package.json" "$APP_CONTENTS/Resources/"

    # Symlink CLI to PATH
    ln -sf "$APP_CONTENTS/MacOS/homekitauto" /usr/local/bin/homekitauto 2>/dev/null || \
        echo "    NOTE: Could not symlink to /usr/local/bin. Run: sudo ln -sf '$APP_CONTENTS/MacOS/homekitauto' /usr/local/bin/homekitauto"

    echo "    Installed to: $APP_DIR"
    echo ""
    echo "==> Next steps:"
    echo "    1. Launch HomeKit Automator from /Applications"
    echo "    2. Grant HomeKit access when prompted"
    echo "    3. Configure your Claude Desktop or OpenClaw integration"
else
    echo ""
    echo "==> Build complete."
    echo "    CLI: $CLI_PATH"
    echo "    MCP: $MCP_DIR/index.js"
    echo ""
    echo "    To install: ./scripts/build.sh --release --install"
fi
