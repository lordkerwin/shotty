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

# Sign with a STABLE self-signed identity so macOS keeps the Screen Recording grant across rebuilds.
# Ad-hoc (`--sign -`) changes the signature every build, so TCC treats each build as a new app and
# re-prompts. Create the identity once (see Scripts/dev-cert.sh), or set SHOTTY_SIGN_IDENTITY.
IDENTITY="${SHOTTY_SIGN_IDENTITY:-Shotty Self-Signed}"
# No -v: a self-signed identity is "not trusted" so -v hides it, but codesign still signs with it fine.
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
  codesign --force --deep --sign "$IDENTITY" "$APP"
  echo "Built $APP, signed with '$IDENTITY'. Grant Screen Recording once; it persists across rebuilds."
else
  codesign --force --deep --sign - "$APP"
  echo "Built $APP (ad-hoc signed)."
  echo "⚠  No '$IDENTITY' identity found, so macOS will re-prompt for Screen Recording every rebuild."
  echo "   Run ./Scripts/dev-cert.sh once to create it, then rebuild."
fi
