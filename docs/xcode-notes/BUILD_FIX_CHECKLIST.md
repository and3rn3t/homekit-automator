# Xcode Build Fix Checklist

Use this checklist to track your progress fixing the build:

## Pre-Flight Checks
- [ ] I have Xcode installed
- [ ] I'm in the correct project directory
- [ ] I've read START_HERE.md

## Option A: Automated Script
- [ ] Opened Terminal in project directory
- [ ] Made script executable: `chmod +x scripts/fix-xcode.sh`
- [ ] Ran the script: `./scripts/fix-xcode.sh`
- [ ] Script completed successfully
- [ ] Followed the "Next steps" shown by the script

## Option B: Manual Steps (if script doesn't work)
- [ ] Closed Xcode (⌘Q)
- [ ] Deleted derived data manually
- [ ] Removed any Models.swift files (kept AutomationModels.swift)
- [ ] Verified all 13 required Swift files exist
- [ ] Reopened Xcode

## In Xcode - Required Steps
- [ ] File → Packages → Reset Package Caches
- [ ] File → Packages → Resolve Package Versions  
- [ ] Waited for package resolution to complete
- [ ] Product → Clean Build Folder (⌘⇧K)
- [ ] Product → Build (⌘B)

## Verification
- [ ] Build succeeded (no red errors)
- [ ] Issue Navigator (⌘5) is empty
- [ ] Product → Run (⌘R) launches the app
- [ ] Menu bar icon appears (house icon)
- [ ] Can click icon and see menu
- [ ] "Show Automations…" opens a window

## File Target Membership (if build fails)
For EACH Swift file, verify in File Inspector (⌘⌥1):
- [ ] HomeKitAutomatorApp.swift - target checked
- [ ] AppDelegate.swift - target checked
- [ ] ContentView.swift - target checked
- [ ] AutomationModels.swift - target checked
- [ ] AutomationStore.swift - target checked
- [ ] DashboardView.swift - target checked
- [ ] HistoryView.swift - target checked
- [ ] SettingsView.swift - target checked
- [ ] AppSettings.swift - target checked
- [ ] HelperManager.swift - target checked
- [ ] SocketConstants.swift - target checked
- [ ] AutomationListItem.swift - target checked
- [ ] LogEntryRow.swift - target checked

## Troubleshooting (if still failing)
- [ ] Checked specific error message in Issue Navigator
- [ ] Searched for error in XCODE_ORGANIZATION_GUIDE.md
- [ ] Verified NO Models.swift exists (only AutomationModels.swift)
- [ ] Tried the "Nuclear Option" from the guide
- [ ] Checked Console.app for runtime errors

## Success! 🎉
- [ ] Build succeeded
- [ ] App runs without crashing
- [ ] All features work
- [ ] Ready to continue development

---

**Current Status:** _________________________________________

**Notes:** _________________________________________

_________________________________________

_________________________________________
