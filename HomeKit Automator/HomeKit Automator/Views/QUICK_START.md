# Quick Start Guide - HomeKit Automator

## 🚀 Getting Started in 5 Minutes

### Step 1: Open the Project
```bash
cd HomeKit\ Automator
open "HomeKit Automator.xcodeproj"
```

### Step 2: Build and Run
1. Select the **"HomeKit Automator"** scheme
2. Press **⌘R** to build and run
3. The app will appear in your menu bar (house icon)

### Step 3: Verify Connection
- Click the menu bar icon
- Status should show "Connected" (green house icon)
- If not, check that HomeKitHelper.app is present

---

## 🎯 Using the App

### View Automations
1. Click menu bar icon → **"Show Automations…"** (or press **⌘A**)
2. Browse the sidebar list
3. Click an automation to see details

### Create an Automation
**Option 1: Using GUI** (requires LLM integration)
1. Click the **+** button in toolbar
2. Describe your automation in natural language
3. Currently shows implementation note

**Option 2: Using CLI** (works now)
```bash
homekitauto automation create --interactive
```

### Manage Automations
- **Enable/Disable**: Toggle switch in detail view
- **Run Manually**: Click "Run Now" button
- **Delete**: Click "Delete Automation" button (confirms first)
- **Refresh**: Click refresh icon in toolbar

### View History
1. Menu bar → **"History…"** (or press **⌘H**)
2. Filter by status, date range, or search
3. Sort newest/oldest

### Configure Settings
1. Menu bar → **"Settings…"** (or press **⌘,**)
2. **General**: Home name, temperature units, launch at login
3. **Advanced**: Socket path, log retention, max restarts

---

## 📁 Project Structure

### Core Files You'll Edit Most

```
ContentView.swift              ← Main UI (automations list + detail)
CreateAutomationView.swift     ← Create automation sheet
AutomationStore.swift          ← Data management
HelperAPIClient.swift          ← API calls to helper
```

### Supporting Files

```
AppDelegate.swift              ← Menu bar management
DashboardView.swift            ← Legacy dashboard
HistoryView.swift              ← Execution history
SettingsView.swift             ← App settings
HelperManager.swift            ← Helper process lifecycle
```

### Data Models

```
AutomationModels.swift         ← All data structures
AppSettings.swift              ← Settings definitions
SocketConstants.swift          ← Socket configuration
```

### UI Components

```
AutomationRowView.swift        ← Sidebar row (inline in ContentView)
AutomationListItem.swift       ← Dashboard list item
LogEntryRow.swift              ← History timeline entry
```

---

## 🔧 Common Tasks

### Add a New Feature

1. **Create a new view**:
   ```swift
   // MyNewView.swift
   import SwiftUI
   
   struct MyNewView: View {
       @State private var store = AutomationStore()
       
       var body: some View {
           VStack {
               Text("My Feature")
           }
       }
   }
   ```

2. **Add to menu bar** (AppDelegate.swift):
   ```swift
   let myMenuItem = NSMenuItem(
       title: "My Feature…",
       action: #selector(openMyFeature),
       keyEquivalent: "m"
   )
   myMenuItem.target = self
   menu.addItem(myMenuItem)
   ```

3. **Create window opener**:
   ```swift
   @objc private func openMyFeature() {
       let view = MyNewView()
       let hostingView = NSHostingView(rootView: view)
       let window = NSWindow(
           contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
           styleMask: [.titled, .closable, .resizable],
           backing: .buffered,
           defer: false
       )
       window.contentView = hostingView
       window.makeKeyAndOrderFront(nil)
   }
   ```

### Add API Endpoint

1. **Add to HelperAPIClient.swift**:
   ```swift
   func myNewCommand() async throws -> MyResponse {
       let response = try await sendCommand("my-command")
       return try JSONDecoder().decode(MyResponse.self, from: Data(response.utf8))
   }
   ```

2. **Define response type**:
   ```swift
   struct MyResponse: Codable, Sendable {
       let result: String
   }
   ```

3. **Use in view**:
   ```swift
   Button("Run Command") {
       Task {
           do {
               let result = try await HelperAPIClient.shared.myNewCommand()
               print(result)
           } catch {
               print("Error: \(error)")
           }
       }
   }
   ```

### Add Setting

1. **Add key to AppSettings.swift**:
   ```swift
   enum AppSettingsKeys {
       static let myNewSetting = "myNewSetting"
   }
   
   enum AppSettingsDefaults {
       static let myNewSetting = true
   }
   ```

2. **Add to SettingsView.swift**:
   ```swift
   @AppStorage(AppSettingsKeys.myNewSetting)
   private var myNewSetting: Bool = AppSettingsDefaults.myNewSetting
   
   // In body:
   Toggle("My Setting", isOn: $myNewSetting)
   ```

3. **Use anywhere**:
   ```swift
   @AppStorage(AppSettingsKeys.myNewSetting)
   private var myNewSetting: Bool = AppSettingsDefaults.myNewSetting
   ```

---

## 🐛 Debugging

### Check Helper Status
```swift
print("Helper status: \(helperManager.helperStatus)")
print("Helper running: \(helperManager.isHelperRunning)")
```

