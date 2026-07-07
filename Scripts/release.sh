#!/bin/bash
# Cut a release: build Shotty.app, zip it, and publish a GitHub Release the in-app updater can find.
# Usage: ./Scripts/release.sh 0.2   (bump `shottyVersion` in Sources/shotty/Updater.swift first)
set -euo pipefail
cd "$(dirname "$0")/.."

ver="${1:?usage: release.sh <version e.g. 0.2>}"
src=$(grep -oE 'shottyVersion = "[0-9.]+"' Sources/shotty/Updater.swift | grep -oE '[0-9.]+' | head -1)
[ "$src" = "$ver" ] || { echo "shottyVersion is $src but you asked for $ver — bump it in Updater.swift, commit, then retry."; exit 1; }

./build-app.sh
zip="Shotty-$ver.zip"
rm -f "$zip"
ditto -c -k --keepParent Shotty.app "$zip"   # ditto keeps the bundle intact for macOS

gh release create "v$ver" "$zip" --title "v$ver" --notes "Shotty v$ver"
echo "Published v$ver with $zip attached."
