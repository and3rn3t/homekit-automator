# Troubleshooting

Common issues and their solutions, organized by symptom.

## Table of Contents

1. [Connection Issues](#connection-issues)
2. [HomeKit Access Issues](#homekit-access-issues)
3. [Device Issues](#device-issues)
4. [Automation Issues](#automation-issues)
5. [Shortcut Issues](#shortcut-issues)
6. [MCP Server Issues](#mcp-server-issues)
7. [Build Issues](#build-issues)
8. [Diagnostic Commands](#diagnostic-commands)

## Connection Issues

### "Could not connect to HomeKitHelper"

**Symptom:** `homekitauto status` returns a connection error.

**Causes and fixes:**

1. **The app isn't running.** Open HomeKit Automator from `/Applications` or run:
   ```bash
   open "/Applications/HomeKit Automator.app"
   ```

2. **The socket file is stale.** If the app crashed, the socket file might still exist:
   ```bash
   rm -f /tmp/homekitauto.sock
   # Then relaunch the app
   ```

3. **Permission denied on socket.** The socket should be owned by your user with mode 0600:
   ```bash
   ls -la /tmp/homekitauto.sock
   # Should show: srw------- 1 yourusername ...
   ```

4. **Helper process crashed.** Check the menu bar icon — if it shows "Helper Down," the Catalyst process crashed. The app auto-restarts it up to 5 times per 15-minute window. If it keeps crashing, check logs:
   ```bash
   log show --predicate 'process == "HomeKitHelper"' --last 10m --style compact
   ```

### Connection Timeout

**Symptom:** Commands hang for 10 seconds then fail.

**Fix:** The HomeKitHelper may be stuck waiting for HomeKit to initialize. This usually happens when iCloud sync is slow. Restart the app and wait 30 seconds for HomeKit to load home data. You can monitor readiness:

```bash
# Test the socket directly
echo '{"id":"test","command":"status"}' | nc -U /tmp/homekitauto.sock
```

## HomeKit Access Issues

### "HomeKit is not available"

**Symptom:** `homekitauto status` connects but reports HomeKit unavailable.

**Causes:**

1. **Not signed into iCloud.** HomeKit requires iCloud. Go to System Settings → Apple ID and sign in.

2. **No Home configured.** Open the Apple Home app and create a home if you haven't already.

3. **HomeKit permission denied.** Check System Settings → Privacy & Security → HomeKit. HomeKit Automator (or HomeKitHelper) must be toggled on.

4. **Entitlement issue.** The helper app may not be properly signed:
   ```bash
   codesign -d --entitlements - "/Applications/HomeKit Automator.app/Contents/Helpers/HomeKitHelper.app"
   # Should include com.apple.developer.homekit = true
   ```

### "No homes found"

**Symptom:** `homekitauto discover` returns an empty home list.

**Causes:**

1. **iCloud sync hasn't completed.** Wait a minute and try again. HomeKit data is loaded asynchronously from iCloud.

2. **Wrong iCloud account.** The helper accesses homes from the currently signed-in iCloud account. If your devices are on a different account (e.g., a family member's), you need to be invited to that home in the Home app.

3. **Home sharing issue.** Go to the Home app → Home Settings → People and verify your access.

## Device Issues

### Device Not Found

**Symptom:** `homekitauto get "Device Name"` returns "Device not found."

**Fixes:**

1. **Check the exact name.** Device names are case-sensitive. Run `homekitauto discover` to see the exact names.

2. **Fuzzy matching.** The tool attempts a fuzzy match (substring, case-insensitive) but it's not perfect. Try using the device UUID instead:
   ```bash
   homekitauto discover --json | grep -A2 "your device"
   # Find the uuid field and use that
   homekitauto get "UUID-HERE"
   ```

3. **Device is filtered out.** Check your filter settings:
   ```bash
   homekitauto config
   # If filterMode is "allowlist", the device might not be in the allowed list
   homekitauto config --filter-mode all
   ```

### Device Not Responding

**Symptom:** Command returns "Device not reachable."

**Causes:**

1. The physical device is powered off or disconnected from the network
2. The HomeKit hub (HomePod, Apple TV) is offline
3. The device's Bluetooth/Wi-Fi connection has dropped

**Fix:** Check the device in the Apple Home app. If it shows "No Response" there too, the issue is with the device itself, not HomeKit Automator.

### Characteristic Not Supported

**Symptom:** `homekitauto set "Device" brightness 50` returns "doesn't have a 'brightness' characteristic."

**Fix:** Not all devices support all characteristics. A basic on/off switch doesn't have brightness. Check what the device supports:

```bash
homekitauto get "Device Name" --json
# Look at the "state" object to see available characteristics
```

## Automation Issues

### Automation Created but Not Running

**Symptom:** `automation create` succeeds but the automation doesn't fire at the scheduled time.

**This is expected behavior.** HomeKit Automator creates the Shortcut, but you need to manually create a Personal Automation in the Shortcuts app to trigger it on schedule. See [shortcuts-integration.md](shortcuts-integration.md) for the steps.

### Automation Actions Partially Fail

**Symptom:** `automation test` shows some actions succeeded and some failed.

**Causes:**

1. **Unreachable devices.** One or more target devices may be offline. The test continues through all actions even if some fail.

2. **Value out of range.** A brightness value above 100 or temperature outside the device's supported range will fail. Check the device's min/max values:
   ```bash
   homekitauto get "Device" --json
   # Look for "min" and "max" in the characteristics
   ```

3. **Read-only characteristic.** Trying to set `currentTemperature` (read-only) instead of `targetTemperature` (writable).

### Duplicate Automation Names

**Symptom:** "An automation named 'X' already exists."

**Fix:** Automation names must be unique because they map 1:1 to Shortcut names. Either choose a different name or delete the existing automation first:

```bash
homekitauto automation delete --name "Morning Routine"
```

## Shortcut Issues

### Shortcut Import Fails

**Symptom:** "I couldn't register the automation as a Shortcut."

**Causes:**

1. **Shortcuts CLI not available.** Verify:
   ```bash
   which shortcuts
   # Should be /usr/bin/shortcuts
   ```

2. **Privacy restriction.** macOS may block Shortcut imports from untrusted sources. Open Shortcuts.app manually and try importing the generated file:
   ```bash
   open ~/.config/homekit-automator/shortcuts/
   # Double-click the .shortcut file to import it
   ```

3. **Shortcuts app not installed.** While it ships with macOS, it can be deleted. Reinstall from the App Store.

### Shortcut Exists but Not in Shortcuts App

**Symptom:** `automation list` shows the automation with a Shortcut name, but the Shortcut doesn't appear in Shortcuts.app.

**Fix:** The Shortcut may have been deleted manually from the Shortcuts app. Re-register it:

```bash
# Delete and recreate the automation
homekitauto automation delete --name "Routine Name"
# Then recreate it through the AI agent or CLI
```

### Shortcut Runs but Doesn't Control Devices

**Symptom:** The Shortcut triggers on schedule but devices don't respond.

**Causes:**

1. **HomeKit hub offline.** Scheduled Shortcuts use the HomeKit hub (HomePod/Apple TV) for execution. If the hub is offline, device commands fail silently.

2. **Device UUIDs changed.** If you removed and re-added a device, its UUID changed. The Shortcut still references the old UUID. Delete and recreate the automation.

## MCP Server Issues

### "CLI error: command not found"

**Symptom:** The MCP server can't find the `homekitauto` CLI.

**Fix:** The CLI must be in the system PATH:

```bash
# Check if it's accessible
which homekitauto

# If not, create the symlink
sudo ln -sf "/Applications/HomeKit Automator.app/Contents/MacOS/homekitauto" /usr/local/bin/homekitauto
```

### MCP Server Won't Start

**Symptom:** Claude Desktop or OpenClaw shows the MCP server as disconnected.

**Diagnostic:**

```bash
# Test the server manually
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | node /Applications/HomeKit\ Automator.app/Contents/Resources/mcp-server.js

# Check stderr for errors (the server logs to stderr)
```

**Common causes:**

1. **Wrong Node.js version.** The server requires Node.js 20+. Check with `node --version`.
2. **Wrong path in config.** Verify the path in your `claude_desktop_config.json` points to the correct `mcp-server.js` file.

## Build Issues

### "XcodeGen not found"

```bash
brew install xcodegen
```

### "No signing identity found"

The build can't find your Apple Developer certificate. Make sure:

1. You're signed into Xcode with your Apple ID (Xcode → Settings → Accounts)
2. Your team ID is set correctly in `.env.local`
3. Your Mac's UDID is registered with your developer account

### "HomeKit entitlement not found"

The Catalyst helper requires the HomeKit entitlement in its code signature. This is configured in `HomeKitHelper.entitlements`. If the build strips it:

1. Open the generated Xcode project: `open scripts/swift/Sources/HomeKitHelper/HomeKitHelper.xcodeproj`
2. Select the target → Signing & Capabilities → Add "HomeKit"
3. Rebuild

## Diagnostic Commands

Use these commands to gather information when troubleshooting:

```bash
# Full system status
homekitauto status --json

# Device discovery with full detail
homekitauto discover --json > /tmp/device-map.json

# Helper process logs (last 10 minutes)
log show --predicate 'process == "HomeKitHelper"' --last 10m --style compact

# Socket connectivity test
echo '{"id":"test","command":"status"}' | nc -U /tmp/homekitauto.sock

# Entitlement verification
codesign -d --entitlements - "/Applications/HomeKit Automator.app/Contents/Helpers/HomeKitHelper.app"

# HomeKit privacy permissions (TCC database)
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT client, auth_value FROM access WHERE service = 'kTCCServiceWillow'"

# List registered Shortcuts (look for HKA: prefix)
shortcuts list | grep "^HKA:"

# Automation registry contents
cat ~/.config/homekit-automator/automations.json

# Config contents
cat ~/.config/homekit-automator/config.json
```
