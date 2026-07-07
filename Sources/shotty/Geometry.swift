import Foundation
import CoreGraphics

// MARK: - Geometry (pure, self-checkable)

func distancePointToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = b.x - a.x, dy = b.y - a.y
    if dx == 0 && dy == 0 { return hypot(p.x - a.x, p.y - a.y) }
    let t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)
    let tc = max(0, min(1, t))
    let proj = CGPoint(x: a.x + tc * dx, y: a.y + tc * dy)
    return hypot(p.x - proj.x, p.y - proj.y)
}

func normalizedRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
    CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
}

func rotatePoint(_ p: CGPoint, around c: CGPoint, by a: CGFloat) -> CGPoint {
    if a == 0 { return p }
    let dx = p.x - c.x, dy = p.y - c.y
    let ca = cos(a), sa = sin(a)
    return CGPoint(x: c.x + dx * ca - dy * sa, y: c.y + dx * sa + dy * ca)
}

func runSelfCheck() {
    assert(abs(distancePointToSegment(CGPoint(x: 0, y: 1), CGPoint(x: -1, y: 0), CGPoint(x: 1, y: 0)) - 1) < 1e-9)
    assert(distancePointToSegment(CGPoint(x: 2, y: 0), CGPoint(x: -1, y: 0), CGPoint(x: 1, y: 0)) == 1) // past endpoint
    let r = normalizedRect(CGPoint(x: 3, y: 4), CGPoint(x: 1, y: 1))
    assert(r.origin.x == 1 && r.origin.y == 1 && r.width == 2 && r.height == 3)
    print("selfcheck ok")
}
