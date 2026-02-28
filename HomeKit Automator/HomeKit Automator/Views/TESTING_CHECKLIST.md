# Testing & Debugging Checklist

## 🧪 Phase 1: Compilation & Build

### Step 1: Check for Build Errors

Run these checks in Xcode:

1. **Clean Build Folder**
   - Product → Clean Build Folder (⇧⌘K)

2. **Build Project**
   - Product → Build (⌘B)

3. **Expected Warnings/Errors to Fix**:

#### Issue 1: Missing @MainActor on AutomationDetailView
**Location**: `ContentView.swift` line ~170

**Problem**: `AutomationDetailView` accesses `@State` store which needs MainActor

**Fix**:
```swift
// Add @MainActor before struct
@MainActor
struct AutomationDetailView: View {
    let automation: RegisteredAutomation
    @State private var store = AutomationStore()
    // ...
}
```

#### Issue 2: Store synchronization in DetailView
**Location**: `ContentView.swift` - AutomationDetailView

**Problem**: Each detail view creates its own store instance, changes won't reflect in main list

**Fix Option A** (Recommended): Pass store as parameter
```swift
struct AutomationDetailView: View {
    let automation: RegisteredAutomation
    @Bindable var store: AutomationStore  // Use passed-in store
    @State private var showingDeleteAlert = false
    @State private var isTriggeringManually = false
    // ...
}

// In ContentView detail section:
if let automation = selectedAutomation {
    AutomationDetailView(automation: automation, store: store)
}
```

**Fix Option B**: Use Environment
```swift
// In ContentView:
.environment(store)

// In AutomationDetailView:
@Environment(AutomationStore.self) private var store
```

#### Issue 3: After delete, selection becomes invalid
**Location**: `ContentView.swift` - deleteAutomations

**Fix**: Clear selection after delete
```swift
private func deleteAutomations(at offsets: IndexSet) {
    for index in offsets {
        let automation = store.automations[index]
        if selectedAutomation?.id == automation.id {
            selectedAutomation = nil
        }
        store.delete(automation.id)
    }
}
```

---

## 🔍 Phase 2: Runtime Testing

### Test Case 1: App Launch

**Steps**:
1. Build and run (⌘R)
2. Check menu bar for house icon
3. Verify status shows "Checking..." then updates

**Expected Result**:
- App appears in menu bar (no Dock icon due to LSUIElement)
- Status item shows connection state
- No crashes

**Common Issues**:
- **No icon appears**: Check Info.plist has LSUIElement = true
- **Helper not found**: Ensure HomeKitHelper.app is in correct location
- **Socket error**: Check socket path in settings

---

### Test Case 2: Empty State

**Steps**:
1. Click menu bar → "Show Automations"
2. Verify empty state appears

**Expected Result**:
- ContentUnavailableView shows
- "Create Automation" button visible
- No crashes

**Common Issues**:
- **Blank screen**: Check store.automations is actually empty
- **Loading forever**: Check isLoading state resets properly

---

### Test Case 3: Create Automation (Placeholder)

**Steps**:
1. Click "+" button or "Create Automation"
2. Sheet should appear
3. Enter text and click "Create Automation"

**Expected Result**:
- Sheet appears over main window
- Error message shows about LLM requirement
- Dismisses when clicking cancel

**Common Issues**:
- **Sheet doesn't appear**: Check showingCreateSheet binding
- **Can't dismiss**: Check dismiss environment value

---

### Test Case 4: Load Automations from CLI

**Steps**:
1. Create automation via CLI:
   ```bash
   cd path/to/cli
   ./homekitauto automation create --interactive
   # Or use a test JSON file
   ```

2. In app, click refresh button
3. Automation should appear

**Expected Result**:
- Automation loads from disk
- Appears in sidebar list
- Can select to view details

**Common Issues**:
- **Doesn't appear**: Check file path matches AutomationStore.configDir
- **Parse error**: Check JSON is valid
- **Wrong directory**: Verify both CLI and app use same location

---

### Test Case 5: Select Automation

**Steps**:
1. Click automation in sidebar
2. Detail view should appear

**Expected Result**:
- Right panel shows automation details
- All sections render correctly
- Toggle switch reflects enabled state

**Common Issues**:
- **Blank detail**: Check selectedAutomation binding
- **Wrong data**: Check automation is passed correctly
- **Toggle doesn't work**: Store synchronization issue (see fix above)

---

### Test Case 6: Toggle Enable/Disable

