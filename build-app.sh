#!/bin/bash
# Build Shotty.app — a proper menu-bar agent bundle (no Dock icon, LSUIElement).
# Run: ./build-app.sh   then drag Shotty.app to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP="Shotty.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/shotty "$APP/Contents/MacOS/shotty"
[ -f Shotty.icns ] && cp Shotty.icns "$APP/Contents/Resources/Shotty.icns"

# Keep the bundle version in sync with the app's shottyVersion constant.
VER=$(grep -oE 'shottyVersion = "[0-9.]+"' Sources/shotty/Updater.swift | grep -oE '[0-9.]+' | head -1)

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Shotty</string>
    <key>CFBundleDisplayName</key><string>Shotty</string>
    <key>CFBundleIdentifier</key><string>com.shotty.app</string>
    <key>CFBundleExecutable</key><string>shotty</string>
    <key>CFBundleIconFile</key><string>Shotty</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VER}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>Shotty</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS keeps the same permission grant across rebuilds.
codesign --force --deep --sign - "$APP"
echo "Built $APP — drag it to /Applications, then grant Screen Recording on first capture."
