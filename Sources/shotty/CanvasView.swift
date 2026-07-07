import AppKit
import CoreImage

// MARK: - Canvas

// A full snapshot of everything undo/redo restores.
struct CanvasState {
    var annotations: [Annotation]
    var background: Background
    var padding: CGFloat
    var corner: CGFloat
    var shadow: CGFloat
    var ratio: CGFloat?
}

final class CanvasView: NSView {
    let baseImage: NSImage
    var annotations: [Annotation] = []
    var tool: Tool = .arrow
    var color: NSColor = .systemRed
    var lineWidth: CGFloat = 4
    var onToolChanged: ((Tool) -> Void)? // lets the toolbar reflect an auto-switch to Select

    // Beautify state (fractions of the shorter image side, so they scale with any screenshot).
    var background: Background = .none // transparent by default
    var paddingFraction: CGFloat = 0.06
    var cornerFraction: CGFloat = 0.03
    var shadowStrength: CGFloat = 0.5 // 0 = off
    var ratio: CGFloat? = nil        // nil = auto (match the screenshot's own ratio)

    private enum DragMode { case none, move, corner(Int), rotate, arrowStart, arrowEnd }
    var onSelectionChanged: ((Annotation?) -> Void)?
    var selectedAnnotation: Annotation? { selected }
    private let ciContext = CIContext()
    private var current: Annotation?
    private var selected: Annotation? { didSet { onSelectionChanged?(selected) } }
    private var dragLast: CGPoint = .zero
    private var dragMode: DragMode = .none
    private var didDrag = false
    private var textField: NSTextField?
    private var clipboard: Annotation?
    private var undoStack: [CanvasState] = []
    private var redoStack: [CanvasState] = []
    private var pendingUndo: CanvasState?
    var onHistoryChanged: (() -> Void)?
    var onStateRestored: (() -> Void)? // resync sidebar controls after undo/redo
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    init(image: NSImage) {
        baseImage = image
        super.init(frame: CGRect(origin: .zero, size: image.size))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    // The screenshot sits on a padded gradient "composite". Everything is expressed in image
    // points; layout aspect-fits the whole composite into the (resizable) view.
    private var padPoints: CGFloat { paddingFraction * min(baseImage.size.width, baseImage.size.height) }
    // The padded screenshot block.
    private var innerSize: CGSize {
        CGSize(width: baseImage.size.width + 2 * padPoints, height: baseImage.size.height + 2 * padPoints)
    }
    // The background canvas: the inner block, or the smallest rect of the chosen ratio that contains it.
    private var compositeSize: CGSize {
        let inner = innerSize
        guard let r = ratio, inner.width > 0, inner.height > 0 else { return inner }
        return inner.width / inner.height > r
            ? CGSize(width: inner.width, height: inner.width / r)
            : CGSize(width: inner.height * r, height: inner.height)
    }

    // Aspect-fit the composite into `container`, place the padded block by alignment, inset for the image.
    private func computeLayout(in container: CGRect) -> (composite: CGRect, image: CGRect, radius: CGFloat) {
        let cs = compositeSize, inner = innerSize
        guard cs.width > 0, cs.height > 0, container.width > 0, container.height > 0 else { return (container, container, 0) }
        let s = min(container.width / cs.width, container.height / cs.height)
        let cw = cs.width * s, ch = cs.height * s
        let comp = CGRect(x: container.minX + (container.width - cw) / 2,
                          y: container.minY + (container.height - ch) / 2, width: cw, height: ch)
        let iw = inner.width * s, ih = inner.height * s
        let inner_ = CGRect(x: comp.midX - iw / 2, y: comp.midY - ih / 2, width: iw, height: ih)
        let img = inner_.insetBy(dx: padPoints * s, dy: padPoints * s)
        let radius = cornerFraction * min(baseImage.size.width, baseImage.size.height) * s
        return (comp, img, radius)
    }
    private var layout: (composite: CGRect, image: CGRect, radius: CGFloat) { computeLayout(in: bounds) }
    private var displayScale: CGFloat { layout.image.width / baseImage.size.width }

    private func toImage(_ viewPoint: CGPoint) -> CGPoint {
        let img = layout.image
        let s = img.width / baseImage.size.width
        return CGPoint(x: (viewPoint.x - img.origin.x) / s, y: (viewPoint.y - img.origin.y) / s)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true // redraw the whole composite on resize
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1).setFill()
        bounds.fill() // dark canvas around the composite
        let l = layout
        if case .none = background { drawCheckerboard(in: l.composite) } // preview only — signals transparency
        drawComposite(composite: l.composite, image: l.image, radius: l.radius, showSelection: true)
    }

