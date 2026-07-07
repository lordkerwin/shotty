#!/bin/bash
# Generate Shotty.icns (gradient squircle + camera-viewfinder mark). Re-run to regenerate.
set -euo pipefail
cd "$(dirname "$0")/.."

# 1024px master, drawn straight into a 1:1 bitmap.
swift - <<'SWIFT'
import AppKit
let n = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let size = CGFloat(n)
let inset: CGFloat = 88
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let squircle = NSBezierPath(roundedRect: rect, xRadius: 200, yRadius: 200)
NSGraphicsContext.saveGraphicsState()
squircle.addClip()
NSGradient(starting: NSColor(srgbRed: 0.36, green: 0.44, blue: 0.98, alpha: 1),
           ending: NSColor(srgbRed: 0.62, green: 0.30, blue: 0.92, alpha: 1))!.draw(in: rect, angle: -45)
NSGraphicsContext.restoreGraphicsState()
let cfg = NSImage.SymbolConfiguration(pointSize: 470, weight: .regular).applying(.init(paletteColors: [.white]))
let sym = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
sym.draw(at: NSPoint(x: (size - sym.size.width) / 2, y: (size - sym.size.height) / 2),
         from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "Icon-1024.png"))
SWIFT

# 2. build the .iconset (all sizes) and pack into .icns
set="Shotty.iconset"
rm -rf "$set"; mkdir "$set"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" Icon-1024.png -o "$set/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z "$d" "$d" Icon-1024.png -o "$set/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$set" -o Shotty.icns
rm -rf "$set" Icon-1024.png
echo "Wrote Shotty.icns"
