#!/bin/bash

# fix-xcode-project.sh
# Automated script to fix common Xcode project organization issues

set -e

echo "🔧 HomeKit Automator - Xcode Project Fix Script"
echo "================================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo "ℹ️  $1"
}

# Check if we're in the right directory
if [ ! -f "HomeKitAutomatorApp.swift" ]; then
    print_error "HomeKitAutomatorApp.swift not found!"
    print_info "Please run this script from your project's root directory."
    exit 1
fi

print_success "Found project files"
echo ""

# Step 1: Check for conflicting Models.swift
echo "Step 1: Checking for conflicting Models.swift files..."
MODELS_FILES=$(find . -name "Models.swift" -type f 2>/dev/null)

if [ ! -z "$MODELS_FILES" ]; then
    print_warning "Found old Models.swift file(s):"
    echo "$MODELS_FILES"
    echo ""
    read -p "Delete these files? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        while IFS= read -r file; do
            rm "$file"
            print_success "Deleted: $file"
        done <<< "$MODELS_FILES"
    else
        print_warning "Skipping deletion. Build may fail!"
    fi
else
    print_success "No conflicting Models.swift files found"
fi
echo ""

# Step 2: Verify AutomationModels.swift exists
echo "Step 2: Verifying AutomationModels.swift exists..."
if [ -f "AutomationModels.swift" ]; then
    print_success "AutomationModels.swift found"
else
    print_error "AutomationModels.swift is missing!"
    print_info "This file should have been created. Please check your project."
    exit 1
fi
echo ""

# Step 3: Verify all required files exist
echo "Step 3: Checking for required Swift files..."
REQUIRED_FILES=(
    "HomeKitAutomatorApp.swift"
    "AppDelegate.swift"
    "ContentView.swift"
    "AutomationModels.swift"
    "AutomationStore.swift"
    "DashboardView.swift"
    "HistoryView.swift"
    "SettingsView.swift"
    "AppSettings.swift"
    "HelperManager.swift"
    "SocketConstants.swift"
    "AutomationListItem.swift"
    "LogEntryRow.swift"
)

MISSING_FILES=()

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        print_success "$file"
    else
        print_error "$file is MISSING"
        MISSING_FILES+=("$file")
    fi
done

if [ ${#MISSING_FILES[@]} -ne 0 ]; then
    echo ""
    print_warning "Some files are missing. Please add them to your project."
    exit 1
fi
echo ""

# Step 4: Clean Derived Data
echo "Step 4: Cleaning Xcode Derived Data..."
DERIVED_DATA_PATH="$HOME/Library/Developer/Xcode/DerivedData"

if [ -d "$DERIVED_DATA_PATH" ]; then
    # Find HomeKit Automator derived data folders
    HOMEKIT_DD=$(find "$DERIVED_DATA_PATH" -maxdepth 1 -name "HomeKitAutomator-*" -o -name "HomeKit*" 2>/dev/null)
    
    if [ ! -z "$HOMEKIT_DD" ]; then
        echo "Found derived data folders:"
        echo "$HOMEKIT_DD"
        echo ""
        read -p "Delete these folders? (y/n) " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            while IFS= read -r folder; do
                if [ ! -z "$folder" ]; then
                    rm -rf "$folder"
                    print_success "Deleted: $(basename $folder)"
                fi
            done <<< "$HOMEKIT_DD"
        else
            print_warning "Skipping derived data cleanup"
        fi
    else
        print_info "No HomeKit Automator derived data found"
    fi
else
    print_warning "Derived Data directory not found"
fi
echo ""

# Step 5: Clean Swift Package Manager cache
echo "Step 5: Cleaning Swift Package Manager cache..."
if [ -d ".swiftpm" ]; then
    rm -rf .swiftpm
    print_success "Removed .swiftpm directory"
else
    print_info "No .swiftpm directory found"
fi

if [ -d ".build" ]; then
    rm -rf .build
    print_success "Removed .build directory"
else
    print_info "No .build directory found"
fi
echo ""

# Step 6: Summary
echo "================================================"
echo "✨ Cleanup Complete!"
echo ""
print_info "Next steps:"
echo "  1. Open your project in Xcode"
echo "  2. File → Packages → Reset Package Caches"
echo "  3. File → Packages → Resolve Package Versions"
echo "  4. Product → Clean Build Folder (⌘⇧K)"
echo "  5. Product → Build (⌘B)"
echo ""
print_success "Your project should now build successfully!"
echo ""
