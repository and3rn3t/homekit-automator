#!/usr/bin/env bash
# test-automation-flow.sh
# Script to test the HomeKit Automator app end-to-end

set -euo pipefail

echo "🧪 HomeKit Automator - Test Script"
echo "=================================="
echo ""

# Configuration
APP_SUPPORT="$HOME/Library/Application Support/homekit-automator"
AUTOMATIONS_FILE="$APP_SUPPORT/automations.json"
LOG_FILE="$APP_SUPPORT/logs/automation-log.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
success() {
    echo -e "${GREEN}✓${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

info() {
    echo "ℹ️  $1"
}

# Test 1: Check directories exist
test_directories() {
    echo "Test 1: Checking directory structure..."
    
    if [ -d "$APP_SUPPORT" ]; then
        success "App Support directory exists"
    else
        warning "App Support directory missing (will be created on first run)"
    fi
    
    if [ -f "$AUTOMATIONS_FILE" ]; then
        success "Automations file exists"
        echo "   Found $(jq '. | length' "$AUTOMATIONS_FILE" 2>/dev/null || echo "0") automations"
    else
        warning "No automations file (normal for first run)"
    fi
    
    echo ""
}

# Test 2: Validate JSON structure
test_json_validity() {
    echo "Test 2: Validating JSON structure..."
    
    if [ -f "$AUTOMATIONS_FILE" ]; then
        if jq empty "$AUTOMATIONS_FILE" 2>/dev/null; then
            success "Automations JSON is valid"
        else
            error "Automations JSON is invalid!"
            return 1
        fi
    else
        info "No automations file to validate"
    fi
    
    if [ -f "$LOG_FILE" ]; then
        if jq empty "$LOG_FILE" 2>/dev/null; then
            success "Log JSON is valid"
        else
            error "Log JSON is invalid!"
            return 1
        fi
    else
        info "No log file to validate"
    fi
    
    echo ""
}

# Test 3: Create sample automation
test_create_automation() {
    echo "Test 3: Creating sample automation..."
    
    # Ensure directory exists
    mkdir -p "$APP_SUPPORT"
    
    # Create sample automation
    SAMPLE_AUTOMATION='{
  "id": "test-automation-1",
  "name": "Test Morning Lights",
  "description": "Test automation for debugging",
  "trigger": {
    "type": "schedule",
    "humanReadable": "Every day at 7:00 AM",
    "cron": "0 7 * * *",
    "timezone": "America/Los_Angeles"
  },
  "conditions": null,
  "actions": [
    {
      "type": "control",
      "deviceUuid": "test-device-uuid",
      "deviceName": "Test Light",
      "room": "Bedroom",
      "characteristic": "On",
      "value": true,
      "delaySeconds": 0,
      "sceneName": null,
      "sceneUuid": null
    }
  ],
  "enabled": true,
  "shortcutName": "Test Morning Lights",
  "createdAt": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'",
  "lastRun": null
}'
    
    # Read existing automations or create empty array
    if [ -f "$AUTOMATIONS_FILE" ]; then
        EXISTING=$(cat "$AUTOMATIONS_FILE")
    else
        EXISTING="[]"
    fi
    
    # Add new automation (if not already present)
    if echo "$EXISTING" | jq -e '.[] | select(.id == "test-automation-1")' > /dev/null 2>&1; then
        info "Test automation already exists"
    else
        echo "$EXISTING" | jq ". + [$SAMPLE_AUTOMATION]" > "$AUTOMATIONS_FILE"
        success "Created test automation"
    fi
    
    echo ""
}

# Test 4: Read automation
test_read_automation() {
    echo "Test 4: Reading automations..."
    
    if [ -f "$AUTOMATIONS_FILE" ]; then
        COUNT=$(jq '. | length' "$AUTOMATIONS_FILE")
        success "Found $COUNT automation(s)"
        
        # Show details
        jq -r '.[] | "   • \(.name) (\(.enabled | if . then "enabled" else "disabled" end))"' "$AUTOMATIONS_FILE"
    else
        error "No automations file found"
        return 1
    fi
    
    echo ""
}

# Test 5: Create log entry
test_create_log_entry() {
    echo "Test 5: Creating test log entry..."
    
    LOG_DIR="$APP_SUPPORT/logs"
    mkdir -p "$LOG_DIR"
    
    LOG_ENTRY='{
  "automationId": "test-automation-1",
  "automationName": "Test Morning Lights",
  "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'",
  "actionsExecuted": 1,
  "succeeded": 1,
  "failed": 0,
  "errors": null
}'
    
    # Read existing logs or create empty array
    if [ -f "$LOG_FILE" ]; then
        EXISTING_LOGS=$(cat "$LOG_FILE")
    else
        EXISTING_LOGS="[]"
    fi
    
    # Add log entry
    echo "$EXISTING_LOGS" | jq ". + [$LOG_ENTRY]" > "$LOG_FILE"
    success "Created test log entry"
    
    echo ""
}

