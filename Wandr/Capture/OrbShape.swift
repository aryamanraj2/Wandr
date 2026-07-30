// OrbShape.swift Wandr The silhouette every layer of the capture orb is cut from. It is a rounded rectangle walked by arc length and pushed out along its own normal by a sum of three periodic waves, so the same type is a wobbling blob when its rect is square and a still capsule when its rect is a text field. That is what makes the orb→composer morph one continuous shape rather than a crossfade between two: nothing swaps, the rect changes and the wobble drains to zero.

import SwiftUI

struct OrbShape: Shape {

    /// How far the outline leaves its rounded-rect base, as a fraction of the shape's inner radius. 0 is the exact capsule; ~0.12 is a lively speaking blob.
    var wobble: Double

    /// Drift clock in seconds. Comes from a `TimelineView`, so it is deliberately *not* animatable — the timeline already delivers a new value every frame, and letting SwiftUI interpolate it too would fight that.
    var phase: Double

    /// Decorrelates the outer echo strokes from the body so the layers breathe as a group instead of moving as one rigid stack.
    var seed: Double = 0

    /// Only the wobble interpolates. Morphing to the composer is exactly "wobble → 0" plus the rect the caller hands us, so a single animatable scalar carries the whole shape change.
    var animatableData: Double {
        get { wobble }
        set { wobble = newValue }
    }

    /// 48 samples is smooth at orb size and cheap enough to rebuild every frame; the Catmull-Rom pass below hides the sampling entirely.
    private static let sampleCount = 48

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2

        // The composer field, Reduce Motion, and the settled tail of the morph all land here. A real
        // `roundedRect` path (rather than a 48-point approximation of one) keeps the resting shape
        // pixel-exact against the system's own capsules.
        guard wobble > 0.0005, radius > 0 else {
            return Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        }

        let amplitude = radius * wobble
        var points: [CGPoint] = []
        points.reserveCapacity(Self.sampleCount)

        for index in 0..<Self.sampleCount {
            let t = Double(index) / Double(Self.sampleCount)
            let (point, normal) = Self.outline(in: rect, radius: radius, at: t)
            let push = amplitude * Self.wave(t: t, phase: phase, seed: seed)
            points.append(CGPoint(x: point.x + normal.dx * push,
                                  y: point.y + normal.dy * push))
        }

        return Self.closedCurve(through: points)
    }

    // MARK: Outline walk

    /// Point and outward normal at fraction `t` of the rounded rect's perimeter, walked clockwise
    /// from the top-left corner's end. Walking by arc length rather than by angle is what keeps the
    /// waves evenly spaced when the rect is wide — sampling by angle bunches every sample into the
    /// two end caps as soon as the shape stops being square.
    private static func outline(in rect: CGRect, radius r: CGFloat, at t: Double) -> (CGPoint, CGVector) {
        let straightW = max(0, rect.width - 2 * r)
        let straightH = max(0, rect.height - 2 * r)
        let arc = .pi / 2 * r
        let perimeter = 2 * straightW + 2 * straightH + 4 * arc

        var d = CGFloat(t) * perimeter

        // Top edge, left to right.
        if d < straightW {
            return (CGPoint(x: rect.minX + r + d, y: rect.minY), CGVector(dx: 0, dy: -1))
        }
        d -= straightW

        if d < arc {
            return onArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                         radius: r, from: -.pi / 2, sweep: .pi / 2, progress: d / arc)
        }
        d -= arc

        if d < straightH {
            return (CGPoint(x: rect.maxX, y: rect.minY + r + d), CGVector(dx: 1, dy: 0))
        }
        d -= straightH

        if d < arc {
            return onArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                         radius: r, from: 0, sweep: .pi / 2, progress: d / arc)
        }
        d -= arc

        if d < straightW {
            return (CGPoint(x: rect.maxX - r - d, y: rect.maxY), CGVector(dx: 0, dy: 1))
        }
        d -= straightW

        if d < arc {
            return onArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                         radius: r, from: .pi / 2, sweep: .pi / 2, progress: d / arc)
        }
        d -= arc

        if d < straightH {
            return (CGPoint(x: rect.minX, y: rect.maxY - r - d), CGVector(dx: -1, dy: 0))
        }
        d -= straightH

        return onArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r),
                     radius: r, from: .pi, sweep: .pi / 2, progress: min(1, d / arc))
    }

    private static func onArc(
        center: CGPoint,
        radius: CGFloat,
        from start: Double,
        sweep: Double,
        progress: CGFloat
    ) -> (CGPoint, CGVector) {
        let angle = start + sweep * Double(progress)
        let normal = CGVector(dx: cos(angle), dy: sin(angle))
        let point = CGPoint(x: center.x + radius * normal.dx, y: center.y + radius * normal.dy)
        return (point, normal)
    }

    // MARK: Deformation

    /// Three periodic waves at 2, 3, and 5 cycles around the outline. Coprime frequencies and
    /// unequal drift rates mean the silhouette never visibly repeats, which is the difference
    /// between "alive" and "looping". Everything stays periodic in `t` so the closed curve joins
    /// seamlessly at the seam.
    private static func wave(t: Double, phase: Double, seed: Double) -> Double {
        let a = sin(t * 2 * .pi * 3 + phase * 0.90 + seed)
        let b = sin(t * 2 * .pi * 2 - phase * 0.63 + seed * 1.7)
        let c = sin(t * 2 * .pi * 5 + phase * 1.31 + seed * 0.4)
        return (0.55 * a + 0.32 * b + 0.20 * c) / 1.07
    }

    // MARK: Smoothing

    /// Catmull-Rom through every sample, converted to cubic Béziers. The curve passes through the
    /// displaced points exactly, so the wave amplitude means what it says, and C1 continuity across
    /// the wrap keeps the seam invisible.
    private static func closedCurve(through points: [CGPoint]) -> Path {
        var path = Path()
        guard points.count > 2 else { return path }

        let n = points.count
        path.move(to: points[0])

        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n]
            let p1 = points[i]
            let p2 = points[(i + 1) % n]
            let p3 = points[(i + 2) % n]

            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }

        path.closeSubpath()
        return path
    }
}
