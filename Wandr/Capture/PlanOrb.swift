//
//  PlanOrb.swift
//  Wandr
//
//  The one object on the capture screen. It is a single rounded rectangle all
//  the way through: a circle is just that shape at corner = size / 2, so the
//  collapse into a text field is one continuous morph rather than a crossfade
//  between two different views.
//
//  Layers, back to front:
//    1. bloom      — diffuse light the voice pushes outward
//    2. rings      — three strokes, each on its own spring, so amplitude
//                    arrives at the outer edge slightly late (a body, not a
//                    rigid disc)
//    3. surface    — the cream face, top-lit, with a contact shadow
//    4. rim        — a hairline that gains contrast while listening
//    5. glyph      — mic, or the composer field once expanded
//

import SwiftUI

/// Declared outside `PlanOrb` on purpose: a type nested in a generic is
/// distinct per specialization, so `PlanOrb<A>.Mode` and `PlanOrb<B>.Mode`
/// would not be the same type for a caller holding it in `@State`.
enum OrbMode: Equatable {
    case orb
    case composer
}

struct PlanOrb<Face: View>: View {

    var mode: OrbMode
    var isListening: Bool
    /// 0...1 live microphone amplitude.
    var level: Double
    /// What sits on the face — the mic glyph, or the composer field once the
    /// shape has flattened. It shares the surface's frame so it travels with
    /// the morph instead of being crossfaded on top of it.
    @ViewBuilder var face: Face

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Slow idle breath so a silent orb still reads as awake. Amplitude is
    /// tiny — this is a resting state, not an attractor loop.
    @State private var breathing = false

    private var diameter: CGFloat { 224 }

    /// Reduce Motion keeps the size feedback but drops the ring travel, which
    /// is the part that oscillates.
    private var reactive: Double {
        reduceMotion ? 0 : level
    }

    var body: some View {
        ZStack {
            surface
            face
                .frame(maxWidth: mode == .composer ? .infinity : diameter)
                .frame(height: mode == .composer ? 60 : diameter)
        }
        // Light and rings are decoration, so they hang off the surface as a
        // background rather than sitting in the stack. The bloom is 1.7× the
        // diameter — as a sibling it set the orb's height even in composer
        // mode, where it is invisible, and that phantom 380pt pushed whatever
        // followed the text field down under the keyboard.
        .background {
            bloom
            rings
        }
        .frame(
            maxWidth: mode == .composer ? .infinity : nil,
            alignment: .center
        )
        .onAppear { breathing = true }
    }

    // MARK: Layers

    /// Warm light that grows with the voice. Not a glow around the shape — a
    /// wash the shape sits in, so the orb feels lit rather than outlined.
    private var bloom: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Wandr.sand.opacity(0.55), Wandr.sand.opacity(0)],
                    center: .center,
                    startRadius: diameter * 0.2,
                    endRadius: diameter * 0.78
                )
            )
            .frame(width: diameter * 1.7, height: diameter * 1.7)
            .scaleEffect(1 + reactive * 0.16)
            .opacity(mode == .composer ? 0 : 0.7 + reactive * 0.3)
            .blur(radius: 26)
            .animation(.wandrInteractive, value: level)
            .allowsHitTesting(false)
    }

    /// Three concentric strokes. Same input, three spring responses — the
    /// stagger is a property of the physics, not a hand-tuned delay, so it
    /// stays coherent when the level retargets mid-flight.
    private var rings: some View {
        ZStack {
            ring(inset: 0, width: 1.5, opacity: 0.9, response: 0.22, travel: 0.10)
            ring(inset: -22, width: 1.2, opacity: 0.5, response: 0.34, travel: 0.16)
            ring(inset: -46, width: 1.0, opacity: 0.28, response: 0.48, travel: 0.22)
        }
        .opacity(mode == .composer ? 0 : 1)
        .allowsHitTesting(false)
    }

    private func ring(
        inset: CGFloat,
        width: CGFloat,
        opacity: Double,
        response: Double,
        travel: Double
    ) -> some View {
        Circle()
            .stroke(Wandr.sand.opacity(opacity), lineWidth: width)
            .frame(width: diameter - inset * 2, height: diameter - inset * 2)
            .scaleEffect(1 + reactive * travel)
            .animation(.spring(response: response, dampingFraction: 0.72), value: level)
            // Kept as its own effect so the breath and the voice compose
            // instead of fighting over one animated property.
            .scaleEffect(1 + breathIdle)
            .animation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true), value: breathing)
    }

    /// Only breathes when idle and listening is off; a live orb is already
    /// moving for a reason and doesn't need a second motive.
    private var breathIdle: CGFloat {
        guard !reduceMotion, !isListening, mode == .orb else { return 0 }
        return breathing ? 0.012 : -0.012
    }

    private var surface: some View {
        RoundedRectangle(cornerRadius: mode == .composer ? 30 : diameter / 2, style: .continuous)
            .fill(surfaceShading)
            .frame(
                maxWidth: mode == .composer ? .infinity : diameter,
                maxHeight: mode == .composer ? 60 : diameter
            )
            .frame(height: mode == .composer ? 60 : diameter)
            .overlay {
                RoundedRectangle(cornerRadius: mode == .composer ? 30 : diameter / 2, style: .continuous)
                    .strokeBorder(rimColor, lineWidth: 1)
            }
            // Contact shadow tightens as the orb "presses down" into the
            // composer, which is what sells the shape change as physical.
            .shadow(
                color: Wandr.ink.opacity(mode == .composer ? 0.06 : 0.14),
                radius: mode == .composer ? 8 : 22,
                y: mode == .composer ? 3 : 12
            )
            .scaleEffect(1 + reactive * 0.03)
            .animation(.wandrInteractive, value: level)
    }

    /// Top-lit so the face has an implied light source above it, matching the
    /// bloom. Reduce Transparency gets the flat cream instead.
    private var surfaceShading: AnyShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Wandr.cardSurface)
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    Wandr.cream,
                    Wandr.cream.mix(with: Wandr.sand, by: 0.22)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var rimColor: Color {
        isListening ? Wandr.ink.opacity(0.28) : Wandr.sand.opacity(0.7)
    }
}
