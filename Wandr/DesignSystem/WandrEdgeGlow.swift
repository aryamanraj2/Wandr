// WandrEdgeGlow.swift Wandr The app's one ambient signal: a light cyan gradient that lives on the screen's own border and says Wandr is attending to you. Used where the app is waiting, listening, or working — never as decoration on a screen that is merely sitting there.

import SwiftUI

/// What the app is doing, in the border's terms. Three states rather than a brightness knob, so a
/// screen declares its condition and the visual follows, instead of every caller inventing numbers.
enum WandrAttention: Equatable {

    /// Waiting on something outside the app — a Siri summary that has not arrived. A held breath:
    /// present enough to say the screen is live, quiet enough to ignore.
    case resting

    /// Listening to the person right now. The brightest of the three, and the only one that answers
    /// to a live input.
    case attending

    /// Doing work the person is waiting on. Steady and directional rather than reactive.
    case working
}

/// A soft cyan bloom on the screen's border.
///
/// This replaces what used to be a 236pt glowing sphere in the middle of the capture screen. The
/// object had to be looked at; a border does the same job — telling you the mic is open — while
/// leaving the middle of the page to the content, which is the direction iOS itself went when Siri
/// stopped being a ball and became the edge of the display.
///
/// The moving part is one `AngularGradient` with a near-opaque leading edge that diffuses into a
/// long tail, rotating slowly. That shape is the whole idea: a uniform ring reads as a static
/// border treatment, whereas a bright head trailing off says something is travelling around the
/// screen. A steady base ring sits underneath so the border never fully disappears between passes.
private struct WandrEdgeGlowModifier: ViewModifier {

    let attention: WandrAttention

    /// 0…1 live input, when there is one. Only `.attending` uses it; the other states have nothing
    /// meaningful to answer to and pretending otherwise would be motion without a cause.
    var level: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.overlay {
            Group {
                if reduceMotion {
                    // Not removed — held. The border still says "listening"; it just stops
                    // travelling. Dropping it entirely would take a state indicator away from the
                    // people most likely to be relying on it.
                    ring(rotation: 0, headOpacity: (base + peak) / 2)
                } else {
                    TimelineView(.animation) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        ring(rotation: t * degreesPerSecond, headOpacity: peak)
                    }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .animation(.wandrTransition, value: attention)
        }
    }

    // MARK: Composition

    /// Two passes over the same path: a wide blurred bloom that reads as light, and a tighter, less
    /// blurred pass inside it that gives the bloom an edge to have come from. One pass alone is
    /// either a hard border or a vague haze.
    private func ring(rotation: Double, headOpacity: Double) -> some View {
        ZStack {
            edge(gradient: sweep(rotation: rotation, headOpacity: headOpacity),
                 lineWidth: 46, blur: 38)
            edge(gradient: sweep(rotation: rotation, headOpacity: headOpacity * 0.9),
                 lineWidth: 16, blur: 13)
        }
    }

    /// A bare `ConcentricRectangle` takes its corners from the container it lands in, which at the
    /// root of a full-screen view is the display itself — so the bloom follows the physical screen's
    /// radius rather than a rounded rect we guessed at. `stroke` straddles the path and the outer
    /// half is clipped away by the window, which is exactly what makes the light look like it is
    /// coming from off the edge rather than being drawn just inside it.
    private func edge(gradient: AngularGradient, lineWidth: CGFloat, blur: CGFloat) -> some View {
        ConcentricRectangle()
            .stroke(gradient, lineWidth: lineWidth)
            .blur(radius: blur)
    }

    /// The sharp head, the diffusing tail, and a floor that never reaches zero.
    ///
    /// The tint is cyan pulled a step toward indigo rather than cyan itself. The page *is* cyan
    /// carried most of the way to white, so the brand tone laid straight onto it at any honest
    /// opacity vanished — the first build of this was invisible on device and read as a rendering
    /// artefact in the corners. A step deeper separates from the field while staying unmistakably
    /// the same light blue.
    private func sweep(rotation: Double, headOpacity: Double) -> AngularGradient {
        let tint = Wandr.cyan.mix(with: Wandr.indigo, by: 0.22)
        return AngularGradient(
            stops: [
                .init(color: tint.opacity(base), location: 0.00),
                .init(color: tint.opacity(base), location: 0.34),
                // The tail: a long ramp up, so most of the border is faint and the eye is drawn to
                // the one place that is bright.
                .init(color: tint.opacity(base + (headOpacity - base) * 0.45), location: 0.72),
                // The head. Near its peak and then cut, rather than easing out symmetrically — a
                // gradient that fades in and out at the same rate has no direction.
                .init(color: tint.opacity(headOpacity), location: 0.94),
                .init(color: tint.opacity(base), location: 1.00)
            ],
            center: .center,
            angle: .degrees(rotation)
        )
    }

    // MARK: Intensity

    /// Reduce Transparency lifts the floor and drops the travel: the border becomes a plainer, more
    /// solid edge rather than a translucent bloom, which is the setting's actual request.
    private var base: Double {
        let floor: Double = switch attention {
        case .resting:   0.26
        case .attending: 0.38
        case .working:   0.34
        }
        return reduceTransparency ? floor + 0.10 : floor
    }

    private var peak: Double {
        switch attention {
        case .resting:   return 0.52
        case .attending: return 0.92 + level * 0.08
        case .working:   return 0.86
        }
    }

    /// Resting is a tide, attending is a pulse, working is a steady pass. Each state's rate is what
    /// distinguishes it as much as its brightness does.
    private var degreesPerSecond: Double {
        switch attention {
        case .resting:   return 22
        case .attending: return 74 + level * 60
        case .working:   return 52
        }
    }
}

extension View {

    /// Puts a soft cyan bloom on the screen's border. Apply to a full-screen container, outside its
    /// background — it ignores the safe area on purpose, because the signal is the edge of the
    /// display rather than the edge of the content.
    func wandrEdgeGlow(_ attention: WandrAttention, level: Double = 0) -> some View {
        modifier(WandrEdgeGlowModifier(attention: attention, level: level))
    }
}

#Preview("Resting") {
    Wandr.pageBackground
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .wandrEdgeGlow(.resting)
}

#Preview("Attending") {
    Wandr.pageBackground
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .wandrEdgeGlow(.attending, level: 0.7)
}

#Preview("Working") {
    Wandr.pageBackground
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .wandrEdgeGlow(.working)
}
