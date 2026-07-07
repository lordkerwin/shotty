import AppKit
import CoreImage

// MARK: - Annotation (one drawn mark)

final class Annotation {
    var tool: Tool
    var start: CGPoint
    var end: CGPoint
    var color: NSColor
    var lineWidth: CGFloat
    var text = ""
    var fontSize: CGFloat = 24
    var rotation: CGFloat = 0 // radians, about the centre (unused for arrows)
    var intensity: CGFloat = 1 // blur/pixelate strength multiplier

    init(tool: Tool, start: CGPoint, end: CGPoint, color: NSColor, lineWidth: CGFloat) {
        self.tool = tool; self.start = start; self.end = end
        self.color = color; self.lineWidth = lineWidth
    }

    var rect: CGRect { normalizedRect(start, end) }
    private var font: NSFont { .boldSystemFont(ofSize: fontSize) }

    func textBounds() -> CGRect {
        let size = (text as NSString).size(withAttributes: [.font: font])
        return CGRect(x: start.x, y: start.y, width: max(size.width, 20), height: max(size.height, fontSize))
    }

    // Unrotated shape box; centre it rotates about.
    var baseRect: CGRect { tool == .text ? textBounds() : rect }
    var center: CGPoint { CGPoint(x: baseRect.midX, y: baseRect.midY) }

    func localCorner(_ i: Int) -> CGPoint {
        let r = baseRect
        switch i {
        case 0: return CGPoint(x: r.minX, y: r.minY)
        case 1: return CGPoint(x: r.maxX, y: r.minY)
        case 2: return CGPoint(x: r.maxX, y: r.maxY)
        default: return CGPoint(x: r.minX, y: r.maxY)
        }
    }
    func worldCorner(_ i: Int) -> CGPoint { rotatePoint(localCorner(i), around: center, by: rotation) }

    private var rotationHandleGap: CGFloat { max(24, min(baseRect.width, baseRect.height) * 0.2) }
    var rotationHandleWorld: CGPoint {
        let r = baseRect
        return rotatePoint(CGPoint(x: r.midX, y: r.maxY + rotationHandleGap), around: center, by: rotation)
    }

    // Drag corner `i` to world point `p`, keeping the opposite corner fixed in world space.
    func setCorner(_ i: Int, toWorld p: CGPoint) {
        let opp = worldCorner((i + 2) % 4)
        let nc = CGPoint(x: (p.x + opp.x) / 2, y: (p.y + opp.y) / 2)
        start = rotatePoint(opp, around: nc, by: -rotation)
        end = rotatePoint(p, around: nc, by: -rotation)
    }

    func rotate(toWorld p: CGPoint) {
        let c = center
        let angle = atan2(p.y - c.y, p.x - c.x) - .pi / 2
        let step = CGFloat.pi / 4 // snap to the nearest 45° when within ~6°
        let snapped = (angle / step).rounded() * step
        rotation = abs(angle - snapped) < (6 * .pi / 180) ? snapped : angle
    }

    func hitTest(_ p: CGPoint) -> Bool {
        if tool == .arrow { return distancePointToSegment(p, start, end) < max(10, lineWidth * 2) }
        let lp = rotatePoint(p, around: center, by: -rotation) // test in the unrotated frame
        switch tool {
        case .rect, .blur, .pixelate: return rect.insetBy(dx: -6, dy: -6).contains(lp)
        case .text: return textBounds().contains(lp)
        default: return false
        }
    }

    func move(dx: CGFloat, dy: CGFloat) { start.x += dx; start.y += dy; end.x += dx; end.y += dy }

    func clone() -> Annotation {
        let a = Annotation(tool: tool, start: start, end: end, color: color, lineWidth: lineWidth)
        a.text = text; a.fontSize = fontSize; a.rotation = rotation; a.intensity = intensity
        return a
    }

    func draw(baseImage: NSImage, ciContext: CIContext) {
        switch tool {
        case .blur:
            drawRedaction(baseImage: baseImage, ciContext: ciContext) { ci, _, unit in
                let f = CIFilter(name: "CIGaussianBlur")
                f?.setValue(ci, forKey: kCIInputImageKey)
                f?.setValue(unit * self.intensity, forKey: kCIInputRadiusKey)
                return f?.outputImage
            }
        case .pixelate:
            drawRedaction(baseImage: baseImage, ciContext: ciContext) { ci, _, unit in
                let f = CIFilter(name: "CIPixellate")
                f?.setValue(ci, forKey: kCIInputImageKey)
                f?.setValue(CIVector(x: 0, y: 0), forKey: kCIInputCenterKey) // stable grid, no phase shift on resize
                f?.setValue(unit * 1.6 * self.intensity, forKey: kCIInputScaleKey)
                return f?.outputImage
            }
        default:
            guard rotation != 0, tool != .arrow else {
                drawBody(baseImage: baseImage, ciContext: ciContext)
                return
            }
            NSGraphicsContext.saveGraphicsState()
            let c = center
            let t = NSAffineTransform()
            t.translateX(by: c.x, yBy: c.y)
            t.rotate(byRadians: rotation)
            t.translateX(by: -c.x, yBy: -c.y)
            t.concat()
            drawBody(baseImage: baseImage, ciContext: ciContext)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func drawBody(baseImage: NSImage, ciContext: CIContext) {
        color.set()
        switch tool {
        case .arrow: drawArrow()
        case .rect:
            let path = NSBezierPath(rect: rect); path.lineWidth = lineWidth; path.stroke()
        case .text: (text as NSString).draw(at: start, withAttributes: [.font: font, .foregroundColor: color])
        default: break
        }
    }

    private func drawArrow() {
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: start)
        path.line(to: end)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let head = max(12, lineWidth * 4)
        for a in [angle + .pi - .pi / 7, angle + .pi + .pi / 7] {
            path.move(to: end)
            path.line(to: CGPoint(x: end.x + cos(a) * head, y: end.y + sin(a) * head))
        }
        path.stroke()
    }

    // Blur/pixelate sample the actual (possibly rotated) region: crop + filter the region's bounding
    // box from the source, then clip to the rotated rectangle so the filtered pixels line up with what
    // they cover. ponytail: blur is the CleanShot look but can be partially reversed — pixelate is the
    // safer choice for redacting real secrets.
    private func drawRedaction(baseImage: NSImage, ciContext: CIContext,
                               filter: (_ input: CIImage, _ pixelRect: CGRect, _ unit: CGFloat) -> CIImage?) {
        let corners = (0..<4).map { worldCorner($0) }
        let xs = corners.map { $0.x }, ys = corners.map { $0.y }
        let bbox = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        guard bbox.width > 1, bbox.height > 1,
              let cg = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let sx = CGFloat(cg.width) / baseImage.size.width
        let sy = CGFloat(cg.height) / baseImage.size.height
        let pixBBox = CGRect(x: bbox.minX * sx, y: bbox.minY * sy, width: bbox.width * sx, height: bbox.height * sy)
        // Fixed strength from the image resolution, so it stays constant as the region scales/rotates.
        let unit = max(8, min(CGFloat(cg.width), CGFloat(cg.height)) * 0.012)
        let ci = CIImage(cgImage: cg).clampedToExtent()
        guard let out = filter(ci, pixBBox, unit),
              let outCG = ciContext.createCGImage(out, from: pixBBox) else { return }
        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath()
        clip.move(to: corners[0]); for i in 1..<4 { clip.line(to: corners[i]) }
        clip.close(); clip.addClip()
        NSImage(cgImage: outCG, size: bbox.size).draw(in: bbox)
        NSGraphicsContext.restoreGraphicsState()
    }
}
