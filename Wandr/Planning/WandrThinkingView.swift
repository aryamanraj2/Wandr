// WandrThinkingView.swift Wandr The screen you wait on. Both waits in the app — the on-device extraction and the grounded planning run — render this, so the two look like one app doing two things rather than two spinners someone wrote on different days.

import SwiftUI

/// A wait that says what it is doing.
///
/// What was here before was `ProgressView().controlSize(.large)` over two lines of text, twice,
/// inlined in `RootView`. A system spinner is the right call when a wait is short and featureless;
/// this one is neither. The planning run walks four named phases, the longest of which is genuinely
/// slow, and it already writes host-readable lines for each of them — it just threw them away.
///
/// So the screen makes two separate claims and keeps them apart:
///
/// - **the fill** behind `WandrSweep`'s head, and the dots, are *real*. They move when
///   `PlanningState` moves and at no other time.
/// - **the travelling head** is activity, not progress. It says the app is still running. It never
///   implies a position.
///
/// Conflating those is how loading screens end up lying — a bar that eases to 90% on a timer and
/// then sits there. Where there is genuinely nothing to report, the caller passes no stage at all
/// and the track stays empty rather than filling on a clock.
struct WandrThinkingView: View {

    /// The masthead. One or two words — this is the largest type in the app and a sentence at this
    /// size stops being a statement.
    let title: String

    /// The live pipeline phase, when the caller has one.
    var stage: PlanningState?

    /// What to say when there is no stage stream to read. The on-device extraction is a single
    /// model call with no interior, so it gets a fixed line and an empty track instead of invented
    /// milestones.
    var caption: String?

    /// The four phases a host actually waits through. `needsDetails`, `ready`, `failed` and
    /// `cancelled` are outcomes rather than legs, and `idle` is the moment before the first one.
    private static let legs: [PlanningState] = [.extracting, .researching, .validating, .curating]

    private var line: String? {
        stage?.hostDescription ?? caption
    }

    /// How far the leg list has been walked. `nil` before the first phase lands, so the dots start
    /// empty rather than pre-lit.
    private var legIndex: Int? {
        guard let stage else { return nil }
        return Self.legs.firstIndex(of: stage)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The screen arrives rather than appearing. Waiting begins the moment this is on screen, and a
    /// wait that cuts in from nothing has already spent its first impression looking like a stall.
    @State private var arrived = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            WandrSweep(progress: stage?.hostProgress)
                .padding(.bottom, 24)
                .opacity(arrived ? 1 : 0)
                .scaleEffect(x: arrived ? 1 : 0.9, anchor: .leading)
                .animation(reduceMotion ? .easeOut(duration: 0.2) : .wandrEnter(0), value: arrived)

            WandrMasthead(title: title, size: 52, shimmering: true)
                .padding(.bottom, 22)
                .opacity(arrived ? 1 : 0)
                .offset(y: arrived || reduceMotion ? 0 : 10)
                .animation(reduceMotion ? .easeOut(duration: 0.2) : .wandrEnter(1), value: arrived)

            if legIndex != nil {
                legDots
                    .padding(.bottom, 14)
                    .opacity(arrived ? 1 : 0)
                    .animation(reduceMotion ? .easeOut(duration: 0.2) : .wandrEnter(2), value: arrived)
            }

            if let line {
                Text(line)
                    .font(.body)
                    .foregroundStyle(Wandr.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(line)
                    // Staged, not crossfaded. `contentTransition(.opacity)` draws both strings at
                    // once, and two captions of different lengths on top of each other is unreadable
                    // — at large text sizes "Finding places nearby" and "Checking what actually
                    // fits" overlapped into noise. The old line leaves first and the new one arrives
                    // into the space it left.
                    //
                    // It also travels now. A caption that fades out and fades back in the same spot
                    // is a *replacement*; one that leaves upward and is followed up from below is a
                    // list advancing, which is what the pipeline is actually doing. Eight points,
                    // because the line does not move far enough to shift anything under it.
                    .transition(.asymmetric(
                        insertion: .opacity
                            .combined(with: .offset(y: reduceMotion ? 0 : 8))
                            .animation(.easeOut(duration: 0.26).delay(0.16)),
                        removal: .opacity
                            .combined(with: .offset(y: reduceMotion ? 0 : -8))
                            .animation(.easeIn(duration: 0.14))
                    ))
            }

            // Two below to one above: the block settles a third of the way down rather than dead
            // centre. Centred, a short block on a tall empty page reads as content that failed to
            // load; held high, the emptiness under it reads as space that was left on purpose.
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.gutter)
        .animation(.wandrResponse, value: line)
        // Inside the page colour, outside the border glow. Everything else that moves on this screen
        // is small and hard-edged — a 7pt band, a glint inside a word, four 9pt dots — and small
        // motion on a large still field reads as a still field. This is the part that gives the
        // other two-thirds of the page something to be doing.
        .wandrDrift()
        .background(Wandr.pageBackground)
        .wandrEdgeGlow(.working)
        .onAppear { arrived = true }
        // One element, one announcement. Read as four (title, three dots, caption) VoiceOver would
        // have to be swiped through to learn the app is merely busy.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.map { "\(title). \($0)" } ?? title)
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: Legs

    /// Four dots joined by hairlines. Filled behind the current leg, ringed ahead of it — the same
    /// "done / doing / to come" reading the numbered rail on the setup screen uses, so a host who
    /// has seen one recognises the other.
    ///
    /// The dot for the leg that is *running* breathes. The ones behind it are finished and hold
    /// still, which is what makes the breathing one legible as the live edge of the work rather than
    /// as decoration applied to the whole row.
    @ViewBuilder
    private var legDots: some View {
        if reduceMotion {
            dots(pulse: 1)
        } else {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                dots(pulse: 1 + 0.22 * sin(t * 2.4))
            }
        }
    }

