# Shotty

A tiny macOS menu-bar screenshot annotator + beautifier — arrows, boxes, blur/pixelate, text, on a
gradient/solid/transparent background with padding, rounded corners and a shadow. Native Swift, no
dependencies.

## Build & run

```bash
swift run shotty          # dev
./build-app.sh            # builds Shotty.app (menu-bar agent, no Dock icon)
open Shotty.app           # or drag to /Applications, add to Login Items
```

First capture prompts for **Screen Recording** permission — grant it and relaunch.

## Hotkeys

- **⌘⇧3** — capture full screen
- **⌘⇧4** — capture region (press **Space** mid-select to grab a window)

These reuse macOS's own screenshot keys, so free them first (reversible):

```bash
./Scripts/macos-screenshots.sh disable   # ./Scripts/macos-screenshots.sh enable to restore
```

(Or System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Screenshots — untick the ⌘⇧3 / ⌘⇧4 items.)

## Editing

Select tool → drag handles to reshape, the round handle to rotate (snaps to 45°). The top slider
sets thickness / font size for the selection; blur/pixelate get an intensity slider. ⌘C/⌘V duplicate,
⌘Z / ⌘⇧Z undo/redo. **Copy** puts the composite on the clipboard; **Save…** writes a PNG (transparent
if "No Background" is selected).

## Updates

Shotty checks GitHub Releases on launch (and via **Check for Updates…** in the menu). When a newer
release exists it offers to download the `.zip` to your Downloads folder — unzip and replace the app.

> The app is ad-hoc signed, not notarized, so a downloaded build is Gatekeeper-quarantined:
> right-click ▸ Open the first time to launch it.
