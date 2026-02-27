# HomeKit Automator Architecture

## 🏗️ System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         macOS Menu Bar                          │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  🏠 Status: Connected                                    │   │
│  │  ────────────────────────────────────────────────────    │   │
│  │  Show Automations… ⌘A   ← Opens ContentView            │   │
│  │  Legacy Dashboard… ⌘D    ← Opens DashboardView         │   │
│  │  History… ⌘H             ← Opens HistoryView           │   │
│  │  Settings… ⌘,            ← Opens SettingsView          │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              HomeKit Automator App (SwiftUI)                    │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  HomeKitAutomatorApp.swift (Entry Point)              │    │
│  │  • @main struct                                        │    │
│  │  • Window scene (ContentView)                          │    │
│  │  • Settings scene                                      │    │
│  │  • AppDelegate integration                             │    │
│  └────────────────────────────────────────────────────────┘    │
│                              │                                  │
│           ┌──────────────────┼──────────────────┐              │
│           ▼                  ▼                  ▼              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ ContentView  │  │ DashboardView│  │ HistoryView  │         │
│  │  (NEW!)      │  │  (Legacy)    │  │              │         │
│  │              │  │              │  │              │         │
│  │ • Search     │  │ • List view  │  │ • Log table  │         │
│  │ • Sidebar    │  │ • Toggles    │  │ • Filters    │         │
│  │ • Detail     │  │ • Delete     │  │ • Stats      │         │
│  │ • Stats      │  │              │  │              │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
│           │                  │                  │              │
│           └──────────────────┼──────────────────┘              │
│                              ▼                                  │
│                  ┌─────────────────────┐                        │
│                  │  AutomationStore    │                        │
│                  │  (@Observable)      │                        │
│                  │                     │                        │
│                  │  • Load/save JSON   │                        │
│                  │  • CRUD operations  │                        │
│                  │  • Success rates    │                        │
│                  │  • Log queries      │                        │
│                  └─────────────────────┘                        │
│                              │                                  │
└──────────────────────────────┼──────────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│           File System (Application Support)                     │
│                                                                 │
│  ~/Library/Application Support/homekit-automator/              │
│  ├── automations.json           ← RegisteredAutomation[]       │
│  ├── logs/                                                      │
│  │   └── automation-log.json    ← AutomationLogEntry[]         │
│  ├── homekitauto.sock           ← Unix domain socket           │
│  └── .auth_token                ← Shared authentication        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                               ▲
                               │
┌──────────────────────────────┼──────────────────────────────────┐
│                              │                                  │
│                  ┌─────────────────────┐                        │
│                  │  HelperManager      │                        │
│                  │  (@Observable)      │                        │
│                  │                     │                        │
│                  │  • Launch helper    │                        │
│                  │  • Health checks    │                        │
│                  │  • Auto-restart     │                        │
│                  │  • Socket IPC       │                        │
│                  └─────────────────────┘                        │
│                              │                                  │
│                              ▼                                  │
│                  ┌─────────────────────┐                        │
│                  │  HomeKitHelper.app  │                        │
│                  │  (Companion)        │                        │
│                  │                     │                        │
│                  │  • HomeKit access   │                        │
│                  │  • Device control   │                        │
│                  │  • Socket server    │                        │
│                  │  • No UI            │                        │
│                  └─────────────────────┘                        │
│                              │                                  │
└──────────────────────────────┼──────────────────────────────────┘
                               ▼
                    ┌──────────────────────┐
                    │  HomeKit Framework   │
                    │  (Apple)             │
                    │                      │
                    │  • Accessories       │
                    │  • Services          │
                    │  • Characteristics   │
                    └──────────────────────┘
                               │
                               ▼
                      🏠 Your HomeKit Devices
