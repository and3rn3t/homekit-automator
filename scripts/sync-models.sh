#!/usr/bin/env bash
# sync-models.sh — Verifies that the Xcode app's AutomationModels.swift stays in
# sync with the canonical HomeKitCore/Models.swift + HomeKitCore/AnyCodableValue.swift.
#
# Usage:
#   ./scripts/sync-models.sh          # Check mode (CI) — exits 0 if in sync, 1 if diverged
#   ./scripts/sync-models.sh --update # Regenerate AutomationModels.swift from canonical sources
#
# The check strips doc comments, 'public' access modifiers, and Hashable conformance
# before comparing, so only structural differences (types, properties, methods) are flagged.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CANONICAL="$REPO_ROOT/scripts/swift/Sources/HomeKitCore/Models.swift"
CANONICAL_ACV="$REPO_ROOT/scripts/swift/Sources/HomeKitCore/AnyCodableValue.swift"
COPY="$REPO_ROOT/HomeKit Automator/HomeKit Automator/Models/AutomationModels.swift"

# Strip doc comments (/// lines), multi-line /** */ blocks, blank lines after stripping,
# 'public ' access modifiers, and normalize whitespace for comparison.
normalize() {
    sed -E \
        -e 's/^[[:space:]]*\/\/\/.*$//'   \
        -e 's/^[[:space:]]*\/\/[[:space:]]MARK:.*$//' \
        -e '/^[[:space:]]*$/d'            \
        -e 's/public //g'                 \
        -e 's/nonisolated\(unsafe\) //g'  \
        -e 's/, Hashable//g'              \
        -e '/^import /d'                  \
        -e 's/^[[:space:]]+//'            \
        -e 's/[[:space:]]+$//'            \
        "$1" | grep -v '^//' | grep -v '^$'
}

if [[ "${1:-}" == "--update" ]]; then
    echo "Regenerating $COPY from canonical sources..."

    HEADER='// HomeKitAutomator — This file should match HomeKitCore/Models.swift and
// HomeKitCore/AnyCodableValue.swift — do not edit independently.
//
// This is a copy of the canonical models from Sources/HomeKitCore/.
// HomeKitAutomator is built via Xcode/XcodeGen and cannot import the SPM HomeKitCore
// module directly. Keep this file in sync with the canonical versions.'

    {
        echo "$HEADER"
        echo ""
        echo "import Foundation"
        echo ""
        # Extract sharedISO8601Formatter (simplified doc comment)
        echo "/// A shared ISO 8601 date formatter for efficient reuse. Thread-safe once created."
        echo "nonisolated(unsafe) let sharedISO8601Formatter = ISO8601DateFormatter()"
        echo ""
        # Process Models.swift: strip header, imports, formatter, doc comments, public
        sed -E \
            -e '1,/^import Foundation/d'           \
            -e '/sharedISO8601Formatter/d'         \
            -e 's/^[[:space:]]*\/\/\/.*$//'        \
            -e '/^$/N;/^\n$/d'                     \
            -e 's/public //g'                      \
            "$CANONICAL" | sed '/^$/N;/^\n$/d'
        echo ""
        echo "// MARK: - AnyCodableValue"
        echo ""
        # Process AnyCodableValue.swift: strip header, imports
        echo "/// A type-erased Codable value supporting JSON primitives."
        echo "/// This should match the canonical version in HomeKitCore/AnyCodableValue.swift."
        sed -E \
            -e '1,/^import Foundation/d'           \
            -e 's/^[[:space:]]*\/\/\/.*$//'        \
            -e '/^$/N;/^\n$/d'                     \
            -e 's/public //g'                      \
            "$CANONICAL_ACV" | sed '/^$/N;/^\n$/d'
    } > "$COPY"

    echo "Done. Review the generated file and commit."
    exit 0
fi

# Check mode: compare normalized structures
echo "Checking Models.swift sync..."

NORM_CANONICAL=$(mktemp)
NORM_COPY=$(mktemp)
trap 'rm -f "$NORM_CANONICAL" "$NORM_COPY"' EXIT

# Normalize canonical = Models.swift + AnyCodableValue.swift
{ normalize "$CANONICAL"; normalize "$CANONICAL_ACV"; } > "$NORM_CANONICAL"

# Normalize copy (includes AnyCodableValue inline)
normalize "$COPY" > "$NORM_COPY"

if diff -q "$NORM_CANONICAL" "$NORM_COPY" > /dev/null 2>&1; then
    echo "✓ Models.swift files are in sync"
    exit 0
else
    echo "✗ Models.swift files have diverged!"
    echo ""
    echo "Structural differences (after stripping comments/access modifiers):"
    diff --unified=3 "$NORM_CANONICAL" "$NORM_COPY" || true
    echo ""
    echo "To fix: update the canonical file in HomeKitCore/ and run:"
    echo "  ./scripts/sync-models.sh --update"
    exit 1
fi
