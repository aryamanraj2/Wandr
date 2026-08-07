// PlanWave.swift Wandr What the capture screen shows instead of an object: the sound itself, as it arrives. Bars enter at the right and age leftward, so the screen is a record of the last couple of seconds rather than one shape pulsing in place.

import SwiftUI

/// Whether the composer has taken the screen over. Two postures, and the wave only exists in one of
/// them — a text field has nothing to be the amplitude of.
enum CaptureMode: Equatable {
    case voice
    case composer
}

/// What the mic is doing, in the screen's own terms. Kept separate from `PlanDictation.Phase` so the
/// visual switches on a small vocabulary and never has to know about permissions or transcription
/// errors.
enum CaptureActivity: Equatable {
    /// Nothing said yet. The wave rests as a row of dots.
    case resting
    /// Mic granted, model warming. Still — movement here would claim we are already hearing
    /// something.
    case waking
    /// Live. Every bar is a real sample.
    case listening
    /// Words are in the buffer and the mic is closed. The last thing heard, held.
    case heard
}

/// A live amplitude trace.
///
/// This is the whole subject of the capture screen now. What used to be here was a 236pt sphere with
/// a drifting mesh gradient, an aura, and two echo strokes — a beautiful object that had nothing to
/// do with what the person was saying beyond getting slightly bigger. A waveform is the opposite
/// trade: far less to look at, and every pixel of it is their voice.
///
/// The history is real. `PlanDictation` publishes one smoothed scalar, and a bar chart driven
/// straight off that scalar pulses symmetrically — every bar the same height, rising and falling
/// together, which reads as a decoration reacting to sound rather than a picture of it. So samples
/// are taken on a fixed clock into a rolling buffer, and the row scrolls.
struct PlanWave: View {

    var activity: CaptureActivity

    /// Read through a closure rather than passed by value. The sampler below runs on its own clock,
    /// and a `Double` captured when the task started would be frozen at whatever the level happened
    /// to be at that instant — the wave would sample the same number forever. A closure over the
    /// observable dictation stays live.
    var level: () -> Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Coarse on purpose. At forty-odd hairlines the row was a grey smudge on a pale page — legible
    /// as "something is there", not as a waveform. Two dozen chunky bars read as a graphic at a
    /// glance and lose nothing: speech does not have detail at 3pt that anyone can see.
    private static let barCount = 25

    /// ~18 samples a second. Fast enough that speech shows its shape, slow enough that the row does
    /// not blur into a smear at 120Hz.
    private static let samplePeriod = Duration.milliseconds(56)

    /// Deliberately `WandrDashedRule`'s stroke: 3pt weight, 5 on, 9 off. At rest this row *is* that
    /// rule — the same dashes that separate one deck from the next in curation — and speaking makes
    /// it stand up. Reusing the app's existing mark rather than inventing a second one means the
    /// resting state is a thing the host has already seen, instead of an empty slot.
    private let barWidth: CGFloat = 5
    private let barSpacing: CGFloat = 9
    private let maxHeight: CGFloat = 110
    private let restHeight: CGFloat = 3

    @State private var samples = [Double](repeating: 0, count: PlanWave.barCount)

    var body: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                Capsule()
                    .fill(tint(at: index))
                    .frame(width: barWidth, height: height(for: sample))
            }
        }
        .frame(height: maxHeight, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(.wandrInteractive, value: samples)
        .task(id: reduceMotion) {
            await sample()
        }
        .accessibilityHidden(true)
    }

    // MARK: Sampling

    /// Off the display path entirely. Nothing here allocates or mutates inside `body`, and the row
    /// advances on its own cadence rather than once per frame.
    ///
    /// `heard` deliberately stops the clock. The mic has closed and there is nothing further to
    /// sample, so continuing to push silence in would scroll the sentence the host just said off the
    /// left of the screen and leave them looking at a flat line — the state that is supposed to mean
    /// "got it" would look identical to the state that means "nothing yet". Frozen, the last thing
    /// said stays on screen until the next thing is.
    private func sample() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.samplePeriod)
            guard !Task.isCancelled else { return }
            guard activity != .heard else { continue }

            let now = activity == .listening ? level() : 0

            guard !reduceMotion else {
                // Reduce Motion takes away the *travel*, not the feedback. The bars still answer the
                // voice — every one of them moves to the current level at once, shaped by a fixed
                // curve so it reads as a meter rather than a block — but nothing slides across the
                // screen. Returning early here instead, which is what this first did, left the row
                // frozen flat for the whole recording: the person most likely to be relying on a
                // visible mic indicator would have been the only one without one.
                samples = Self.stillEnvelope.map { $0 * now }
                continue
            }

            samples.removeFirst()
            samples.append(now)
        }
    }

    /// A fixed symmetric curve, fullest in the middle. Only used under Reduce Motion, where every
    /// bar carries the same instant and a flat row of equal heights would read as a progress bar.
    private static let stillEnvelope: [Double] = (0..<barCount).map { index in
        let t = Double(index) / Double(barCount - 1)
        return 0.45 + 0.55 * sin(t * .pi)
    }

    // MARK: Appearance

    private func height(for sample: Double) -> CGFloat {
        guard activity != .resting || sample > 0 else { return restHeight }
        // Square-rooted, because loudness is not linear and a raw level spends most of its range in
        // the bottom third — untransformed, ordinary speech barely lifts off the floor.
        let shaped = sqrt(max(0, min(1, sample)))
        return max(restHeight, shaped * maxHeight)
    }

    /// Newest at full strength, ageing back toward the page. Sound arriving and dissipating, which
    /// is also what makes the direction of travel readable when every bar happens to be the same
    /// height.
    ///
    /// The age ramp is dropped at rest. A resting row is not a trace of anything — nothing has
    /// flowed through it — so shading it as though something had made the left half fade to
    /// invisible against the page, and the screen's only resting element disappeared. Uniform, it
    /// reads as a row waiting to be used.
    private func tint(at index: Int) -> Color {
        guard activity != .resting else { return Wandr.mist }

        let age = Double(index) / Double(Self.barCount - 1)
        let base: Color = switch activity {
        case .resting:           Wandr.mist
        case .waking:            Wandr.mist.mix(with: Wandr.brand, by: 0.4)
        case .listening, .heard: Wandr.brand
        }
        // Floors at 0.28 rather than 0: a bar that fades to invisible shortens the row from the left
        // and makes the wave look like it is being eaten.
        return base.opacity(0.28 + age * 0.72)
    }
}

#Preview("Listening") {
    PlanWave(activity: .listening, level: { Double.random(in: 0.05...0.9) })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Wandr.pageBackground)
}

#Preview("Resting") {
    PlanWave(activity: .resting, level: { 0 })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Wandr.pageBackground)
}