```

---

## 📦 Data Models Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    AutomationModels.swift                       │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  AutomationDefinition (Input)                            │  │
│  │  • From LLM or user input                                │  │
│  │  • Not validated yet                                     │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              │                                  │
│                              ▼                                  │
│                      Validation by CLI                          │
│                              │                                  │
│                              ▼                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  RegisteredAutomation (Stored)                           │  │
│  │  • Validated                                             │  │
│  │  • Has UUID                                              │  │
│  │  • Has shortcut name                                     │  │
│  │  • Persisted in automations.json                         │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              │                                  │
│                    ┌─────────┼─────────┐                        │
│                    ▼         ▼         ▼                        │
│         ┌──────────────┬─────────┬───────────┐                 │
│         │ Trigger      │ Condition│ Action    │                 │
│         │              │          │           │                 │
│         │ • Type       │ • Type   │ • Device  │                 │
│         │ • Schedule   │ • Guard  │ • Value   │                 │
│         │ • Event      │ • Time   │ • Delay   │                 │
│         └──────────────┴─────────┴───────────┘                 │
│                              │                                  │
│                              ▼                                  │
│                      Execution by Helper                        │
│                              │                                  │
│                              ▼                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  AutomationLogEntry (Result)                             │  │
│  │  • Automation ID                                         │  │
│  │  • Timestamp                                             │  │
│  │  • Actions executed                                      │  │
│  │  • Success/failure counts                                │  │
│  │  • Error messages                                        │  │
│  │  • Persisted in automation-log.json                      │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔄 ContentView Structure (NEW)

```
ContentView
│
├─ NavigationSplitView
│  │
│  ├─ Sidebar (Left)
│  │  │
│  │  ├─ Search Bar
│  │  │  └─ TextField with clear button
│  │  │
│  │  ├─ List
│  │  │  └─ ForEach(filteredAutomations)
│  │  │     └─ NavigationLink
│  │  │        └─ AutomationRowView
│  │  │           ├─ Name
│  │  │           ├─ Description
│  │  │           ├─ Trigger info
│  │  │           ├─ Success rate badge
│  │  │           └─ Enabled indicator
│  │  │
│  │  └─ Toolbar
│  │     ├─ Create button
│  │     └─ Refresh button
│  │
│  └─ Detail (Right)
│     │
│     └─ AutomationDetailView
│        │
│        ├─ Header with toggle
│        ├─ Statistics (3 cards)
│        │  ├─ Success rate
│        │  ├─ Execution count
│        │  └─ Last run time
│        │
│        ├─ Trigger section
│        │  └─ InfoCard
│        │
│        ├─ Conditions section (if any)
│        │  └─ ForEach(conditions)
│        │     └─ InfoCard
│        │
│        ├─ Actions section
│        │  └─ ForEach(actions)
│        │     └─ InfoCard
│        │        ├─ Device name
│        │        ├─ Room
│        │        ├─ Characteristic
│        │        ├─ Value
│        │        └─ Delay (if any)
│        │
│        ├─ Details section
│        │  └─ InfoCard
│        │     ├─ ID
│        │     ├─ Shortcut name
│        │     ├─ Created timestamp
│        │     └─ Last run timestamp
│        │
│        └─ Delete button
│
└─ Alert (Delete confirmation)
```

---

## 🎨 Component Hierarchy

```
ContentView (Main container)
│
├─ AutomationRowView (Reusable list item)
│  ├─ Icon
│  ├─ VStack (text)
│  ├─ VStack (stats)
│  └─ HStack (controls)
│
├─ AutomationDetailView (Reusable detail)
│  ├─ Header card
│  ├─ StatBox × 3
│  ├─ SectionHeader × N
│  ├─ InfoCard × N
│  │  └─ LabeledRow × N
│  └─ Delete button
│
├─ StatBox (Reusable stat display)
│  ├─ Icon
│  ├─ Value text
│  └─ Label text
│
├─ SectionHeader (Reusable section title)
│  └─ Label with icon
│
├─ InfoCard (Reusable container)
│  └─ Generic content
│
└─ LabeledRow (Reusable key-value)
   ├─ Label text
   └─ Value text
