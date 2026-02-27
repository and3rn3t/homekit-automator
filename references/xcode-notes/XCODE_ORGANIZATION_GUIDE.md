# 🎯 Xcode Project Organization Guide

## Quick Fix Steps

Follow these steps **in order** to properly organize your Xcode project:

### Step 1: Clean Everything 🧹

1. **Open your project in Xcode**
2. Press **⌘⇧K** (Product → Clean Build Folder)
3. Wait for "Clean Finished" message

### Step 2: Close Xcode and Clean Derived Data 🗑️

1. **Quit Xcode** (⌘Q)
2. **Open Terminal** and run:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/HomeKitAutomator-*
   ```

### Step 3: Verify Project Files 📋

In Terminal, navigate to your project directory and verify these files exist:

```bash
cd ~/path/to/your/project

# Check all required files exist
ls -la *.swift
```

You should see these files in the root:
- ✅ HomeKitAutomatorApp.swift
- ✅ AppDelegate.swift  
- ✅ ContentView.swift
- ✅ AutomationModels.swift (NOT Models.swift!)
- ✅ AutomationStore.swift
- ✅ DashboardView.swift
- ✅ HistoryView.swift
- ✅ SettingsView.swift
- ✅ AppSettings.swift
- ✅ HelperManager.swift
- ✅ SocketConstants.swift
- ✅ AutomationListItem.swift
- ✅ LogEntryRow.swift

### Step 4: Remove Any Old Models.swift File ❌

**CRITICAL:** If you have an old `Models.swift` file, it MUST be deleted:

```bash
# Find any Models.swift files
find . -name "Models.swift" -type f

# If found, delete them (NOT AutomationModels.swift!)
# Example:
# rm "./HomeKit Automator/App/Models.swift"
```

### Step 5: Reopen Xcode and Add Files 📂

1. **Open Xcode** again
2. In **Project Navigator** (left sidebar), find your app target group
3. **For each file listed in Step 3**, verify it's in the project:
   - If missing, **Right-click** your app group
   - Choose **"Add Files to [Your Target]..."**
   - Select the missing Swift file(s)
   - ✅ **IMPORTANT:** Check the "Add to targets" box for your app
   - Click **"Add"**

### Step 6: Verify Target Membership 🎯

For **each Swift file** in your project:

1. **Click the file** in Project Navigator
2. **Open File Inspector** (⌘⌥1 or right sidebar)
3. Under **"Target Membership"**, verify your app target is **✅ CHECKED**
4. If not checked, check it!

### Step 7: Reset Swift Package Manager 📦

1. In Xcode menu: **File → Packages → Reset Package Caches**
2. Wait for it to complete
3. Then: **File → Packages → Resolve Package Versions**
4. Wait for resolution to complete

### Step 8: Clean and Build 🔨

1. **Clean again:** Press **⌘⇧K**
2. **Build:** Press **⌘B**

**Expected:** Build Succeeded ✅

---

## 📁 Correct Project Structure

Your Xcode project should look like this in the Project Navigator:

```
HomeKit Automator
├── HomeKit Automator (folder)
│   ├── HomeKitAutomatorApp.swift       ← App entry point with @main
│   ├── AppDelegate.swift                ← Menu bar management
│   ├── ContentView.swift                ← Main window view
│   ├── AutomationModels.swift           ← Data models (renamed!)
│   ├── AutomationStore.swift            ← Data store
│   ├── SocketConstants.swift            ← Socket communication
│   ├── HelperManager.swift              ← Helper process manager
│   ├── AppSettings.swift                ← Settings definitions
│   ├── Views/
│   │   ├── DashboardView.swift          ← Legacy dashboard
│   │   ├── HistoryView.swift            ← Execution history
│   │   ├── SettingsView.swift           ← Settings panel
│   │   ├── AutomationListItem.swift     ← Row component
│   │   └── LogEntryRow.swift            ← Log row component
│   └── Assets.xcassets
├── Packages (dependencies)
│   └── HomeKitCore (Swift Package)
└── Products
```

---

## 🚨 Common Errors and Fixes

### Error: "Filename 'Models.swift' used twice"

**Cause:** Old Models.swift conflicts with AutomationModels.swift or SPM module

**Fix:**
1. Find and delete ALL `Models.swift` files (keep AutomationModels.swift)
2. Clean derived data (see Step 2)
3. Clean and rebuild

---

### Error: "Cannot find type 'RegisteredAutomation'"

**Cause:** AutomationModels.swift is not in your app target

**Fix:**
1. Select AutomationModels.swift in Project Navigator
2. Open File Inspector (⌘⌥1)
3. Under "Target Membership", check your app target box
4. Clean and rebuild

---

### Error: "Module 'HomeKitCore' not found"

**Cause:** Swift Package Manager needs to resolve dependencies

**Fix:**
1. File → Packages → Reset Package Caches
2. File → Packages → Resolve Package Versions
3. Wait for resolution
4. Clean and rebuild

---

### Error: "lstat: No such file or directory"

**Cause:** Xcode references a file that doesn't exist on disk

**Fix:**
1. In Project Navigator, look for files in **red** (missing)
2. Right-click red files and choose "Delete" → "Remove Reference"
3. Re-add the correct files (see Step 5)
4. Clean derived data and rebuild

---

## ✅ Verification Checklist

After build succeeds, verify:

- [ ] No errors in the Issue Navigator (⌘5)
- [ ] "Build Succeeded" message appears
- [ ] AutomationModels.swift is visible in project
- [ ] No Models.swift in the App folder
- [ ] All Swift files have target membership checked
- [ ] Product → Run (⌘R) launches the app
- [ ] Menu bar icon appears (house icon)

---

## 🎉 Success!

Once the build succeeds:

1. **Run the app** (⌘R)
2. Look for the **house icon** in your menu bar
3. Click it to verify the menu appears
4. Choose "Show Automations…" to open the main window

---

## 📝 What Changed?

The key changes to fix the build:

1. **Models.swift → AutomationModels.swift** - Renamed to avoid conflicts with Swift Package Manager's HomeKitCore/Models.swift
2. **Added AutomationStore.swift** - Missing data store implementation
3. **Added SocketConstants.swift** - Missing socket configuration
4. **Organized files properly** - All Swift files must be in the Xcode target

---

## 🆘 Still Having Issues?

If you're still stuck after following all steps:

1. **Close Xcode** (⌘Q)
2. **Delete everything and start fresh:**
   ```bash
   # In Terminal, from your project directory:
   rm -rf ~/Library/Developer/Xcode/DerivedData/*
   rm -rf .swiftpm
   rm -rf *.xcworkspace
   ```
3. **Reopen the .xcodeproj file**
4. **Follow Steps 5-8 again**

---

**Need help?** Check the console output (⌘⇧Y) for specific error messages.
