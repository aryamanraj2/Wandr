// WandrShimmer.swift Wandr A light that travels through whatever it is applied to. Used on the word a screen is waiting under, so a wait reads as ongoing rather than stuck.

import SwiftUI

/// A highlight sweeping through the glyphs of its content.
///
/// The wait screen had a progress band and a large word, and the band was the only thing moving —
/// once every two and a half seconds, across an otherwise motionless page. A screen where 90% of the
/// pixels never change reads as frozen no matter what the remaining 10% is doing, which is why it
/// still looked static after the band was added.
///
/// So the word itself carries light. This is the gesture people already read as "thinking" — a sharp
/// leading edge diffusing into a tail, travelling through the type rather than sitting behind it —
/// and it is applied to the one element on the screen large enough to show it.
private struct WandrShimmerModifier: ViewModifier {

    var active: Bool

    /// The bright centre of the travelling light, and the tone it ramps through on either side.
    ///
    /// Two colours rather than one, because a single colour fading to nothing is the thing that does
    /// not work over dark type on a pale page. Faded to transparent it reads as the letters
    /// *dissolving* — the first build swept charcoal glyphs to near-white and the word looked
    /// erased. Kept dark enough to stay legible, it reads as nothing at all: the second build was
    /// invisible. A narrow bright core with a wide, darker shoulder gives both — a glint that is
    /// clearly a light, arriving and leaving through a hue ramp rather than through the page colour.
    var core: Color
    var shoulder: Color

    /// One pass. Slow enough to read as a sweep rather than a flicker, quick enough that the screen
    /// is never still for long.
    var period: Double = 2.6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content.overlay {
                TimelineView(.animation) { timeline in
                    sweep(at: timeline.date.timeIntervalSinceReferenceDate)
                }
                // Masked to the glyphs, not to the text's box — a rectangle of light crossing a word
                // is a scanner; light inside the letterforms is the word being lit.
                .mask(content)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        } else {
            content
        }
    }

    private func sweep(at time: Double) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            // Narrow. A wide band washes the whole word at once, which is a colour change rather
            // than a light passing over it.
            let band = max(80, width * 0.34)
            let cycle = (time / period).truncatingRemainder(dividingBy: 1)
            // Linear. This was smoothstepped, on the theory that easing would make the pass feel
            // less mechanical — but smoothstep is slowest at the *ends of its travel*, which here
            // are the empty margins on either side of the word, and fastest through the middle,
            // which is the word itself. The glint spent most of each cycle parked off the type and
            // flicked across it too quickly to see; the effect read as absent. A constant rate keeps
            // the light on the letters for the share of the cycle they actually occupy.
            let eased = cycle

            LinearGradient(
                stops: [
                    .init(color: shoulder.opacity(0), location: 0.00),
                    .init(color: shoulder.opacity(0.75), location: 0.30),
                    .init(color: core, location: 0.50),
                    .init(color: shoulder.opacity(0.75), location: 0.70),
                    .init(color: shoulder.opacity(0), location: 1.00)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: band)
            .blur(radius: 4)
            .offset(x: -band + (width + band) * eased)
        }
    }
}

extension View {

    /// Sends a highlight through this view's shape while `active`. Intended for a single large
    /// element — display type, a progress fill — not for body copy, where it would fight legibility.
    ///
    /// Pick `highlight` against what it crosses: something lighter than the surface for a fill,
    /// something that shifts hue rather than brightness for dark type.
    func wandrShimmer(_ active: Bool = true, core: Color, shoulder: Color) -> some View {
        modifier(WandrShimmerModifier(active: active, core: core, shoulder: shoulder))
    }

    /// Display type on the pale page: a cyan glint arriving and leaving through indigo. The glint is
    /// light enough to read as a light, and the shoulders are dark enough that the letter is never
    /// the same tone as the page behind it.
    func wandrTypeShimmer(_ active: Bool = true) -> some View {
        wandrShimmer(active, core: Wandr.cyan, shoulder: Wandr.brand)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 30) {
        Text("Planning")
            .font(.wandrPoster(52))
            .tracking(Metrics.posterTracking)
            .foregroundStyle(Wandr.primaryText)
            .wandrTypeShimmer()
    }
    .padding(.horizontal, Metrics.gutter)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(Wandr.pageBackground)
}
