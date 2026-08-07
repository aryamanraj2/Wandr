// WandrSweep.swift Wandr The thinking band. A light travels the width of the page while the app works, and the part of the band behind it fills in with what has actually been finished — so the motion says "still going" and the fill says "this far", and neither has to lie about the other.

import SwiftUI

/// A horizontal band that reads as a process rather than a loop.
///
/// The one rule worth borrowing from the assistant UIs that do this well is the *shape of the
/// gradient*: a near-opaque leading edge that diffuses into a long tail. A blob that fades in and
/// out at the same rate has no direction, and a bar that pulses in place says only "busy". A head
/// with a tail says where the work is going, which is the difference between motion that informs
/// and motion that decorates.
///
/// The second half of the idea is that the band is not only the head. `progress` fills the track
/// behind it from the pipeline's real stage, so the screen is making a claim it can keep. When
/// there is no stage to report — the on-device extraction is a single call with no interior — the
/// caller passes `nil` and gets the head alone, which promises nothing.
struct WandrSweep: View {

    /// 0…1 of real, completed work. `nil` when the caller genuinely does not know, in which case
    /// the track stays empty rather than filling on a timer.
    var progress: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The lit core. Everything else on this band is either behind it or a bloom around it.
    private let trackHeight: CGFloat = 7

    /// One head per row of light.
    private struct Head {
        /// Where in its own cycle it starts.
        let phase: Double
        /// How long its pass takes. Slow enough to read as travelling rather than flashing.
        let period: Double
        /// Multiplier on the head's brightness, so the extra passes layer under the main two rather
        /// than competing with them.
        let strength: Double
    }

