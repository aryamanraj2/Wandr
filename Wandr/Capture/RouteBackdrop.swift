//
//  RouteBackdrop.swift
//  Wandr
//
//  The one piece of expressive motion in the app: dashed routes tracing
//  themselves across the page as it opens.
//
//  It earns the exception because launch is rare, it orients rather than
//  decorates (this is a planning app; the routes say "journeys" before a word
//  is read), and it never blocks input — the mic is tappable on frame one.
//
//  The dashes are deliberately the same stroke as `WandrDashedRule`, which
//  already separates decks in curation. Same vocabulary, larger gesture, so it
//  reads as the app's own language rather than an intro sequence bolted on.
//

import SwiftUI

struct RouteBackdrop: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives every trim. One value, so the whole field is a single animation
    /// with per-route delays rather than a dozen to keep in sync.
    @State private var drawn = false

    var body: some View {
        ZStack {
            ForEach(Array(Self.routes.enumerated()), id: \.offset) { index, route in
                Route(points: route.points)
                    .trim(from: 0, to: drawn ? 1 : 0)
                    .stroke(
                        Wandr.sand.opacity(route.weight),
                        style: StrokeStyle(
                            lineWidth: route.width,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: [5, 9]
                        )
                    )
                    // Ease-out: each route leaves fast and settles, the way a
                    // line being drawn does. Linear would read mechanical.
                    .animation(
                        reduceMotion
                            ? .easeOut(duration: 0.3)
                            : .easeOut(duration: 1.15).delay(Double(index) * 0.07),
                        value: drawn
                    )
            }
        }
        // Texture, never a participant. It sits under everything and takes no
        // touches, so the mic stays hittable through it.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { drawn = true }
    }

    // MARK: Geometry

    /// A route of straight runs joined by rounded elbows — a road on a map,
    /// not a flowing arc. The corner is what carries the character here, so
    /// the turns stay tight rather than being smoothed into a curve.
    private struct Route: Shape {
        var points: [CGPoint]
        var corner: CGFloat = 18

        func path(in rect: CGRect) -> Path {
            let scaled = points.map {
                CGPoint(x: $0.x * rect.width, y: $0.y * rect.height)
            }
            guard let first = scaled.first, scaled.count > 1 else { return Path() }

            var path = Path()
            path.move(to: first)

            guard scaled.count > 2 else {
                path.addLine(to: scaled[1])
                return path
            }

            for index in 1..<(scaled.count - 1) {
                let previous = scaled[index - 1]
                let vertex = scaled[index]
                let next = scaled[index + 1]

                let incoming = vector(from: vertex, to: previous)
                let outgoing = vector(from: vertex, to: next)

                // Never eat more than half of either leg, or short segments
                // would collapse into each other.
                let radius = min(
                    corner,
                    length(from: vertex, to: previous) / 2,
                    length(from: vertex, to: next) / 2
                )

                let entry = CGPoint(
                    x: vertex.x + incoming.dx * radius,
                    y: vertex.y + incoming.dy * radius
                )
                let exit = CGPoint(
                    x: vertex.x + outgoing.dx * radius,
                    y: vertex.y + outgoing.dy * radius
                )

                path.addLine(to: entry)
                path.addQuadCurve(to: exit, control: vertex)
            }

            path.addLine(to: scaled[scaled.count - 1])
            return path
        }

        private func length(from a: CGPoint, to b: CGPoint) -> CGFloat {
            max(sqrt(pow(b.x - a.x, 2) + pow(b.y - a.y, 2)), 0.001)
        }

        private func vector(from a: CGPoint, to b: CGPoint) -> CGVector {
            let distance = length(from: a, to: b)
            return CGVector(dx: (b.x - a.x) / distance, dy: (b.y - a.y) / distance)
        }
    }

    private struct Line {
        let points: [CGPoint]
        let width: CGFloat
        let weight: Double
    }

    /// Traced off the sketch: routes run down the margins rather than across
    /// the page, in fragments of varying length — including a few two-dash
    /// stubs, which are what stop the field from looking like a diagram.
    /// The orb's band stays empty by construction.
    private static let routes: [Line] = [
        // Left descent, top third
        Line(points: [CGPoint(x: 0.06, y: 0.13), CGPoint(x: 0.11, y: 0.13),
                      CGPoint(x: 0.16, y: 0.16), CGPoint(x: 0.18, y: 0.20),
                      CGPoint(x: 0.17, y: 0.26), CGPoint(x: 0.14, y: 0.31),
                      CGPoint(x: 0.09, y: 0.34), CGPoint(x: 0.03, y: 0.35)],
             width: 1.9, weight: 0.85),

        // Centre-left spine — the longest run, with the most turns
        Line(points: [CGPoint(x: 0.42, y: 0.02), CGPoint(x: 0.48, y: 0.03),
                      CGPoint(x: 0.49, y: 0.11), CGPoint(x: 0.43, y: 0.13),
                      CGPoint(x: 0.41, y: 0.16), CGPoint(x: 0.40, y: 0.23),
                      CGPoint(x: 0.45, y: 0.28), CGPoint(x: 0.46, y: 0.33),
                      CGPoint(x: 0.45, y: 0.37)],
             width: 1.9, weight: 0.85),

        // Its continuation, peeling away left above the orb
        Line(points: [CGPoint(x: 0.46, y: 0.37), CGPoint(x: 0.39, y: 0.40),
                      CGPoint(x: 0.29, y: 0.405), CGPoint(x: 0.23, y: 0.41),
                      CGPoint(x: 0.16, y: 0.43), CGPoint(x: 0.12, y: 0.46),
                      CGPoint(x: 0.09, y: 0.49), CGPoint(x: 0.03, y: 0.505)],
             width: 1.8, weight: 0.75),

        // Top-right diagonal
        Line(points: [CGPoint(x: 0.79, y: 0.015), CGPoint(x: 0.82, y: 0.045),
                      CGPoint(x: 0.84, y: 0.07)],
             width: 1.7, weight: 0.70),

        // Two stubs — deliberately almost nothing
        Line(points: [CGPoint(x: 0.86, y: 0.109), CGPoint(x: 0.89, y: 0.112)],
             width: 1.7, weight: 0.62),
        Line(points: [CGPoint(x: 0.92, y: 0.156), CGPoint(x: 0.955, y: 0.160)],
             width: 1.7, weight: 0.62),

        // Right-hand bracket, level with the orb but hard against the edge
        Line(points: [CGPoint(x: 0.96, y: 0.365), CGPoint(x: 0.94, y: 0.38),
                      CGPoint(x: 0.935, y: 0.405), CGPoint(x: 0.945, y: 0.435)],
             width: 1.7, weight: 0.66),

        // Bottom-left approach
        Line(points: [CGPoint(x: 0.01, y: 0.777), CGPoint(x: 0.06, y: 0.781),
                      CGPoint(x: 0.11, y: 0.768), CGPoint(x: 0.14, y: 0.757)],
             width: 1.8, weight: 0.72),

        // Bottom-left descent to the corner
        Line(points: [CGPoint(x: 0.19, y: 0.81), CGPoint(x: 0.21, y: 0.845),
                      CGPoint(x: 0.20, y: 0.89), CGPoint(x: 0.18, y: 0.92),
                      CGPoint(x: 0.14, y: 0.95), CGPoint(x: 0.09, y: 0.965)],
             width: 1.9, weight: 0.82),

        // Bottom-right loop, upper half
        Line(points: [CGPoint(x: 0.72, y: 0.843), CGPoint(x: 0.755, y: 0.816),
                      CGPoint(x: 0.80, y: 0.803), CGPoint(x: 0.845, y: 0.811),
                      CGPoint(x: 0.86, y: 0.838)],
             width: 1.8, weight: 0.78),

        // Bottom-right loop, lower half
        Line(points: [CGPoint(x: 0.862, y: 0.869), CGPoint(x: 0.845, y: 0.90),
                      CGPoint(x: 0.80, y: 0.917), CGPoint(x: 0.82, y: 0.95),
                      CGPoint(x: 0.836, y: 0.99)],
             width: 1.8, weight: 0.78),

        // A lone vertical, bottom centre
        Line(points: [CGPoint(x: 0.666, y: 0.906), CGPoint(x: 0.666, y: 0.95)],
             width: 1.7, weight: 0.60)
    ]
}

#Preview {
    ZStack {
        Wandr.pageBackground
        RouteBackdrop()
    }
    .ignoresSafeArea()
}