# Test 6: Check socket
test_socket() {
    echo "Test 6: Checking Unix domain socket..."
    
    SOCKET_PATH="$APP_SUPPORT/homekitauto.sock"
    
    if [ -S "$SOCKET_PATH" ]; then
        success "Socket exists at $SOCKET_PATH"
        
        # Try to connect (requires helper running)
        if nc -U -z "$SOCKET_PATH" 2>/dev/null; then
            success "Socket is accepting connections"
        else
            warning "Socket exists but not accepting connections (helper may not be running)"
        fi
    else
        warning "Socket not found (helper not running)"
    fi
    
    echo ""
}

# Test 7: Check helper process
test_helper_process() {
    echo "Test 7: Checking helper process..."
    
    if pgrep -x "HomeKitHelper" > /dev/null; then
        success "HomeKitHelper process is running"
        PID=$(pgrep -x "HomeKitHelper")
        info "PID: $PID"
    else
        warning "HomeKitHelper process not running"
    fi
    
    echo ""
}

# Test 8: Backup current data
test_backup() {
    echo "Test 8: Creating backup..."
    
    if [ -d "$APP_SUPPORT" ]; then
        BACKUP_DIR="$APP_SUPPORT/backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        
        if [ -f "$AUTOMATIONS_FILE" ]; then
            cp "$AUTOMATIONS_FILE" "$BACKUP_DIR/"
            success "Backed up automations"
        fi
        
        if [ -f "$LOG_FILE" ]; then
            cp "$LOG_FILE" "$BACKUP_DIR/"
            success "Backed up logs"
        fi
        
        info "Backup created at: $BACKUP_DIR"
    else
        info "No data to backup"
    fi
    
    echo ""
}

# Test 9: Simulate automation toggle
test_toggle_automation() {
    echo "Test 9: Testing automation toggle..."
    
    if [ -f "$AUTOMATIONS_FILE" ]; then
        # Toggle first automation
        UPDATED=$(jq '.[0].enabled = (.[0].enabled | not)' "$AUTOMATIONS_FILE")
        echo "$UPDATED" > "$AUTOMATIONS_FILE"
        
        NEW_STATE=$(jq -r '.[0].enabled' "$AUTOMATIONS_FILE")
        success "Toggled automation to: $NEW_STATE"
    else
        error "No automations to toggle"
        return 1
    fi
    
    echo ""
}

# Test 10: Cleanup test data
test_cleanup() {
    echo "Test 10: Cleaning up test data..."
    
    if [ -f "$AUTOMATIONS_FILE" ]; then
        # Remove test automation
        UPDATED=$(jq 'map(select(.id != "test-automation-1"))' "$AUTOMATIONS_FILE")
        echo "$UPDATED" > "$AUTOMATIONS_FILE"
        success "Removed test automation"
    fi
    
    if [ -f "$LOG_FILE" ]; then
        # Remove test log entries
        UPDATED_LOGS=$(jq 'map(select(.automationId != "test-automation-1"))' "$LOG_FILE")
        echo "$UPDATED_LOGS" > "$LOG_FILE"
        success "Removed test log entries"
    fi
    
    echo ""
}

# Main test runner
run_tests() {
    echo "Starting test suite..."
    echo ""
    
    FAILED=0
    
    test_directories || FAILED=$((FAILED + 1))
    test_json_validity || FAILED=$((FAILED + 1))
    test_socket
    test_helper_process
    test_backup
    
    # Interactive tests (ask user first)
    read -p "Create test automation? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        test_create_automation || FAILED=$((FAILED + 1))
        test_read_automation || FAILED=$((FAILED + 1))
        test_create_log_entry || FAILED=$((FAILED + 1))
        test_toggle_automation || FAILED=$((FAILED + 1))
        
        read -p "Clean up test data? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            test_cleanup
        fi
    fi
    
    echo ""
    echo "=================================="
    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
    else
        echo -e "${RED}✗ $FAILED test(s) failed${NC}"
    fi
    echo "=================================="
}

# Check for jq
if ! command -v jq &> /dev/null; then
    error "jq is required but not installed"
    echo "Install with: brew install jq"
    exit 1
fi

# Run all tests
run_tests