    private func drawCheckerboard(in rect: CGRect) {
        let tile: CGFloat = 10
        NSColor(white: 0.30, alpha: 1).setFill(); rect.fill()
        NSColor(white: 0.42, alpha: 1).setFill()
        var row = 0
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX + (row.isMultiple(of: 2) ? 0 : tile)
            while x < rect.maxX {
                CGRect(x: x, y: y, width: min(tile, rect.maxX - x), height: min(tile, rect.maxY - y)).fill()
                x += 2 * tile
            }
            y += tile; row += 1
        }
    }

    // Shared by screen draw and export: gradient bg, drop shadow, rounded screenshot, annotations.
    private func drawComposite(composite: CGRect, image: CGRect, radius: CGFloat, showSelection: Bool) {
        switch background {
        case .none: break // transparent
        case .gradient(let i): Backgrounds.gradient(i).draw(in: composite, angle: -45)
        case .solid(let c): c.setFill(); composite.fill()
        }

        let path = NSBezierPath(roundedRect: image, xRadius: radius, yRadius: radius)
        if shadowStrength > 0 {
            NSGraphicsContext.saveGraphicsState()
            let sh = NSShadow()
            sh.shadowColor = NSColor.black.withAlphaComponent(0.6 * shadowStrength)
            sh.shadowBlurRadius = max(6, radius) * (0.6 + shadowStrength)
            sh.shadowOffset = NSSize(width: 0, height: -6 - 8 * shadowStrength)
            sh.set()
            NSColor.black.setFill()
            path.fill() // opaque fill casts the shadow; the image covers it next
            NSGraphicsContext.restoreGraphicsState()
        }

        NSGraphicsContext.saveGraphicsState()
        path.addClip() // clips both the image and annotations to the rounded corners
        baseImage.draw(in: image)
        let s = image.width / baseImage.size.width
        let t = NSAffineTransform()
        t.translateX(by: image.origin.x, yBy: image.origin.y)
        t.scaleX(by: s, yBy: s)
        t.concat()
        for a in annotations { a.draw(baseImage: baseImage, ciContext: ciContext) }
        current?.draw(baseImage: baseImage, ciContext: ciContext)
        if showSelection, let sel = selected {
            NSColor.systemBlue.setStroke()
            if sel.tool == .arrow {
                drawHandle(sel.start, s)
                drawHandle(sel.end, s)
            } else {
                // rotated dashed outline through the four corners
                let outline = NSBezierPath()
                outline.move(to: sel.worldCorner(0))
                for i in 1..<4 { outline.line(to: sel.worldCorner(i)) }
                outline.close()
                outline.lineWidth = 1 / s
                outline.setLineDash([4, 3], count: 2, phase: 0)
                outline.stroke()
                // rotation handle + connector from the top edge
                let rh = sel.rotationHandleWorld
                let topMid = CGPoint(x: (sel.worldCorner(2).x + sel.worldCorner(3).x) / 2,
                                     y: (sel.worldCorner(2).y + sel.worldCorner(3).y) / 2)
                let conn = NSBezierPath(); conn.move(to: topMid); conn.line(to: rh); conn.lineWidth = 1 / s
                conn.stroke()
                drawHandle(rh, s, round: true)
                if sel.tool != .text { for i in 0..<4 { drawHandle(sel.worldCorner(i), s) } }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawHandle(_ p: CGPoint, _ s: CGFloat, round: Bool = false) {
        let hs = 9 / s
        let r = CGRect(x: p.x - hs / 2, y: p.y - hs / 2, width: hs, height: hs)
        let path = round ? NSBezierPath(ovalIn: r) : NSBezierPath(rect: r)
        NSColor.white.setFill(); path.fill()
        NSColor.systemBlue.setStroke(); path.lineWidth = 1.5 / s; path.stroke()
    }

    override func mouseDown(with e: NSEvent) {
        commitChange() // flush any pending slider edit into history
        commitText()
        didDrag = false
        let viewP = convert(e.locationInWindow, from: nil)
        let p = toImage(viewP)
        window?.makeFirstResponder(self)
        switch tool {
        case .select:
            // Grab a handle of the current selection before re-selecting something else.
            let tol = 12 / max(displayScale, 0.0001)
            if let s = selected {
                if s.tool == .arrow {
                    if hypot(p.x - s.start.x, p.y - s.start.y) < tol { dragMode = .arrowStart; return }
                    if hypot(p.x - s.end.x, p.y - s.end.y) < tol { dragMode = .arrowEnd; return }
                } else {
                    let rh = s.rotationHandleWorld
                    if hypot(p.x - rh.x, p.y - rh.y) < tol { dragMode = .rotate; return }
                    if s.tool != .text {
                        for i in 0..<4 {
                            let c = s.worldCorner(i)
                            if hypot(p.x - c.x, p.y - c.y) < tol { dragMode = .corner(i); return }
                        }
                    }
                }
            }
            selected = annotations.last { $0.hitTest(p) }
            dragMode = (selected != nil) ? .move : .none
            dragLast = p
            needsDisplay = true
        case .text:
            startText(atView: viewP)
        default:
            current = Annotation(tool: tool, start: p, end: p, color: color, lineWidth: lineWidth)
        }
    }

    override func mouseDragged(with e: NSEvent) {
        let p = toImage(convert(e.locationInWindow, from: nil))
        if tool == .select {
            let dragging: Bool = { if case .none = dragMode { return false } else { return true } }()
            if dragging, !didDrag { beginChange(); didDrag = true } // snapshot before first move
            switch dragMode {
            case .move: selected?.move(dx: p.x - dragLast.x, dy: p.y - dragLast.y); dragLast = p
            case .arrowStart: selected?.start = p
            case .arrowEnd: selected?.end = p
            case .corner(let i): selected?.setCorner(i, toWorld: p)
            case .rotate: selected?.rotate(toWorld: p)
            case .none: break
            }
        } else {
            current?.end = p
        }
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) {
        if let c = current {
            if c.tool == .arrow || c.rect.width + c.rect.height > 4 {
                recordChange { annotations.append(c) }
                selectAndSwitch(to: c) // select the fresh annotation so it can be adjusted right away
            }
            current = nil
            needsDisplay = true
        } else if didDrag {
            commitChange() // a move/resize/rotate finished
        }
        dragMode = .none
        didDrag = false
    }

    private func selectAndSwitch(to a: Annotation) {
        selected = a
        tool = .select
        onToolChanged?(.select)
    }

    override func keyDown(with e: NSEvent) {
        if e.modifierFlags.contains(.command), let ch = e.charactersIgnoringModifiers?.lowercased() {
            switch ch {
            case "c":
                if let s = selected { clipboard = s.clone() }
                else { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([renderedImage()]) }
                return
            case "v":
                if let c = clipboard { clipboard = placeDuplicate(of: c) } // cascade on repeated paste
                return
            case "z":
                if e.modifierFlags.contains(.shift) { redo() } else { undo() }
                return
            default: break
            }
        }
        if e.keyCode == 51 || e.keyCode == 117 { // delete / fwd-delete
            if let s = selected, let i = annotations.firstIndex(where: { $0 === s }) {
                recordChange { annotations.remove(at: i) }
                selected = nil; needsDisplay = true
            }
        } else {
            super.keyDown(with: e)
        }
    }

    @discardableResult
    private func placeDuplicate(of source: Annotation) -> Annotation {
        let dup = source.clone()
        let off = 20 / max(displayScale, 0.0001) // ~20px, down-right
        dup.move(dx: off, dy: -off)
        recordChange { annotations.append(dup) }
        selectAndSwitch(to: dup)
        needsDisplay = true
        return dup
    }

    func duplicateSelected() { if let s = selected { placeDuplicate(of: s) } }

    // MARK: - Undo / redo (full-canvas snapshots)

    private func snapshot() -> CanvasState {
        CanvasState(annotations: annotations.map { $0.clone() }, background: background,
                    padding: paddingFraction, corner: cornerFraction, shadow: shadowStrength, ratio: ratio)
    }
    private func apply(_ s: CanvasState) {
        annotations = s.annotations; background = s.background
        paddingFraction = s.padding; cornerFraction = s.corner; shadowStrength = s.shadow; ratio = s.ratio
        selected = nil
        onStateRestored?(); needsDisplay = true
    }

    // Discrete edit: capture the pre-state, mutate, push it.
    func recordChange(_ mutate: () -> Void) {
        let before = snapshot()
        mutate()
        undoStack.append(before); redoStack.removeAll()
        onHistoryChanged?()
    }
    // Continuous edit (drag, slider): capture once on begin, push on commit.
    func beginChange() { if pendingUndo == nil { pendingUndo = snapshot() } }
    func commitChange() {
        guard let before = pendingUndo else { return }
        pendingUndo = nil
        undoStack.append(before); redoStack.removeAll()
        onHistoryChanged?()
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(snapshot()); apply(prev); onHistoryChanged?()
    }
    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot()); apply(next); onHistoryChanged?()
    }

    private func startText(atView p: CGPoint) {
        let tf = NSTextField(frame: CGRect(x: p.x, y: p.y - 30, width: 220, height: 30))
        tf.font = .boldSystemFont(ofSize: 24)
        tf.textColor = color
        tf.drawsBackground = false
        tf.isBordered = false
        tf.focusRingType = .none
        tf.target = self
        tf.action = #selector(commitText)
        addSubview(tf)
        window?.makeFirstResponder(tf)
        textField = tf
    }

    @objc func commitText() {
        guard let tf = textField else { return }
        let str = tf.stringValue
        let origin = toImage(CGPoint(x: tf.frame.origin.x + 2, y: tf.frame.origin.y + 3))
        tf.removeFromSuperview()
        textField = nil
        if !str.isEmpty {
            // ponytail: baseline offset is approximate — field preview and final draw can differ a few px.
            let a = Annotation(tool: .text, start: origin, end: origin, color: color, lineWidth: lineWidth)
            a.text = str
            a.fontSize = 24 / displayScale // keep on-screen size matching the field at current zoom
            recordChange { annotations.append(a) }
            selectAndSwitch(to: a)
        }
        needsDisplay = true
    }

    // Render the full composite at the SOURCE's native pixel resolution. Retina screencapture PNGs
    // carry 144 DPI, so baseImage.size is in points (half the pixels) — scale up by that factor or
    // the export comes out soft.
    private func renderedRep() -> NSBitmapImageRep? {
        commitText()
        selected = nil
        let cs = compositeSize // points
        var pxScale: CGFloat = 1
        if let cg = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil), baseImage.size.width > 0 {
            pxScale = CGFloat(cg.width) / baseImage.size.width
        }
        let w = Int((cs.width * pxScale).rounded()), h = Int((cs.height * pxScale).rounded())
        guard w > 0, h > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil } // 1 unit = 1 pixel
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        let t = NSAffineTransform()
        t.scaleX(by: pxScale, yBy: pxScale) // map point-space drawing into the pixel-space bitmap
        t.concat()
        let l = computeLayout(in: CGRect(origin: .zero, size: cs))
        drawComposite(composite: l.composite, image: l.image, radius: l.radius, showSelection: false)
        NSGraphicsContext.restoreGraphicsState()
        rep.size = cs // logical (point) size for NSImage/clipboard; PNG still uses the full w×h pixels
        return rep
    }

    func renderedImage() -> NSImage {
        guard let rep = renderedRep() else { return baseImage }
        let out = NSImage(size: rep.size)
        out.addRepresentation(rep)
        return out
    }

    func renderedPNG() -> Data? { renderedRep()?.representation(using: .png, properties: [:]) }
}
