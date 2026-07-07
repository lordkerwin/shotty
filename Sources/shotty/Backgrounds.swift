import AppKit

// MARK: - Tools & backgrounds

enum Tool: String, CaseIterable { case select, arrow, rect, blur, pixelate, text }

enum Background {
    case none
    case gradient(Int)
    case solid(NSColor)

    func sameAs(_ o: Background) -> Bool {
        switch (self, o) {
        case (.none, .none): return true
        case let (.gradient(a), .gradient(b)): return a == b
        case let (.solid(a), .solid(b)): return a == b
        default: return false
        }
    }
}

enum Backgrounds {
    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
    static let pairs: [(NSColor, NSColor)] = [
        (rgb(0.96, 0.42, 0.62), rgb(0.80, 0.20, 0.52)), // pink → magenta
        (rgb(0.52, 0.30, 0.90), rgb(0.32, 0.52, 0.98)), // purple → blue
        (rgb(0.05, 0.15, 0.45), rgb(0.02, 0.05, 0.20)), // deep blue
        (rgb(0.10, 0.62, 0.60), rgb(0.45, 0.80, 0.55)), // teal → green
        (rgb(0.97, 0.32, 0.30), rgb(0.98, 0.60, 0.22)), // red → orange
        (rgb(0.98, 0.75, 0.80), rgb(0.95, 0.60, 0.70)), // soft pink
        (rgb(0.92, 0.92, 0.95), rgb(0.78, 0.80, 0.85)), // light
        (rgb(0.98, 0.85, 0.70), rgb(0.95, 0.70, 0.55)), // peach
        (rgb(0.35, 0.30, 0.85), rgb(0.20, 0.45, 0.90)), // indigo
        (rgb(0.10, 0.10, 0.25), rgb(0.02, 0.02, 0.10)), // midnight
    ]
    static let plainColors: [NSColor] = [
        .black, .white, .systemRed, .systemOrange, .systemYellow, .systemGreen,
        .systemBlue, .systemPurple, .systemPink, .systemTeal, .systemIndigo, .systemGray,
    ]
    static func gradient(_ i: Int) -> NSGradient {
        let p = pairs[min(max(i, 0), pairs.count - 1)]
        return NSGradient(starting: p.0, ending: p.1)!
    }
    static func gradientThumbnail(_ i: Int, size: NSSize) -> NSImage {
        thumbnail(size) { rect in gradient(i).draw(in: rect, angle: -45) }
    }
    static func solidThumbnail(_ c: NSColor, size: NSSize) -> NSImage {
        thumbnail(size) { rect in c.setFill(); rect.fill() }
    }
    private static func thumbnail(_ size: NSSize, _ body: (NSRect) -> Void) -> NSImage {
        let img = NSImage(size: size)
        let rect = NSRect(origin: .zero, size: size)
        img.lockFocus()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).addClip()
        body(rect)
        img.unlockFocus()
        return img
    }
}
