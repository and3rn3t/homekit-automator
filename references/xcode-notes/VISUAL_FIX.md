# 🎯 VISUAL GUIDE: Fix Build in 3 Clicks

## Your Current Situation:

```
❌ ERROR: Filename "Models.swift" used twice
```

---

## 🎬 Step-by-Step (With Pictures)

### Step 1: Find the File

**In Xcode's left sidebar:**

```
📁 HomeKit Automator
  └── 📁 App
       ├── 📄 HomeKitAutomatorApp.swift
       ├── 📄 AppDelegate.swift
       ├── 📄 ContentView.swift
       ├── 📄 Models.swift          👈 FIND THIS ONE
       ├── 📄 AutomationStore.swift
       └── ...
```

**Click on** → `Models.swift`

---

### Step 2: Rename It

**Method A: Keyboard (Fastest)**
1. Select `Models.swift`
2. Press **ENTER** key
3. Type: `AutomationModels.swift`
4. Press **ENTER** again

**Method B: Right-Click**
1. Right-click `Models.swift`
2. Choose "Rename"
3. Type: `AutomationModels.swift`
4. Press **ENTER**

---

### Step 3: Clean + Build

1. **Clean:** Press `⌘` + `⇧` + `K`
2. **Build:** Press `⌘` + `B`

**Wait for:** ✅ Build Succeeded

---

## ✅ After Renaming:

```
📁 HomeKit Automator
  └── 📁 App
       ├── 📄 HomeKitAutomatorApp.swift
       ├── 📄 AppDelegate.swift
       ├── 📄 ContentView.swift
       ├── 📄 AutomationModels.swift   👈 RENAMED! ✅
       ├── 📄 AutomationStore.swift
       └── ...
```

**No more `Models.swift` in the App folder!**

---

## 🎉 Success Looks Like:

**Build output:**
```
✅ Build Succeeded
   
   [timestamp] Build time: X.Xs
```

**No errors in the Issue Navigator!**

---

## 🚀 Then Run It:

Press `⌘` + `R` to run the app

**You should see:**
- 🏠 Menu bar icon appears
- Click it → Menu opens
- "Show Automations…" is there
- App runs without crashing

---

## ⚠️ Troubleshooting

### If rename button is grayed out:

**File is locked or part of wrong target**

**Solution:**
1. Quit Xcode (`⌘Q`)
2. In **Terminal**:
   ```bash
   cd ~/Documents/GitHub/homekit-automator/HomeKit\ Automator/App
   mv Models.swift AutomationModels.swift
   ```
3. Reopen Xcode
4. Right-click the **red** `Models.swift` → Delete → Remove Reference
5. Right-click "App" folder → Add Files → Select `AutomationModels.swift`
6. Build (`⌘B`)

---

### If Xcode shows both files:

**Both files are now in the project**

**Solution:**
1. Delete the OLD one (the one that says `Models.swift`)
2. Keep the NEW one (`AutomationModels.swift`)
3. Clean and build

---

### If build still fails with "Models.swift used twice":

**Xcode hasn't refreshed**

**Solution:**
1. Quit Xcode completely (`⌘Q`)
2. Delete derived data:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/HomeKit*Automator*
   ```
3. Reopen Xcode
4. Build (`⌘B`)

---

## 📝 Quick Reference Card

| Action | Keyboard Shortcut |
|--------|------------------|
| Rename file | Select + **ENTER** |
| Clean build | **⌘⇧K** |
| Build | **⌘B** |
| Run | **⌘R** |
| Quit Xcode | **⌘Q** |

---

## ✅ Checklist

- [ ] Found `Models.swift` in Project Navigator
- [ ] Renamed it to `AutomationModels.swift`
- [ ] Cleaned build folder (⌘⇧K)
- [ ] Built project (⌘B)
- [ ] Build succeeded ✅
- [ ] Ran app (⌘R)
- [ ] Menu bar icon appeared ✅

---

**That's it! Simple rename = build fixed!** 🎊

**Need more help?** See `FIX_BUILD.md` or `RENAME_FILE.md`
