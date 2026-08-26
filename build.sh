#!/bin/bash
# Builds HeadTracker.app without Xcode (Command Line Tools are enough).
set -euo pipefail
cd "$(dirname "$0")"

APP=build/HeadTracker.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O \
    -target "$(uname -m)-apple-macos14.0" \
    HeadTracker/*.swift \
    -o "$APP/Contents/MacOS/HeadTracker"

# Xcode substitutes the $(...) placeholders at build time; do it by hand here.
cp HeadTracker/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleExecutable HeadTracker" \
    -c "Set :CFBundleIdentifier com.pratikaman.HeadTracker" \
    -c "Set :CFBundleName HeadTracker" \
    -c "Set :CFBundleDevelopmentRegion en" \
    "$APP/Contents/Info.plist"
cp HeadTracker/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

echo "Built $APP"
echo "Run it with: open $APP"
