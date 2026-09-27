#!/bin/bash
# Builds USBDriveDoctor and packages it into a launchable .app bundle.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="USBDriveDoctor.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp ".build/release/USBDriveDoctor" "$APP/Contents/MacOS/USBDriveDoctor"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>USBDriveDoctor</string>
    <key>CFBundleIdentifier</key>
    <string>local.usbdrivedoctor</string>
    <key>CFBundleName</key>
    <string>USB Drive Doctor</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

echo "Built: $(pwd)/$APP"
