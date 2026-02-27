# 🚀 IMMEDIATE FIX - Run This Now

## The Problem
Your build is failing because `Models.swift` exists in TWO places:
1. `HomeKit Automator/App/Models.swift` ← In your app
2. `scripts/swift/Sources/HomeKitCore/Models.swift` ← In Swift Package

Both files are being compiled, causing a collision.

---

## ✅ THE SOLUTION (Do This Right Now)

### Step 1: In Xcode - Rename the File

1. **Find `Models.swift`** in the Project Navigator (left sidebar)
   - It should be under "HomeKit Automator" → "App" folder

2. **Click on `Models.swift`** to select it

3. **Press ENTER** (or right-click → Rename)

4. **Change the name from:**
   ```
   Models.swift
   ```
   **To:**
   ```
   AutomationModels.swift
   ```

5. **Press ENTER** to confirm

**That's it!** This fixes the name collision.

---

### Step 2: Clean and Build

1. **Clean:** Press **⌘⇧K** (Product → Clean Build Folder)

2. **Build:** Press **⌘B** (Product → Build)

**Expected:** ✅ Build Succeeded

---

## 🎉 Alternative: If Rename Doesn't Work

If you can't rename in Xcode, do this:

### In Terminal:

```bash
cd ~/Documents/GitHub/homekit-automator

# Navigate to the app folder  
cd "HomeKit Automator/App"

# Rename the file
mv Models.swift AutomationModels.swift

# Go back to project root
cd ../..

# Clean derived data
rm -rf ~/Library/Developer/Xcode/DerivedData/HomeKit*Automator*
```

### Then in Xcode:

1. You'll see Xcode marks `Models.swift` as missing (red text)
2. **Right-click the red `Models.swift`** → **Delete** → **Remove Reference**
3. **Right-click "App" folder** → **Add Files to "HomeKit Automator"**
4. Select **`AutomationModels.swift`**
5. ✅ Check "HomeKit Automator" target
6. Click **Add**
7. **Clean** (⌘⇧K) and **Build** (⌘B)

---

## 🔍 Verify It Worked

After renaming, you should see in Project Navigator:
```
HomeKit Automator/
└── App/
    ├── HomeKitAutomatorApp.swift
    ├── AppDelegate.swift
    ├── ContentView.swift
    ├── AutomationModels.swift  ✅ (formerly Models.swift)
    ├── AutomationStore.swift
    └── ... other files
```

**And NO file named `Models.swift` in the App folder!**

---

## ✅ Test It

1. Build succeeds (⌘B) ✅
2. Run the app (⌘R) ✅
3. Menu bar icon appears ✅
4. Click icon → "Show Automations…" works ✅

---

## 🆘 If Still Failing

### Error: "Cannot find RegisteredAutomation"

**Fix:** The renamed file isn't in the build target

1. Select `AutomationModels.swift`
2. Open File Inspector (⌘⌥1)
3. Under "Target Membership", check ✅ "HomeKit Automator"
4. Build again

---

### Error: Still see "Models.swift used twice"

**Fix:** Xcode's cache is stale

1. **Quit Xcode completely** (⌘Q)
2. **Delete derived data:**
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/*
   ```
3. **Reopen Xcode**
4. **Build** (⌘B)

---

## 💡 Why This Works

- **Before:** Both `Models.swift` files compiled → collision
- **After:** Only one `Models.swift` (in Swift Package) + `AutomationModels.swift` (in app) → no collision
- **Content is identical**, just different filename

---

## 🎯 Do This Now:

1. ✅ Rename `Models.swift` to `AutomationModels.swift` in Xcode
2. ✅ Clean (⌘⇧K)
3. ✅ Build (⌘B)
4. ✅ Run (⌘R)

**Total time: 30 seconds** ⏱️

---

**Still stuck?** Read `FIX_BUILD.md` for more detailed troubleshooting.
