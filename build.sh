#!/bin/bash
# Build ipflag.app — a self-contained macOS menu-bar app.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ipflag"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

echo "Cleaning previous build..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "Compiling main.swift..."
swiftc -O -o "$MACOS_DIR/$APP_NAME" main.swift

echo "Assembling app bundle..."
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp icon/AppIcon.icns "$RESOURCES_DIR/AppIcon.icns"

# Ad-hoc code signature so the app launches without Gatekeeper complaints and
# so login-item registration behaves predictably on modern macOS.
if command -v codesign >/dev/null 2>&1; then
    echo "Ad-hoc signing..."
    codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || \
        echo "  (warning: ad-hoc signing failed; app will still run)"
fi

echo ""
echo "✅ Built $APP_BUNDLE"
echo "   Run it with:  open $APP_BUNDLE"
