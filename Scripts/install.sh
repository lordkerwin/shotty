#!/bin/bash
# Build Shotty and install it into /Applications, replacing the running copy. For local dev updates.
set -euo pipefail
cd "$(dirname "$0")/.."

./build-app.sh
killall shotty 2>/dev/null || true   # quit the running menu-bar instance so it can be replaced
rm -rf /Applications/Shotty.app
cp -R Shotty.app /Applications/       # cp -R preserves the code signature
open /Applications/Shotty.app
echo "Installed to /Applications and relaunched."
