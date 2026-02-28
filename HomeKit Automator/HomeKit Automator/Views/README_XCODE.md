# HomeKit Automator - macOS App

A native macOS menu bar application for managing HomeKit automations with natural language processing.

## Overview

HomeKit Automator is a menu bar app that provides a beautiful SwiftUI interface for creating, managing, and monitoring HomeKit automations. It works alongside the HomeKitHelper companion process to provide full HomeKit framework access.

## Architecture

### Components

#### 1. **Main App (HomeKit Automator.app)**
- **ContentView.swift** - Primary automations list and detail view with NavigationSplitView
- **CreateAutomationView.swift** - Sheet for creating new automations with natural language input
- **DashboardView.swift** - Legacy dashboard view with quick automation management
- **HistoryView.swift** - Complete execution history with filtering and search
- **SettingsView.swift** - App preferences (General and Advanced tabs)

#### 2. **Menu Bar Integration**
- **AppDelegate.swift** - NSStatusItem management, health checks, window lifecycle
- **HomeKitAutomatorApp.swift** - SwiftUI App entry point with window configuration

#### 3. **Data Layer**
- **AutomationStore.swift** - Observable store for automations and logs (reads from disk)
- **AutomationModels.swift** - Shared data models (RegisteredAutomation, AutomationAction, etc.)
- **AppSettings.swift** - UserDefaults-backed settings with @AppStorage support

#### 4. **Communication**
- **HelperManager.swift** - Manages HomeKitHelper process lifecycle and health checks
- **HelperAPIClient.swift** - Socket-based API client for sending commands to HomeKitHelper
- **SocketConstants.swift** - Shared socket configuration and token management

#### 5. **UI Components**
- **AutomationRowView.swift** - Compact row view for sidebar list
- **AutomationListItem.swift** - Detailed row view for dashboard with controls
- **LogEntryRow.swift** - Timeline entry for execution history

## Features

### ✅ Implemented

- **Menu Bar Integration**
  - Status icon with connection state indicator
  - Quick access to all windows and functions
  - Health check timer with automatic helper restart
  - Launch at login support via SMAppService

- **Automations Management**
  - List view with search and filtering
  - Three-column NavigationSplitView (sidebar → detail → ?)
  - Enable/disable toggle per automation
  - Delete automations with confirmation
  - Manual trigger ("Run Now" button)
  - Success rate tracking

- **Execution History**
  - Filterable timeline of all automation runs
  - Date range filtering
  - Status filtering (All, Success, Failed)
  - Search by automation name
  - Success rate summary bar

- **Settings**
  - General: Default home, temperature units, launch at login
  - Advanced: Socket path, log retention, max helper restarts

- **Data Persistence**
  - Reads/writes to same JSON files as CLI tool
  - Location: `~/Library/Application Support/homekit-automator/`
  - Atomic writes to prevent data corruption

### 🚧 Requires Additional Implementation

- **Natural Language Automation Creation**
  - UI is complete (CreateAutomationView)
  - Needs LLM service integration (OpenAI, Claude, etc.)
  - Currently shows placeholder message directing users to CLI

- **Real-time Updates**
  - Currently requires manual refresh
  - Could add FileSystemWatcher or NSFileCoordinator
  - Could use Distributed actors for IPC with helper

- **Notifications**
  - Automation execution notifications
  - Error alerts
  - Helper connection status changes

## File Structure

```
HomeKit Automator/
├── HomeKitAutomatorApp.swift          # App entry point
├── AppDelegate.swift                   # Menu bar and app lifecycle
├── ContentView.swift                   # Main window with automations list
├── CreateAutomationView.swift          # Automation creation sheet
├── DashboardView.swift                 # Legacy dashboard window
├── HistoryView.swift                   # Execution history window
├── SettingsView.swift                  # Settings window (General + Advanced)
│
├── Models/
│   ├── AutomationModels.swift         # Shared data models
│   └── AppSettings.swift              # Settings keys and defaults
│
├── Services/
│   ├── HelperManager.swift            # Helper process management
│   ├── HelperAPIClient.swift          # Socket API client
│   ├── SocketConstants.swift          # Socket configuration
│   └── AutomationStore.swift          # Data persistence layer
│
├── Components/
│   ├── AutomationRowView.swift        # Sidebar list row
│   ├── AutomationListItem.swift       # Dashboard list item
│   └── LogEntryRow.swift              # History timeline entry
│
└── Info.plist                          # App configuration (LSUIElement = YES)
```

## Data Flow

1. **App Launch**
   - AppDelegate sets up menu bar status item
   - Health check timer starts (30s interval)
   - HelperManager launches HomeKitHelper process
   - AutomationStore loads from disk

2. **Viewing Automations**
   - ContentView displays automations from AutomationStore
   - Store reads from `~/Library/Application Support/homekit-automator/automations.json`
   - Changes update immediately via @Observable

3. **Creating Automations**
   - User describes automation in natural language (CreateAutomationView)
   - LLM service parses to AutomationDefinition (TODO: implement)
   - HelperAPIClient sends via Unix socket to HomeKitHelper
   - Helper validates against HomeKit devices
   - Helper registers automation and saves to disk
   - App reloads from disk

4. **Managing Automations**
   - Enable/disable: Updates JSON and calls helper API
   - Delete: Removes from JSON and helper registry
   - Trigger: Sends command to helper via socket

5. **Execution History**
   - Helper writes to `logs/automation-log.json` after each run
   - HistoryView loads and filters log entries
   - Real-time updates require manual refresh

## Requirements

- macOS 13.0+ (for SMAppService, NavigationSplitView)
- Swift 5.9+
- Xcode 15.0+

## Building

1. Open `HomeKit Automator.xcodeproj` in Xcode
2. Select the "HomeKit Automator" scheme
3. Build and run (⌘R)

The app will appear in the menu bar with a house icon.

## Configuration

All settings are stored in `UserDefaults` with keys defined in `AppSettings.swift`.

Default locations:
- **Socket**: `~/Library/Application Support/homekit-automator/homekitauto.sock`
- **Automations**: `~/Library/Application Support/homekit-automator/automations.json`
- **Logs**: `~/Library/Application Support/homekit-automator/logs/automation-log.json`

## Known Issues

1. **LLM Integration**: The "Create Automation" flow requires LLM service integration
2. **Manual Refresh**: Changes from CLI require manual refresh in GUI
3. **No Notifications**: App doesn't show system notifications for events
4. **Helper Location**: App expects HomeKitHelper.app adjacent to main app bundle

## Future Enhancements

- [ ] Implement LLM service for natural language parsing
- [ ] Add file system monitoring for automatic refresh
- [ ] Push notifications for automation events
- [ ] Widgets for quick automation triggers
- [ ] Siri Shortcuts integration
- [ ] Export/import automations as JSON
- [ ] Automation templates library
- [ ] Visual automation builder (no-code)
- [ ] Device health monitoring
- [ ] Analytics dashboard
- [ ] Dark mode optimizations
- [ ] Menu bar quick actions

## License

Copyright © 2026. All rights reserved.
