#!/bin/bash
# ROBOTERM build script
# Usage: ./scripts/build.sh [--install] [--run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "=== ROBOTERM Build ==="

# Generate Xcode project
echo "[1/3] Generating Xcode project..."
xcodegen generate 2>&1 | tail -1

# Build
echo "[2/3] Building..."
xcodebuild -project roboterm.xcodeproj -scheme roboterm -configuration Debug build 2>&1 | tail -3

# Find the built app
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/roboterm-*/Build/Products/Debug/ROBOTERM.app -maxdepth 0 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
    echo "ERROR: Build output not found"
    exit 1
fi

echo "Built: $APP_PATH"

# Install to /Applications
if [[ "${1:-}" == "--install" ]] || [[ "${2:-}" == "--install" ]]; then
    echo "[3/3] Installing to /Applications..."
    rm -rf /Applications/ROBOTERM.app
    cp -a "$APP_PATH" /Applications/ROBOTERM.app
    codesign --force --deep --sign - /Applications/ROBOTERM.app 2>/dev/null
    echo "Installed: /Applications/ROBOTERM.app"
    APP_PATH="/Applications/ROBOTERM.app"
fi

# Run
if [[ "${1:-}" == "--run" ]] || [[ "${2:-}" == "--run" ]]; then
    echo "Launching ROBOTERM..."
    open "$APP_PATH"
fi

echo "=== Done ==="
