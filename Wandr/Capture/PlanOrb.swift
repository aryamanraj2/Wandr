// PlanOrb.swift Wandr The one object on the capture screen, and the only place in the app that gets to look alive. Every layer is cut from the same `OrbShape`, so the collapse into a text field is one shape whose rect changes and whose wobble drains to zero — not two views crossfading. Layers, back to front: 1. aura — the silhouette itself, scaled and blurred, so the light around the orb is the orb's own shape rather than a generic circular glow 2. echoes — two outer strokes on their own wave seeds, arriving late 3. body — a drifting `MeshGradient` clipped to the silhouette: lit top-left, deep bottom-right, warming toward cream as the voice comes up 4. specular — one soft highlight that gives the face a light source 5. rim — a creamy hairline that gains contrast while listening 6. face — the mic, which shrinks into the composer field's leading icon rather than being replaced by it

import SwiftUI

/// Declared outside `PlanOrb` on purpose: a type nested in a generic is distinct per specialization, so `PlanOrb<A>.Mode` and `PlanOrb<B>.Mode` would not be the same type for a caller holding it in `@State`.
enum OrbMode: Equatable {
    case orb
    case composer
}

/// What the orb is doing, in the orb's own terms. Kept separate from `PlanDictation.Phase` so the
/// visual has one small vocabulary to switch on and does not have to know about permissions or
/// transcription errors.
enum OrbActivity: Equatable {
    /// Nothing has been said yet. Slow breath, cool and closed.
    case resting
    /// Mic granted, model warming. Holds still — a pulse here would claim we are hearing something.
    case waking
    /// Live. The silhouette and the gradient both answer to the voice.
    case listening
    /// Words are in the buffer and the mic is closed. Settled, warm, done.
    case heard
}

struct PlanOrb<Face: View>: View {

    var mode: OrbMode
    var activity: OrbActivity
    /// 0...1 live microphone amplitude.
    var level: Double
    /// What sits on the face — in practice the mic glyph and, once flattened, the composer field beside it. It shares the surface's frame so it travels with the morph instead of being crossfaded on top of it.
    @ViewBuilder var face: Face

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var diameter: CGFloat { 236 }
    private var composerHeight: CGFloat { 60 }

    /// Reduce Motion keeps every state legible through colour, size, and rim contrast, and drops
    /// only the parts that oscillate: the drift clock and the voice-driven travel.
    private var animated: Bool { !reduceMotion }

