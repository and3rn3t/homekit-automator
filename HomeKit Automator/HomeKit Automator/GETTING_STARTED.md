# HomeKit Automator - Getting Started Guide

## 🎯 What This App Does

HomeKit Automator is a **macOS menu bar application** that helps you manage HomeKit automations through a beautiful SwiftUI interface. It works alongside a CLI tool and MCP integration to provide:

- 📱 Visual automation management
- 🔍 Search and filter automations
- 📊 Execution history and success rates
- ⚙️ Enable/disable automations
- 🔔 Status monitoring via menu bar

## 🚀 Getting Started in Xcode

### Step 1: Fix Build Errors

When you first open the project, you'll see errors about duplicate `Models.swift` files. Here's how to fix it:

1. **Delete the old `Models.swift` file:**
   - In Xcode's Project Navigator (⌘1), find `Models.swift` in the "HomeKit Automator" target
   - Right-click → **Delete** → **Move to Trash**

2. **Add the new `AutomationModels.swift` file:**
   - The file has already been created for you
   - In Xcode, right-click your project folder → **Add Files to "HomeKit Automator"**
   - Select `AutomationModels.swift`
   - ✅ Make sure "HomeKit Automator" target is checked

3. **Build the project** (⌘B):
   - The build should now succeed! 🎉

### Step 2: Update Your Info.plist (Optional)

If you want the app to run as a **menu bar-only app** (no Dock icon):

1. Open your `Info.plist`
2. Add a new entry:
   - Key: `Application is agent (UIElement)` or `LSUIElement`
   - Type: Boolean
   - Value: `YES`

This makes the app behave like a true background menu bar utility.

## 📁 Project Structure

```
HomeKit Automator/
├── App/
│   ├── HomeKitAutomatorApp.swift    # Main app entry point
│   ├── AppDelegate.swift             # Menu bar & window management
│   ├── ContentView.swift             # NEW: Main automation browser
│   ├── DashboardView.swift           # Legacy dashboard view
│   ├── HistoryView.swift             # Execution history
│   ├── SettingsView.swift            # App settings
│   ├── AutomationStore.swift         # Data management
│   ├── AutomationModels.swift        # NEW: Renamed from Models.swift
│   ├── HelperManager.swift           # HomeKit helper process manager
│   └── Item.swift                    # Template (can be deleted)
│
├── scripts/swift/Sources/
│   └── HomeKitCore/
│       └── Models.swift              # Canonical models (SPM)
│
└── Data Files (runtime):
    └── ~/Library/Application Support/homekit-automator/
        ├── automations.json
        └── logs/automation-log.json
```

## 🏗️ Architecture Overview

### Three Main Components:

1. **macOS App** (SwiftUI)
   - Menu bar interface
   - Automation browser with `ContentView`
   - Legacy dashboard with `DashboardView`
   - History viewer
   - Settings

2. **HomeKitHelper** (Companion Process)
   - Provides HomeKit framework access
   - Runs in background
   - Managed by `HelperManager`
   - Communicates via Unix domain socket

3. **CLI Tool** (`homekitauto`)
   - Create/manage automations via terminal
   - MCP server integration
   - Shares same data files with the app

### Data Flow:

```
CLI/MCP → automations.json ← AutomationStore ← ContentView
                ↓
          HomeKitHelper → HomeKit Framework
                ↓
         automation-log.json
```

## 🎨 What I've Updated

### ✅ New `ContentView.swift`

Replaced the boilerplate SwiftData template with a fully-featured automation browser:

- **Split view** with sidebar and detail pane
- **Search** functionality
- **Context menus** for quick actions
- **Success rate indicators** with color coding
- **Detailed automation view** with:
  - Trigger information
  - Conditions display
  - Action breakdown
  - Execution statistics
  - Delete functionality

### ✅ New `AutomationModels.swift`

Renamed from `Models.swift` to avoid conflicts:
- Contains all automation data structures
- Matches canonical version in Swift Package
- Ready for use in the app

### ✅ Enhanced `HomeKitAutomatorApp.swift`

Added a proper main window:
```swift
Window("HomeKit Automator", id: "main") {
    ContentView()
}
```

### ✅ Updated `AppDelegate.swift`

Added menu item to open the new main window:
- "Show Automations…" (⌘A)
- Keeps existing Dashboard, History, Settings
- Status monitoring remains unchanged

## 🎯 Next Steps

### Immediate:

1. ✅ Delete old `Models.swift`
2. ✅ Add `AutomationModels.swift` to target
3. ✅ Build and run (⌘R)

### To Explore:

1. **Run the app** - You should see the menu bar icon
2. **Click menu bar icon** → "Show Automations…"
3. **Create test data** via CLI (if available)
4. **Test the interface:**
   - Search automations
   - Right-click for context menu
   - Toggle enabled/disabled
   - View execution statistics

### To Customize:

1. **Connect real data** - `AutomationStore` already loads from disk
2. **Add creation flow** - Wire up the "Create Automation" button
3. **Enhance filters** - Add by trigger type, enabled status, etc.
4. **Add notifications** - Use `UserNotifications` for execution alerts
5. **Improve statistics** - Add charts using Swift Charts

## 🛠️ Key Files to Understand

### `AutomationStore.swift`
Observable store that manages:
- Loading/saving automations from JSON
- Execution log entries
- Success rate calculations
- CRUD operations

All mutations automatically persist to disk.

### `HelperManager.swift`
Manages the HomeKitHelper companion process:
- Launch/stop lifecycle
- Health checks via socket
- Auto-restart with rate limiting
- Status reporting

### `ContentView.swift`
Main UI for browsing automations:
- Uses `AutomationStore` for data
- Provides search and filtering
- Shows detailed automation info
- Context menus for quick actions

## 💡 Tips

1. **Data Location:** Automations are stored in:
   ```
   ~/Library/Application Support/homekit-automator/automations.json
   ```

2. **Logging:** Add print statements in `AutomationStore` to debug data loading

3. **Preview Support:** Use Xcode previews to test UI without running the full app

4. **Multiple Windows:** The app now supports:
   - Main window (`ContentView`)
   - Dashboard window (legacy)
   - History window
   - Settings window

5. **Menu Bar Icon:** Status changes based on helper health:
   - `house.fill` = Connected
   - `house` = Disconnected

## 📚 Technologies Used

- **SwiftUI** - Modern declarative UI
- **Swift Concurrency** - async/await throughout
- **Observation** - `@Observable` for state management
- **AppKit** - Menu bar integration via `NSStatusItem`
- **FileManager** - JSON persistence
- **ServiceManagement** - Login item registration

## 🐛 Troubleshooting

### Build fails with "Models.swift used twice"
→ Delete the old `Models.swift` from the app target (see Step 1 above)

### App doesn't show in menu bar
→ Check `Info.plist` has `LSUIElement = YES`

### No automations appear
→ Check if `~/Library/Application Support/homekit-automator/automations.json` exists
→ Try creating one via the CLI first

### Helper won't start
→ Check that `HomeKitHelper.app` exists in the app bundle
→ View logs in `HelperManager` for errors

## 🎉 You're Ready!

Build the project (⌘B) and run it (⌘R). You should see:
1. Menu bar icon appear
2. Click it → "Show Automations…"
3. Beautiful new interface!

Have fun exploring your HomeKit Automator! 🏠✨
