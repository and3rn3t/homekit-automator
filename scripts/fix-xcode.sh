#!/usr/bin/env bash
# fix-xcode.sh — Fix common Xcode build errors for HomeKit Automator
#
# This script consolidates the previous fix-build.sh and fix-xcode-project.sh
# into a single tool that:
#   1. Removes conflicting Models.swift files (replaced by AutomationModels.swift)
#   2. Verifies all required Swift source files exist
#   3. Cleans Xcode DerivedData for this project
#   4. Clears Swift Package Manager caches
#
# Usage:
#   ./scripts/fix-xcode.sh                # Interactive — prompts before destructive actions
#   ./scripts/fix-xcode.sh --force         # Non-interactive — deletes without prompting
#
# Run from the repository root, or the script will locate it automatically.

set -euo pipefail

# ─── Locate the project ──────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

# ─── Colors ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
err()  { echo -e "${RED}❌ $1${NC}"; }
info() { echo "ℹ️  $1"; }

confirm_or_skip() {
    if $FORCE; then return 0; fi
    read -p "$1 (y/n): " -n 1 -r; echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

echo "🔧 HomeKit Automator — Xcode Build Fix"
echo "======================================="
echo "   Project root: $PROJECT_ROOT"
echo ""

# ─── Step 1: Remove conflicting Models.swift ─────────────────────────────────

echo "Step 1: Checking for conflicting Models.swift files..."

XCODE_APP_DIR="$PROJECT_ROOT/HomeKit Automator/HomeKit Automator"
CONFLICTS=()

# Known conflict locations
for candidate in \
    "$XCODE_APP_DIR/App/Models.swift" \
    "$XCODE_APP_DIR/Models.swift"; do
    [[ -f "$candidate" ]] && CONFLICTS+=("$candidate")
done

# Broad search as backup
while IFS= read -r -d '' f; do
    # Skip canonical HomeKitCore/Models.swift (SPM source — not a conflict)
    [[ "$f" == *"HomeKitCore/Models.swift" ]] && continue
    # Deduplicate
    for c in "${CONFLICTS[@]:-}"; do [[ "$c" == "$f" ]] && continue 2; done
    CONFLICTS+=("$f")
done < <(find "$XCODE_APP_DIR" -name "Models.swift" -print0 2>/dev/null || true)

if [[ ${#CONFLICTS[@]} -gt 0 ]]; then
    warn "Found conflicting Models.swift file(s):"
    for f in "${CONFLICTS[@]}"; do echo "   $f"; done
    if confirm_or_skip "Delete these files?"; then
        for f in "${CONFLICTS[@]}"; do rm "$f" && ok "Deleted: $f"; done
    else
        warn "Skipping deletion — build may still fail."
    fi
else
    ok "No conflicting Models.swift files found"
fi
echo ""

# ─── Step 2: Verify required Swift files ─────────────────────────────────────

echo "Step 2: Verifying required Swift source files..."

REQUIRED_FILES=(
    HomeKitAutomatorApp.swift
    AppDelegate.swift
    ContentView.swift
    AutomationModels.swift
    AutomationStore.swift
    DashboardView.swift
    HistoryView.swift
    SettingsView.swift
    AppSettings.swift
    HelperManager.swift
    SocketConstants.swift
    AutomationListItem.swift
    LogEntryRow.swift
)

MISSING=()
for name in "${REQUIRED_FILES[@]}"; do
    if find "$XCODE_APP_DIR" -name "$name" -print -quit | grep -q .; then
        ok "$name"
    else
        err "$name — MISSING"
        MISSING+=("$name")
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo ""
    warn "${#MISSING[@]} required file(s) missing. Add them before building."
fi
echo ""

# ─── Step 3: Clean Xcode DerivedData ─────────────────────────────────────────

echo "Step 3: Cleaning Xcode DerivedData..."

DERIVED="$HOME/Library/Developer/Xcode/DerivedData"
if [[ -d "$DERIVED" ]]; then
    MATCHES=$(find "$DERIVED" -maxdepth 1 \( -name "HomeKit*Automator*" -o -name "HomeKitAutomator-*" \) -type d 2>/dev/null || true)
    if [[ -n "$MATCHES" ]]; then
        echo "$MATCHES"
        if confirm_or_skip "Delete these DerivedData folders?"; then
            while IFS= read -r d; do
                [[ -n "$d" ]] && rm -rf "$d" && ok "Deleted: $(basename "$d")"
            done <<< "$MATCHES"
        else
            warn "Skipping DerivedData cleanup"
        fi
    else
        info "No HomeKit Automator DerivedData found"
    fi
else
    info "DerivedData directory not found"
fi
echo ""

# ─── Step 4: Clean SPM caches ────────────────────────────────────────────────

echo "Step 4: Cleaning Swift Package Manager caches..."

for dir in "$PROJECT_ROOT/.swiftpm" "$XCODE_APP_DIR/.swiftpm" "$XCODE_APP_DIR/.build"; do
    if [[ -d "$dir" ]]; then
        rm -rf "$dir" && ok "Removed $dir"
    fi
done
info "SPM caches cleaned"
echo ""

# ─── Done ─────────────────────────────────────────────────────────────────────

echo "======================================="
echo "✨ Fix complete!"
echo ""
info "Next steps in Xcode:"
echo "  1. File → Packages → Reset Package Caches"
echo "  2. File → Packages → Resolve Package Versions"
echo "  3. Product → Clean Build Folder (⌘⇧K)"
echo "  4. Product → Build (⌘B)"
echo ""
ok "Your project should now build successfully!"