```

---

## 🔌 IPC Communication

```
┌──────────────────┐                    ┌──────────────────┐
│  GUI App         │                    │ HomeKitHelper    │
│  (Menu Bar)      │                    │ (Companion)      │
│                  │                    │                  │
│  HelperManager   │◄───────────────────┤ Socket Server    │
│                  │   Unix Socket      │                  │
│                  │   Auth Token       │                  │
│                  │                    │                  │
│  Commands:       │                    │  Responses:      │
│  • ping          ├───────────────────►│  • pong          │
│  • shutdown      ├───────────────────►│  • ok            │
│  • status        ├───────────────────►│  • status data   │
│                  │                    │                  │
└──────────────────┘                    └──────────────────┘
         │                                       │
         │                                       │
         ▼                                       ▼
   Reads/Writes                            Reads/Writes
         │                                       │
         └───────────────┬───────────────────────┘
                         ▼
            ┌─────────────────────┐
            │  JSON Files         │
            │                     │
            │  automations.json   │
            │  logs/*.json        │
            └─────────────────────┘
```

---

## 📝 File Relationships

```
HomeKitAutomatorApp.swift (Entry)
    │
    ├─ Creates Window("main") → ContentView
    ├─ Creates Settings → SettingsView
    └─ Injects AppDelegate
              │
              ├─ Creates NSStatusItem (menu bar)
              ├─ Creates DashboardView window
              ├─ Creates HistoryView window
              └─ Manages HelperManager
                        │
                        └─ Launches HomeKitHelper.app

ContentView
    │
    ├─ Owns AutomationStore
    │     │
    │     ├─ Reads automations.json
    │     ├─ Reads automation-log.json
    │     └─ Writes automations.json
    │
    └─ Renders AutomationRowView × N
              │
              └─ Navigates to AutomationDetailView
```

---

## 🔄 State Management

```
@Observable AutomationStore
    │
    ├─ automations: [RegisteredAutomation]
    ├─ logEntries: [AutomationLogEntry]
    └─ lastError: String?
              │
              ├─ func reload()
              ├─ func toggleEnabled(_:)
              ├─ func delete(_:)
              ├─ func successRate(for:) -> Double
              └─ func logEntries(for:) -> [Entry]
                        │
                        ▼
                 Automatic UI updates
                 (Swift Observation)
                        │
                        ▼
               ContentView re-renders
```

---

## 🎯 User Interaction Flow

```
1. User clicks menu bar icon
   └─► Menu appears

2. User clicks "Show Automations…"
   └─► Window opens with ContentView
       └─► AutomationStore loads data
           └─► Sidebar shows list

3. User types in search box
   └─► filteredAutomations updates
       └─► List re-renders

4. User clicks automation
   └─► selectedAutomation = automation
       └─► Detail view shows

5. User right-clicks automation
   └─► Context menu appears
       ├─► Enable/Disable
       │   └─► store.toggleEnabled(id)
       │       └─► JSON written to disk
       │           └─► List updates
       └─► Delete
           └─► Confirmation alert
               └─► store.delete(id)
                   └─► JSON written to disk
                       └─► List updates

6. User clicks "Refresh"
   └─► store.reload()
       └─► JSON read from disk
           └─► UI updates
```

---

## 🏃 Execution Flow

```
1. HomeKitHelper monitors triggers
   └─► Cron schedules
   └─► Solar events
   └─► Device state changes

2. Trigger fires
   └─► Check conditions
       └─► All pass?
           ├─► Execute actions
           │   └─► For each action:
           │       ├─► Apply delay
           │       ├─► Update device
           │       └─► Log result
           └─► Write log entry
               └─► automation-log.json

3. GUI refreshes (periodic or manual)
   └─► AutomationStore.reload()
       └─► Reads automation-log.json
           └─► UI shows new stats
```

---

## 🎨 Visual Hierarchy

```
┌─────────────────────────────────────────────────────────────┐
│  Window: HomeKit Automator                      🟢🟡🔴       │
├─────────────────────────────────────────────────────────────┤
│  Toolbar: [➕ Create] [🔄 Refresh]                          │
├───────────────────────┬─────────────────────────────────────┤
│  Sidebar              │  Detail                             │
│                       │                                     │
│  [🔍 Search...    ✕]  │  Morning Lights                     │
│  ──────────────────── │  Turn on bedroom lights             │
│                       │  [◼︎◼︎◼︎◼︎◼︎◼︎◼︎◼︎◼︎━━━━ Enabled]      │
│  ⏰ Morning Lights    │  ─────────────────────────────────  │
│     Every day at 7AM  │  ┌─────────┐┌─────────┐┌─────────┐ │
│     Turn on bedroom   │  │ 98%     ││ 45 runs ││ 2m ago  │ │
│     ✓ 98%            │  │ success ││ total   ││ last    │ │
│                       │  └─────────┘└─────────┘└─────────┘ │
│  🌅 Evening Routine   │  ─────────────────────────────────  │
│     At sunset         │  ⚡ TRIGGER                         │
│     Close blinds      │  • Type: time                       │
│     ⚠️ 75%            │  • Every day at 7:00 AM             │
│                       │                                     │
│  ⏰ Bedtime           │  🎬 ACTIONS                         │
│     Every day 11PM    │  1. Bedroom Light                   │
│     All lights off    │     • Room: Bedroom                 │
│     ✓ 100%           │     • On → true                     │
│                       │  2. Bedroom Light (2s delay)       │
│  [Empty...]           │     • Brightness → 75               │
│                       │                                     │
│                       │  [🗑️ Delete Automation]             │
└───────────────────────┴─────────────────────────────────────┘
```

---

This architecture provides:
- ✅ **Separation of concerns** - UI, data, and logic are separated
- ✅ **Reactive updates** - Changes propagate automatically
- ✅ **Persistence** - Data survives app restarts
- ✅ **IPC** - Clean communication with helper process
- ✅ **Reusability** - Components can be used elsewhere
- ✅ **Testability** - Each layer can be tested independently