    private func dots(pulse: Double) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.legs.enumerated()), id: \.offset) { index, _ in
                if index != 0 {
                    Rectangle()
                        .fill(Wandr.mist.opacity(reached(index) ? 0.9 : 0.45))
                        .frame(width: 22, height: 1.5)
                }

                Circle()
                    .fill(reached(index) ? Wandr.brand : Wandr.mist.opacity(0.35))
                    .frame(width: 9, height: 9)
                    .scaleEffect(index == legIndex ? pulse : 1)
                    .overlay {
                        // Only on the dot the run has just arrived at, and only once per arrival.
                        // Keyed on `legIndex` so a new leg builds a new ripple, which is what makes
                        // it fire.
                        if index == legIndex, !reduceMotion {
                            LegArrival().id(legIndex)
                        }
                    }
            }
        }
        .animation(.wandrTransition, value: legIndex)
        .accessibilityHidden(true)
    }

    private func reached(_ index: Int) -> Bool {
        guard let legIndex else { return false }
        return index <= legIndex
    }
}

/// The one moment in a long wait when something has genuinely happened.
///
/// Four times in a run the pipeline finishes a leg, and until now that news was carried by a colour
/// change on a 9pt dot and a caption swap — both of which land inside a quarter-second and neither of
/// which the eye is looking at, because it has spent the last twenty seconds being told nothing. A
/// ring leaving the dot puts the change where the change happened, and is large and brief enough to
/// catch peripherally.
///
/// Deliberately not a flash or a bounce: this marks *progress*, and the vocabulary for progress in
/// this app is something leaving its source, the same as the band's heads and the border's sweep.
private struct LegArrival: View {

    @State private var expanded = false

    var body: some View {
        Circle()
            // The frame grows, not the scale. `scaleEffect` takes the stroke with it, so the ring
            // arrived at three times its width as a three-times-heavier line — a thickening blob
            // rather than a ripple. A hairline that stays a hairline is the thing that reads as
            // something leaving.
            .stroke(Wandr.brand, lineWidth: 1.5)
            .frame(width: expanded ? 32 : 9, height: expanded ? 32 : 9)
            .opacity(expanded ? 0 : 0.8)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) { expanded = true }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#Preview("Researching") {
    WandrThinkingView(title: "Planning", stage: .researching)
}

#Preview("Curating") {
    WandrThinkingView(title: "Planning", stage: .curating)
}

#Preview("No stage to report") {
    WandrThinkingView(title: "Reading\nthat back", caption: "Pulling out the details you gave")
}