**Steps**:
1. Select an automation
2. Toggle the switch in detail view
3. Check JSON file updates

**Expected Result**:
- Switch toggles immediately
- JSON file writes to disk
- State persists after refresh

**Common Issues**:
- **Doesn't toggle**: Store instance mismatch
- **Doesn't persist**: File write failed (check permissions)
- **Sidebar doesn't update**: Need to refresh store

---

### Test Case 7: Delete Automation

**Steps**:
1. Select automation
2. Click "Delete Automation"
3. Confirm in alert

**Expected Result**:
- Confirmation alert appears
- After confirm, automation removed
- Sidebar updates immediately
- Detail view clears

**Common Issues**:
- **Still appears**: Store not reloading
- **Crash**: Selection not cleared (see fix above)
- **Reappears after refresh**: JSON not updated

---

### Test Case 8: Manual Trigger

**Steps**:
1. Select automation
2. Click "Run Now" button
3. Wait for completion

**Expected Result**:
- Button shows "Running..." with spinner
- After delay, returns to "Run Now"
- Execution logged (check History)

**Common Issues**:
- **Timeout**: Helper not responding (check socket)
- **Forever loading**: Error not caught properly
- **No log entry**: Helper didn't write log

---

### Test Case 9: History View

**Steps**:
1. Menu bar → "History"
2. Should show execution log entries

**Expected Result**:
- Window opens with history
- Can filter by status
- Can search by name
- Date range works

**Common Issues**:
- **Empty when shouldn't be**: Log file path wrong
- **Crash on filter**: Check filteredEntries logic
- **Won't open**: Window creation failed

---

### Test Case 10: Dashboard View

**Steps**:
1. Menu bar → "Legacy Dashboard"
2. Should show automation list

**Expected Result**:
- Window opens
- Shows all automations
- Toggle switches work
- Delete button works

**Common Issues**:
- **Blank**: Store not loading
- **Toggle doesn't work**: Store instance issue
- **Delete doesn't confirm**: Alert binding issue

---

### Test Case 11: Settings

**Steps**:
1. Menu bar → "Settings" (⌘,)
2. Modify settings
3. Close and reopen

**Expected Result**:
- Settings window opens
- Changes persist via @AppStorage
- Launch at login works

**Common Issues**:
- **Won't open**: Settings scene not configured
- **Doesn't persist**: @AppStorage key mismatch
- **Launch at login fails**: SMAppService error

---

### Test Case 12: Helper Management

**Steps**:
1. Menu bar → "Restart Helper"
2. Wait for restart

**Expected Result**:
- Status changes to "Restarting..."
- Then "Connected" or "Disconnected"
- Icon updates

**Common Issues**:
- **Stays disconnected**: Helper can't launch
- **Rapid restarts**: Rate limit triggered
- **Status stuck**: Health check not running

---

## 🐛 Phase 3: Common Bug Fixes

### Bug Fix 1: Store Synchronization

**File**: `ContentView.swift`

```swift
// Change AutomationDetailView to accept store
struct AutomationDetailView: View {
    let automation: RegisteredAutomation
    @Bindable var store: AutomationStore  // Changed from @State
    @State private var showingDeleteAlert = false
    @State private var isTriggeringManually = false
    
    var body: some View {
        Form {
            // ... existing code ...
        }
    }
    
    // ... rest of implementation
}

// Update usage in ContentView
} detail: {
    if let automation = selectedAutomation {
        AutomationDetailView(automation: automation, store: store)
    } else {
        ContentUnavailableView {
            Label("Select an Automation", systemImage: "slider.horizontal.3")
        } description: {
            Text("Choose an automation from the sidebar to view details")
        }
    }
}
```

---

### Bug Fix 2: Selection Clearing on Delete

**File**: `ContentView.swift`

```swift
private func deleteAutomations(at offsets: IndexSet) {
    for index in offsets {
        let automation = store.automations[index]
        // Clear selection if we're deleting the selected item
        if selectedAutomation?.id == automation.id {
            selectedAutomation = nil
        }
        store.delete(automation.id)
    }
}
```

---

### Bug Fix 3: AutomationStore Environment Setup

**File**: `AutomationStore.swift`

Add conformance to make it work with @Bindable:

```swift
// No changes needed - @Observable already provides this
```

---

### Bug Fix 4: Better Error Handling in Trigger

**File**: `ContentView.swift` - AutomationDetailView

