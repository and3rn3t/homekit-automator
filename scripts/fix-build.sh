#!/bin/bash
# fix-build.sh
# Script to fix the HomeKit Automator build errors

set -e

echo "🔧 HomeKit Automator Build Fix Script"
echo "======================================"
echo ""

# Get the script's directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$SCRIPT_DIR"

echo "📁 Project root: $PROJECT_ROOT"
echo ""

# Check if Models.swift exists in the App directory
MODELS_PATH="$PROJECT_ROOT/HomeKit Automator/App/Models.swift"
if [ -f "$MODELS_PATH" ]; then
    echo "❌ Found conflicting Models.swift file:"
    echo "   $MODELS_PATH"
    echo ""
    read -p "🗑️  Delete this file? (y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm "$MODELS_PATH"
        echo "✅ Deleted Models.swift"
    else
        echo "⚠️  Skipping deletion. Build will still fail."
    fi
else
    echo "✅ Models.swift already removed"
fi
echo ""

# Check if AutomationModels.swift exists
AUTOMATION_MODELS_PATH="$PROJECT_ROOT/AutomationModels.swift"
if [ ! -f "$AUTOMATION_MODELS_PATH" ]; then
    # Try other possible locations
    AUTOMATION_MODELS_PATH="$PROJECT_ROOT/HomeKit Automator/App/AutomationModels.swift"
fi

if [ -f "$AUTOMATION_MODELS_PATH" ]; then
    echo "✅ AutomationModels.swift found at:"
    echo "   $AUTOMATION_MODELS_PATH"
else
    echo "⚠️  AutomationModels.swift not found!"
    echo "   Make sure it was created in the project root."
fi
echo ""

# Clean build folder
echo "🧹 Cleaning build artifacts..."
if [ -d "$HOME/Library/Developer/Xcode/DerivedData/HomeKit_Automator-fmcpxidbypygkzduasrhielzirwy" ]; then
    rm -rf "$HOME/Library/Developer/Xcode/DerivedData/HomeKit_Automator-fmcpxidbypygkzduasrhielzirwy"
    echo "   ✅ Cleaned HomeKit_Automator DerivedData"
fi

if [ -d "$HOME/Library/Developer/Xcode/DerivedData/HomeKitAutomator-bshbmozhwqlyjqckkfgrxlwcwtyu" ]; then
    rm -rf "$HOME/Library/Developer/Xcode/DerivedData/HomeKitAutomator-bshbmozhwqlyjqckkfgrxlwcwtyu"
    echo "   ✅ Cleaned HomeKitAutomator DerivedData"
fi

# Clean all DerivedData for safety
echo "   🗑️  Cleaning all HomeKit Automator DerivedData folders..."
rm -rf "$HOME/Library/Developer/Xcode/DerivedData/"HomeKit*Automator*
echo "   ✅ All build artifacts cleaned"
echo ""

echo "✅ Build fix complete!"
echo ""
echo "📝 Next steps in Xcode:"
echo "   1. Open your project in Xcode"
echo "   2. If Models.swift still appears in the file navigator:"
echo "      - Right-click it → Delete → Move to Trash"
echo "   3. If AutomationModels.swift is not in the project:"
echo "      - Right-click your app folder → Add Files to 'HomeKit Automator'"
echo "      - Select AutomationModels.swift"
echo "      - ✅ Check 'HomeKit Automator' target"
echo "   4. Product → Clean Build Folder (⌘⇧K)"
echo "   5. Product → Build (⌘B)"
echo ""
echo "🎉 Your project should now build successfully!"