### Test Socket Connection
```bash
# In Terminal
echo '{"id":"test","command":"status","token":"YOUR_TOKEN","version":"1.0"}' | \
nc -U ~/Library/Application\ Support/homekit-automator/homekitauto.sock
```

### View Logs
```bash
# Automation data
cat ~/Library/Application\ Support/homekit-automator/automations.json

# Execution logs
cat ~/Library/Application\ Support/homekit-automator/logs/automation-log.json
```

### Reset Everything
```bash
# Stop helper
pkill HomeKitHelper

# Clear data
rm -rf ~/Library/Application\ Support/homekit-automator/

# Rebuild and run
```

---

## 📚 Key Concepts

### State Management
- Use `@Observable` for stores
- Use `@State` for local view state
- Use `@AppStorage` for persistent settings
- Always mark MainActor for UI classes

### Async/Await
- Use `Task { }` to call async from sync
- Use `await` for async operations
- Use `try await` for throwing async
- Use `defer` for cleanup

### Socket Communication
- Always runs on background queue
- Returns to MainActor for UI updates
- Has timeout handling (30s)
- Retries on connection failure (via HelperManager)

### Data Persistence
- JSON files in Application Support
- Atomic writes prevent corruption
- Shared with CLI tool
- Manual refresh required (no FileSystemWatcher yet)

---

## 🎨 SwiftUI Tips

### Navigation
```swift
// Three-column split view
NavigationSplitView {
    List(selection: $selected) { /* sidebar */ }
} detail: {
    if let item = selected { DetailView(item: item) }
}
```

### Sheets
```swift
@State private var showSheet = false

.sheet(isPresented: $showSheet) {
    MyView { /* onComplete */ }
}
```

### Alerts
```swift
@State private var showAlert = false

.alert("Title", isPresented: $showAlert) {
    Button("OK") { }
} message: {
    Text("Message")
}
```

### Progress
```swift
if isLoading {
    ProgressView("Loading...")
}
```

---

## ⚡️ Performance Tips

1. **Use `.task` for loading**:
   ```swift
   .task { await loadData() }
   ```

2. **Debounce searches**:
   ```swift
   @State private var searchTask: Task<Void, Never>?
   
   .onChange(of: searchText) { _, newValue in
       searchTask?.cancel()
       searchTask = Task {
           try? await Task.sleep(for: .seconds(0.3))
           performSearch(newValue)
       }
   }
   ```

3. **Cache expensive computations**:
   ```swift
   private var filteredItems: [Item] {
       // Computed once per render
   }
   ```

4. **Use identifiable for ForEach**:
   ```swift
   ForEach(items) { item in /* ... */ }
   ```

---

## 🚨 Common Issues

### "Socket connection failed"
- Helper not running → Check menu bar status
- Wrong socket path → Check settings
- Permissions issue → Reset token in SocketConstants

### "No automations shown"
- Empty registry → Create via CLI first
- Wrong path → Check AutomationStore.configDir
- Invalid JSON → Delete and recreate file

### "Helper keeps restarting"
- Rate limit exceeded → Wait 15 minutes
- Crash on launch → Check helper logs
- Missing bundle → Ensure HomeKitHelper.app is present

### "Toggle doesn't work"
- State not updating → Store needs reload
- JSON write failed → Check disk space
- Socket error → Helper connection lost

---

## 📦 Dependencies

### Built-in Frameworks
- SwiftUI (UI)
- AppKit (Menu bar, windows)
- Foundation (Data, JSON)
- ServiceManagement (Launch at login)

### No External Dependencies!
All features built with Apple frameworks.

---

## 🎯 Next Implementation Steps

If you want to add LLM integration:

1. **Add API key setting**:
   ```swift
   static let openaiAPIKey = "openaiAPIKey"
   ```

2. **Create LLM service**:
   ```swift
   actor LLMService {
       func parseAutomation(_ prompt: String) async throws -> AutomationDefinition
   }
   ```

3. **Update CreateAutomationView**:
   ```swift
   let definition = try await LLMService().parseAutomation(userPrompt)
   let response = try await HelperAPIClient.shared.createAutomation(definition)
   ```

4. **Handle errors gracefully**:
   ```swift
   catch {
       errorMessage = error.localizedDescription
   }
   ```

---

## ✅ Checklist for New Developers

- [ ] Project builds without errors
- [ ] App appears in menu bar
- [ ] Can view automations list (even if empty)
- [ ] Can open all windows (Dashboard, History, Settings)
- [ ] Helper status shows "Connected" or "Disconnected"
- [ ] Can create automation via CLI
- [ ] Created automation appears after refresh
- [ ] Can toggle automation on/off
- [ ] Can delete automation
- [ ] Can view execution history

If all checked, you're ready to develop! 🎉

---

## 📞 Getting Help

1. Read the main README: `README_XCODE.md`
2. Check implementation summary: `IMPLEMENTATION_SUMMARY.md`
3. Review code comments in source files
4. Test with preview providers (⌥⌘↵)
5. Use Xcode debugger and breakpoints

Happy coding! 🚀
