#!/bin/bash
# Disable (or re-enable) macOS's built-in ⌘⇧3 / ⌘⇧4 screenshot shortcuts so Shotty can use them.
# Usage:  ./macos-screenshots.sh disable   |   ./macos-screenshots.sh enable
# Reversible: `enable` restores the original bindings. ⌘⇧5 and the clipboard variants are left alone.
set -euo pipefail

case "${1:-}" in
  disable) enabled="false" ;;
  enable)  enabled="true"  ;;
  *) echo "usage: $0 disable|enable"; exit 1 ;;
esac

# id 28 = ⌘⇧3 (save whole screen), id 30 = ⌘⇧4 (save selected area).
# params = <char code> <key code> <modifier mask 1179648 = ⇧⌘>.
set_key() {
  defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add "$1" "
    <dict><key>enabled</key><$enabled/><key>value</key><dict>
      <key>type</key><string>standard</string>
      <key>parameters</key><array><integer>$2</integer><integer>$3</integer><integer>1179648</integer></array>
    </dict></dict>"
}
set_key 28 51 20   # ⌘⇧3
set_key 30 52 21   # ⌘⇧4

# Apply without a logout.
/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u

echo "macOS ⌘⇧3 / ⌘⇧4 ${1}d. If Shotty doesn't pick them up right away, log out and back in."