    /// Three heads on two clocks.
    ///
    /// Two of them are half a cycle apart on the same 2.4s period, because one comet on that loop
    /// leaves well over a second with nothing on screen but a static bar, and a band that is empty
    /// half the time reads as a bar that has stopped.
    ///
    /// The third is the fix for the next problem after that one: two lights on a shared clock repeat
    /// the *same picture* every 2.4 seconds, and a pattern the eye can learn in one cycle is a
    /// pattern it stops seeing by the third. A fainter head on 5.3s never lands in the same place
    /// twice against the other two, so the band keeps presenting an arrangement that has not been
    /// seen before — which is what "still working" has to look like over a wait measured in tens of
    /// seconds rather than in beats.
    private let heads: [Head] = [
        Head(phase: 0.00, period: 2.40, strength: 1.00),
        Head(phase: 0.50, period: 2.40, strength: 0.86),
        Head(phase: 0.25, period: 5.30, strength: 0.28)
    ]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack(alignment: .leading) {
                track

                if let progress {
                    filled(width: width, progress: progress.clamped())
                }

                if reduceMotion {
                    // No travel. The fill above still moves as stages complete, and the caption and
                    // dots under the band carry the rest — so nothing about the state is lost, only
                    // the oscillation.
                    EmptyView()
                } else {
                    TimelineView(.animation) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        ZStack(alignment: .leading) {
                            if let progress {
                                edge(width: width, progress: progress.clamped(), at: t)
                            }

                            ForEach(Array(heads.enumerated()), id: \.offset) { _, head in
                                comet(width: width, head: head, at: t)
                            }
                        }
                        // Sized to the track before it is masked. Without this the stack measures
                        // one comet wide — `offset` moves a view without resizing it — and the mask
                        // below, centred in whatever it is given, lands nowhere near the rail it is
                        // supposed to describe: it cut the passes off around three-quarters of the
                        // way along and left the last quarter of the band dead.
                        .frame(width: width, alignment: .leading)
                        // A head's travel runs a tail's length past the end of the track, and
                        // nothing was stopping it drawing there — so each pass finished as a
                        // detached dark stub floating in the page's margin, past the capsule's own
                        // rounded end. The light belongs to the track. Faded rather than cut,
                        // because a hard clip at the track's ends replaces the stub with two
                        // vertical edges, which is a worse artefact than the one it fixes.
                        .mask { railMask(width: width) }
                    }
                }
            }
            // Pinned to the track's own height, not the container's. The comet's bloom is three and
            // a half times taller than the track, and letting it set the stack's height meant the
            // track and the fill were being centred inside different boxes — they drifted apart
            // vertically and the band rendered as two separate rules. The bloom overflows this
            // frame, which is exactly what a bloom should do.
            .frame(height: trackHeight)
            .frame(height: proxy.size.height, alignment: .center)
        }
        .frame(height: 26)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Layers

    /// Opaque across the track, gone within a few points of either end.
    private func railMask(width: CGFloat) -> some View {
        let fade = max(0.004, 5 / max(width, 1))
        return LinearGradient(
            stops: [
                .init(color: .black.opacity(0), location: 0),
                .init(color: .black, location: fade),
                .init(color: .black, location: 1 - fade),
                .init(color: .black.opacity(0), location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: width)
    }

    private var track: some View {
        Capsule()
            .fill(Wandr.mist.opacity(0.42))
            .frame(height: trackHeight)
    }

    /// What is genuinely done. Indigo into cyan — the acting tone resolving into the structural one,
    /// which is the same direction the rest of the app moves in as something settles.
    ///
    /// The completed stretch shimmers too. It is the part of the band that represents work already
    /// standing, and a solid unchanging block is exactly what made the screen look finished-and-stuck
    /// rather than finished-so-far.
    private func filled(width: CGFloat, progress: Double) -> some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [Wandr.indigo, Wandr.cyan],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: max(trackHeight, width * progress), height: trackHeight)
            .wandrShimmer(!reduceMotion, core: Wandr.cream, shoulder: Wandr.cyan)
            .animation(.wandrTransition, value: progress)
    }

    /// The head and its tail. Two passes: a blurred bloom that reads as light spilling off the band,
    /// and a tight core inside it so the light has a source. The gradient runs transparent → warm at
    /// the *trailing* edge because that is the direction of travel — the bright end is the front.
    private func comet(width: CGFloat, head: Head, at time: Double) -> some View {
        let tail = max(140, width * 0.46)
        let travel = width + tail
        // A slow wobble on the phase rather than on the period: changing the period outright would
        // teleport the head, since position is read straight off the clock rather than integrated.
        // Shifting where in its cycle the head *is*, smoothly, varies its speed by a few percent
        // either way — enough that the pass never resolves into a metronome, small enough that it
        // never reads as stuttering.
        let drift = 0.12 * sin(time / 5.1)
        let cycle = ((time / head.period) + head.phase + drift).truncatingRemainder(dividingBy: 1)
        let x = -tail + travel * cycle

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(cometGradient(headOpacity: 0.7 * head.strength))
                .frame(width: tail, height: trackHeight * 3.6)
                .blur(radius: 11)

            Capsule()
                .fill(cometGradient(headOpacity: head.strength))
                .frame(width: tail, height: trackHeight)
                .blur(radius: 1)
        }
        .offset(x: x)
    }

    /// A small warm bloom sitting exactly where the finished work ends.
    ///
    /// This is the only point on the band that means something specific — the boundary between what
    /// is done and what is not — and before this it was just where one colour stopped. Breathing, it
    /// becomes the place the work is currently happening, and it is the one thing on the screen that
    /// both moves continuously *and* sits at a position the app can defend. The pulse is slower than
    /// anything else on the band so it never gets counted in with the passing heads.
    private func edge(width: CGFloat, progress: Double, at time: Double) -> some View {
        let x = max(trackHeight, width * progress)
        let size = trackHeight * 5.5
        let breath = 0.5 + 0.5 * sin(time * 1.15)

        return Circle()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: Wandr.cream.opacity(0.34 + 0.34 * breath), location: 0.00),
                        .init(color: Wandr.cyan.opacity(0.22 + 0.20 * breath), location: 0.45),
                        .init(color: Wandr.cyan.opacity(0), location: 1.00)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
            .offset(x: x - size / 2)
            .animation(.wandrTransition, value: progress)
    }

    /// Cream at the head is deliberate: it is the palette's single warm tone, reserved throughout
    /// the app for the thing that is currently happening. Everything behind it cools back to indigo
    /// and then to nothing.
    private func cometGradient(headOpacity: Double) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Wandr.indigo.opacity(0), location: 0.00),
                .init(color: Wandr.indigo.opacity(headOpacity * 0.30), location: 0.52),
                .init(color: Wandr.cyan.opacity(headOpacity * 0.78), location: 0.84),
                .init(color: Wandr.cream.opacity(headOpacity), location: 0.99),
                .init(color: Wandr.cream.opacity(0), location: 1.00)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private extension Double {
    func clamped() -> Double { Swift.min(1, Swift.max(0, self)) }
}

#Preview("Half done") {
    VStack {
        WandrSweep(progress: 0.5)
        WandrSweep(progress: nil)
    }
    .padding(.horizontal, Metrics.gutter)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Wandr.pageBackground)
}