    var body: some View {
        Group {
            if animated {
                TimelineView(.animation) { timeline in
                    stack(phase: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                stack(phase: 0)
            }
        }
        .frame(maxWidth: mode == .composer ? .infinity : nil, alignment: .center)
    }

    // MARK: Composition

    private func stack(phase: Double) -> some View {
        ZStack {
            aura(phase: phase)
            echoes(phase: phase)
            core(phase: phase)
            face
                .frame(maxWidth: mode == .composer ? .infinity : diameter)
                .frame(height: mode == .composer ? composerHeight : diameter)
        }
    }

    // MARK: Layers

    /// The orb's own silhouette, scaled up and blurred: light that has the shape of the thing
    /// casting it. A plain radial gradient reads as a sticker's drop shadow; this reads as glow.
    private func aura(phase: Double) -> some View {
        silhouette(phase: phase, seed: 2.4, wobble: wobble * 1.25)
            .fill(
                RadialGradient(
                    colors: [
                        auraTone.opacity(0.55),
                        auraTone.opacity(0.16),
                        auraTone.opacity(0)
                    ],
                    center: .center,
                    startRadius: diameter * 0.18,
                    endRadius: diameter * 0.72
                )
            )
            .frame(width: diameter, height: diameter)
            .scaleEffect(1.34 + reactive * 0.30)
            .blur(radius: 30)
            .opacity(mode == .composer ? 0 : 0.55 + reactive * 0.45)
            .allowsHitTesting(false)
    }

    /// Two strokes on their own wave seeds and their own springs. Same input, different response —
    /// the stagger is a property of the physics rather than a hand-tuned delay, so it stays coherent
    /// when the level retargets mid-flight.
    private func echoes(phase: Double) -> some View {
        ZStack {
            echo(phase: phase, seed: 1.1, scale: 1.10, travel: 0.13, width: 1.4, opacity: 0.40, response: 0.26)
            echo(phase: phase, seed: 3.7, scale: 1.22, travel: 0.20, width: 1.0, opacity: 0.22, response: 0.40)
        }
        .opacity(mode == .composer ? 0 : echoPresence)
        .animation(.wandrResponse, value: activity)
        .allowsHitTesting(false)
    }

    /// The echoes are the orb answering a voice, so they carry the weight of there being one. Held
    /// at full strength through every state they stop reading as radiated sound and start reading as
    /// two permanent hairlines drawn around the shape — a diagram of an orb rather than an orb.
    private var echoPresence: Double {
        switch activity {
        case .resting:   return 0.28
        case .waking:    return 0.50
        case .listening: return 0.80 + level * 0.20
        case .heard:     return 0.44
        }
    }

    private func echo(
        phase: Double,
        seed: Double,
        scale: CGFloat,
        travel: Double,
        width: CGFloat,
        opacity: Double,
        response: Double
    ) -> some View {
        silhouette(phase: phase, seed: seed, wobble: wobble * 1.4)
            .stroke(Wandr.brand.opacity(opacity), lineWidth: width)
            .frame(width: diameter, height: diameter)
            .scaleEffect(scale + reactive * travel)
            .animation(.spring(response: response, dampingFraction: 0.72), value: reactive)
    }

    /// The face. A drifting mesh rather than a flat fill or a two-stop gradient: nine control points
    /// on unequal sine drifts means the light on the body never sits still, which is what separates
    /// an object that is listening from a coloured circle. Reduce Transparency gets the flat tone.
    private func core(phase: Double) -> some View {
        let outline = silhouette(phase: phase, seed: 0, wobble: wobble)
        let shadowRadius: CGFloat = mode == .composer ? 8 : 26
        let shadowOffset: CGFloat = mode == .composer ? 3 : 14

        return outline
            .fill(surfaceShading(phase: phase))
            .overlay { specular }
            // Body and highlight are clipped together, here, where the view's frame is the orb's.
            // Clipping the highlight inside its own layer instead cuts it to that layer's much
            // smaller frame, which is a hard-edged rounded rect sitting centred on the face.
            .clipShape(outline)
            // Rim last and outside the clip: `stroke` straddles the path, so clipping it would keep
            // only its inner half.
            .overlay { outline.stroke(rimColor, lineWidth: 1) }
            .frame(
                maxWidth: mode == .composer ? .infinity : diameter,
                maxHeight: mode == .composer ? composerHeight : diameter
            )
            .frame(height: mode == .composer ? composerHeight : diameter)
            // Contact shadow tightens as the orb presses down into the composer, which is what
            // sells the shape change as one object changing posture.
            .shadow(
                color: Wandr.charcoal.opacity(mode == .composer ? 0.10 : 0.22),
                radius: shadowRadius,
                y: shadowOffset
            )
            .scaleEffect(1 + reactive * 0.035)
            .animation(.wandrInteractive, value: reactive)
    }

    /// One soft light source, up and to the left, matching the aura. It deliberately does no
    /// clipping of its own — `core` clips it along with the body, so the falloff is bounded by the
    /// silhouette and curves with the wobble. Anything that trims this layer at its own size gives
    /// the highlight an edge of its own, and an edge is what turns a light into a panel.
    private var specular: some View {
        Ellipse()
            .fill(Wandr.cream.opacity(mode == .composer ? 0.05 : 0.18))
            .frame(width: diameter * 0.62, height: diameter * 0.44)
            .offset(x: -diameter * 0.13, y: -diameter * 0.20)
            .blur(radius: 26)
            .allowsHitTesting(false)
    }

    // MARK: Shape

    /// Every layer asks for the same silhouette, differing only in wave seed and amplitude. The idle
    /// breath lives here rather than in a repeating animation: it is one more term in the wave, so
    /// it composes with the voice instead of fighting it for the same animated property.
    private func silhouette(phase: Double, seed: Double, wobble: Double) -> OrbShape {
        OrbShape(wobble: wobble, phase: animated ? phase * driftRate : 0, seed: seed)
    }

    /// How fast the silhouette drifts. Resting is a slow tide; listening is quick and answerable.
    private var driftRate: Double {
        switch activity {
        case .resting:   return 0.42
        case .waking:    return 0.30
        case .listening: return 0.95 + level * 0.9
        case .heard:     return 0.34
        }
    }

    /// The composer is a text field and must be an exact capsule, so the wobble drains to zero as
    /// the morph runs — the shape stops being alive at the same moment it stops being a subject.
    private var wobble: Double {
        guard mode == .orb else { return 0 }
        guard animated else { return 0.012 }

        switch activity {
        case .resting:   return 0.030
        case .waking:    return 0.022
        case .listening: return 0.042 + level * 0.085
        case .heard:     return 0.026
        }
    }

    /// Voice-driven travel, suppressed under Reduce Motion — the size and colour feedback stay, only
    /// the oscillation goes.
    private var reactive: Double {
        animated ? level : 0
    }

    // MARK: Colour

    private func surfaceShading(phase: Double) -> AnyShapeStyle {
        if reduceTransparency {
            // Same light axis, same warmth, no mesh: the flat path is the diagonal ramp sampled at
            // its two ends rather than a separate look.
            return AnyShapeStyle(
                LinearGradient(colors: [surfaceTone(depth: 0.1), surfaceTone(depth: 0.9)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        }
        return AnyShapeStyle(
            MeshGradient(
                width: 3,
                height: 3,
                points: meshPoints(phase: animated ? phase : 0),
                colors: meshColors,
                smoothsColors: true
            )
        )
    }

    /// Corners are pinned so the mesh always covers the silhouette; only the edge midpoints and the
    /// centre drift, on four unequal rates so the pattern does not visibly cycle.
    private func meshPoints(phase: Double) -> [SIMD2<Float>] {
        let t = phase * 0.55
        let m: Float = mode == .composer ? 0.03 : 0.11

        func f(_ v: Double) -> Float { Float(v) }

        return [
            SIMD2(0, 0),
            SIMD2(0.5 + m * f(sin(t * 0.70)), 0),
            SIMD2(1, 0),

            SIMD2(0, 0.5 + m * f(cos(t * 0.62 + 1.9))),
            SIMD2(0.5 + m * f(sin(t * 0.53 + 1.2)), 0.5 + m * f(cos(t * 0.47 + 0.4))),
            SIMD2(1, 0.5 + m * f(sin(t * 0.58 + 2.1))),

            SIMD2(0, 1),
            SIMD2(0.5 + m * f(cos(t * 0.66 + 0.9)), 1),
            SIMD2(1, 1)
        ]
    }

    /// Lit toward cyan at the top-left, indigo through the middle, charcoal-indigo at the
    /// bottom-right — one implied light source, so the body reads as volume rather than a tinted
    /// disc. Every stop is *derived* from how far it sits down that one axis rather than written
    /// out by hand, which is what keeps the surface monotonic: no stop can come out brighter than
    /// its neighbours and pool into a patch behind whatever the face is showing. The centre is not
    /// a light — it is simply the middle of the ramp, the same tone as the rest of its diagonal.
    private var meshColors: [Color] {
        // Column + row, normalised: 0 at the lit corner, 1 at the deep one.
        (0..<9).map { surfaceTone(depth: Double($0 % 3 + $0 / 3) / 4) }
    }

    /// The body's tone at `depth` along the light axis, 0 lit to 1 deep. Voice warmth is weighted
    /// toward the lit end, so a rising level reads as the light source itself warming — the app's
    /// one warm tone doing the job the palette reserves it for — rather than as a panel switching
    /// on under the glyph. `heard` holds that warmth after the mic closes, so a finished capture
    /// *looks* finished without needing a label to say so.
    private func surfaceTone(depth: Double) -> Color {
        let warmth: Double = switch activity {
        case .resting:   0.02
        case .waking:    0.05
        case .listening: 0.08 + level * 0.22
        case .heard:     0.20
        }

        let lift: Double = activity == .resting ? 0.0 : 0.06

        let base: Color
        if depth <= 0.5 {
            let toward: Double = (1 - depth * 2) * (0.44 + lift)
            base = Wandr.brand.mix(with: Wandr.cyan, by: toward)
        } else {
            let toward: Double = (depth - 0.5) * 2 * 0.46
            base = Wandr.brand.mix(with: Wandr.charcoal, by: toward)
        }

        let warmed: Double = warmth * (1 - depth)
        return base.mix(with: Wandr.cream, by: warmed)
    }

    private var auraTone: Color {
        switch activity {
        case .resting, .waking: return Wandr.brand
        case .listening:        return Wandr.brand.mix(with: Wandr.cream, by: 0.22)
        case .heard:            return Wandr.brand.mix(with: Wandr.cream, by: 0.30)
        }
    }

    /// A warm hairline that brightens when the mic opens. On an indigo face the rim has to be the
    /// light tone — an indigo rim on an indigo body is no rim at all.
    private var rimColor: Color {
        switch activity {
        case .resting:   return Wandr.cream.opacity(0.20)
        case .waking:    return Wandr.cream.opacity(0.34)
        case .listening: return Wandr.cream.opacity(0.52 + level * 0.35)
        case .heard:     return Wandr.cream.opacity(0.46)
        }
    }
}

#Preview("Listening") {
    PlanOrb(mode: .orb, activity: .listening, level: 0.6) {
        Image(systemName: "mic.fill")
            .font(.system(size: 46))
            .foregroundStyle(Wandr.onBrand)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Wandr.pageBackground)
}

#Preview("Resting") {
    PlanOrb(mode: .orb, activity: .resting, level: 0) {
        Image(systemName: "mic.fill")
            .font(.system(size: 46))
            .foregroundStyle(Wandr.onBrand)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Wandr.pageBackground)
}