```swift
private func triggerManually() {
    Task {
        isTriggeringManually = true
        defer { isTriggeringManually = false }
        
        do {
            try await HelperAPIClient.shared.triggerAutomation(automation.id)
            // Give it a moment to execute
            try? await Task.sleep(for: .seconds(1))
            store.reload()
        } catch {
            // Show error to user
            print("Failed to trigger automation: \(error)")
            // TODO: Show alert with error
        }
    }
}
```

---

### Bug Fix 5: Preview Fix

**File**: `ContentView.swift`

```swift
#Preview("Automation Detail") {
    // Need to provide a store
    let store = AutomationStore()
    
    NavigationStack {
        AutomationDetailView(
            automation: RegisteredAutomation(
                id: "preview-1",
                name: "Morning Lights",
                description: "Turn on bedroom lights in the morning",
                trigger: AutomationTrigger(
                    type: "time",
                    humanReadable: "Every day at 7:00 AM"
                ),
                conditions: nil,
                actions: [
                    AutomationAction(
                        deviceName: "Bedroom Light",
                        characteristic: "On",
                        value: .bool(true)
                    )
                ],
                enabled: true,
                shortcutName: "Morning Lights",
                createdAt: "2026-02-26T08:00:00Z"
            ),
            store: store
        )
    }
}
```

---

## 🧪 Phase 4: Integration Testing

### Test Scenario 1: End-to-End Flow

1. **Start**: Fresh app launch
2. **Create**: Make automation via CLI
3. **View**: Open app, refresh, see automation
4. **Toggle**: Disable/enable
5. **Trigger**: Run manually
6. **Check**: View in history
7. **Delete**: Remove automation
8. **Verify**: Confirm gone from disk

---

### Test Scenario 2: Helper Lifecycle

1. **Launch**: App starts helper automatically
2. **Monitor**: Health checks run every 30s
3. **Kill**: Manually kill helper process
4. **Recover**: App should auto-restart
5. **Limit**: Kill 6 times rapidly to hit rate limit
6. **Verify**: Status shows error, stops restarting

---

### Test Scenario 3: Data Persistence

1. **Create**: Make several automations
2. **Modify**: Enable/disable various ones
3. **Quit**: Close app completely
4. **Relaunch**: Open app again
5. **Verify**: All changes persisted

---

### Test Scenario 4: Multiple Windows

1. **Open**: Main window, Dashboard, History, Settings
2. **Interact**: Make changes in multiple windows
3. **Verify**: Changes sync across windows (requires store sharing)

---

## 📋 Testing Checklist

Copy this to track your testing progress:

### Compilation
- [ ] Clean build folder
- [ ] Build succeeds without errors
- [ ] No critical warnings

### Basic Functionality
- [ ] App launches successfully
- [ ] Menu bar icon appears
- [ ] Status updates correctly
- [ ] Main window opens

### Automations
- [ ] Empty state shows correctly
- [ ] Can load automations from disk
- [ ] Can select automation
- [ ] Detail view shows all info
- [ ] Can toggle enabled/disabled
- [ ] Can delete automation
- [ ] Can manually trigger
- [ ] Swipe to delete works

### Other Views
- [ ] Dashboard opens and functions
- [ ] History opens and shows logs
- [ ] Settings opens and persists changes
- [ ] All filters work in history

### Helper Management
- [ ] Helper launches on startup
- [ ] Health checks update status
- [ ] Can manually restart helper
- [ ] Auto-restart works (test by killing helper)
- [ ] Rate limiting prevents infinite restarts

### Edge Cases
- [ ] Works with no automations
- [ ] Works with many automations (50+)
- [ ] Handles invalid JSON gracefully
- [ ] Handles missing files gracefully
- [ ] Handles helper not running
- [ ] Handles socket timeout

---

## 🎯 Priority Fixes to Make Now

Before moving to the next phase, implement these critical fixes:

### 1. Store Synchronization (HIGH PRIORITY)
The detail view creates its own store, causing changes to not reflect.

### 2. Selection Clearing (MEDIUM PRIORITY)
Deleting selected automation crashes.

### 3. Error Display (LOW PRIORITY)
Manual trigger errors only print to console.

---

## 🚀 Next Steps

Once testing is complete and bugs are fixed:

1. ✅ **Test & Debug** ← You are here
2. 🔜 **Add LLM Integration** 
3. 🔜 **Build Helper App**
4. 🔜 **Add Features**
5. 🔜 **Work on CLI**

Ready to fix the identified issues?
