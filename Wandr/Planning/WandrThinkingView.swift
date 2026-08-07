// WandrThinkingView.swift Wandr The screen you wait on. Both waits in the app — the on-device extraction and the grounded planning run — render this, so the two look like one app doing two things rather than two spinners someone wrote on different days.

import SwiftUI

/// A wait that says what it is doing, in as few moving parts as that takes.
///
/// The screen states two things and keeps them strictly apart:
///
/// - **the checklist and the bar are real.** They move when `PlanningState` moves and at no other
///   time. Where there is genuinely nothing to report, the caller passes no stage, the bar stays
///   empty, and the readout says `WORKING` rather than inventing a percentage.
/// - **the caret is activity, not progress.** It says the app is still running. It never implies a
///   position, which is why it is a blink in place rather than anything that travels.
///
/// Conflating those is how loading screens end up lying — a bar that eases to 90% on a timer and
/// then sits there.
///
/// The look is deliberately hard: flat fills, square corners, 2pt rules, monospaced state, and no
/// blur, gradient, glow, or ambient motion anywhere on the page. This is the one surface in the app
/// built that way, and it is built that way because it is the one surface with nothing to touch —
/// a wait has no controls to make inviting, so softness here is decoration on a screen whose entire
/// job is to be legible at a glance. What replaced the previous version was five simultaneous
/// decorative systems (a comet band, type shimmer, drifting blooms, a rotating border glow, pulsing
/// dots with arrival ripples), all of which moved constantly and none of which meant anything.
///
/// The whole pipeline is on screen at once now rather than one line at a time. Four rows is small
/// enough to read in a glance, and seeing the two steps still to come is what makes a twenty-second
/// pause on the research leg read as a long step rather than as a stall.
struct WandrThinkingView: View {

    /// The masthead. One or two words — this is the largest type in the app and a sentence at this
    /// size stops being a statement.
    let title: String

    /// The live pipeline phase, when the caller has one.
    var stage: PlanningState?

    /// What to say when there is no stage stream to read. The on-device extraction is a single
    /// model call with no interior, so it gets a fixed line and an empty bar instead of invented
    /// milestones.
    var caption: String?

    /// The four phases a host actually waits through. `needsDetails`, `ready`, `failed` and
    /// `cancelled` are outcomes rather than legs, and `idle` is the moment before the first one.
    private static let legs: [PlanningState] = [.extracting, .researching, .validating, .curating]

    private static let barHeight: CGFloat = 14

    private var line: String? {
        stage?.hostDescription ?? caption
    }

    /// How far the leg list has been walked. `nil` before the first phase lands, and for any state
    /// that is an outcome rather than a leg.
    private var legIndex: Int? {
        guard let stage else { return nil }
        return Self.legs.firstIndex(of: stage)
    }

    private var progress: Double? { stage?.hostProgress }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    @ScaledMetric(relativeTo: .footnote) private var markerSize: CGFloat = 10

    var body: some View {
        // A wait screen that scrolls sounds wrong, and at every ordinary text size this one does
        // not: the spacers below hold the block a third of the way down a page that fits. But four
        // rows of the pipeline at an accessibility size are four rows of *three lines each*, and
        // laid out rigidly that ran the readout up under the status bar and pushed the bar off the
        // bottom of the screen entirely. `minHeight` on the content is what keeps both behaviours in
        // one layout — the spacers get slack to distribute when there is any, and none when there is
        // not, at which point this becomes an ordinary scrolling page.
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)

                    readout
                        .padding(.bottom, 10)

                    Rectangle()
                        .fill(Wandr.primaryText)
                        .frame(height: Metrics.rule)
                        .padding(.bottom, 30)

                    WandrMasthead(title: title, size: 52)
                        .padding(.bottom, 30)

                    checklist

                    bar
                        .padding(.top, 30)

                    // Two below to one above: the block settles a third of the way down rather than
                    // dead centre. Centred, a short block on a tall empty page reads as content that
                    // failed to load; held high, the emptiness under it reads as space that was left
                    // on purpose.
                    Spacer(minLength: 0)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metrics.gutter)
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Wandr.pageBackground)
        // One element, one announcement. Read as six (title, four rows, a readout) VoiceOver would
        // have to be swiped through to learn the app is merely busy.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: Readout

    /// Where the run is, in the two facts that fit on one line. Monospaced and digit-locked because
    /// both halves change while you are looking at them, and a percentage that reflows as it counts
    /// draws the eye to the wrong thing.
    private var readout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(phaseCounter)

            Spacer(minLength: 12)

            if let percent {
                Text(percent)
            }
        }
        .font(.wandrMono(11, weight: .semibold))
        .tracking(1.2)
        .textCase(.uppercase)
        .monospacedDigit()
        .foregroundStyle(Wandr.primaryText)
    }

    private var phaseCounter: String {
        guard let legIndex else { return "Working" }
        return "Phase \(legIndex + 1) / \(Self.legs.count)"
    }

    /// Only ever the pipeline's own number. There is no fallback here on purpose — a wait with no
    /// position to report shows no position.
    private var percent: String? {
        progress.map { "\(Int(($0 * 100).rounded()))%" }
    }

    // MARK: Checklist

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                self.row(row)
            }
        }
        // A near-cut rather than a spring. A phase landing is a switch flipping, and easing it makes
        // the change look like something the screen decided rather than something that happened.
        .animation(.linear(duration: 0.1), value: legIndex)
        .accessibilityHidden(true)
    }

    private func row(_ row: Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            marker(row.state)

            // All-caps and tracked at ordinary sizes, and neither at accessibility ones. Both are
            // width taxes on a line that already wraps three ways at AX5, and all-caps is the harder
            // of the two to read for exactly the person who asked for larger text.
            Text(typeSize.isAccessibilitySize ? row.text : row.text.uppercased())
                // Dynamic-Type-relative, unlike the fixed-size metadata labels elsewhere in the app:
                // this is the screen's primary content now, not a caption on something else.
                .font(.system(.footnote, design: .monospaced)
                    .weight(row.state == .current ? .bold : .medium))
                .tracking(typeSize.isAccessibilitySize ? 0 : 0.6)
                .foregroundStyle(textColor(row.state))
                .fixedSize(horizontal: false, vertical: true)

            if row.state == .current {
                BlinkingCaret(steady: reduceMotion)
            }
        }
    }

    /// Square, flat, and either filled or not. The done/doing distinction is carried by the caret and
    /// the type weight rather than by a third marker state — three shapes to decode is one more than
    /// a status list is worth.
    private func marker(_ state: RowState) -> some View {
        Group {
            if state == .pending {
                Rectangle()
                    .strokeBorder(Wandr.primaryText.opacity(0.28), lineWidth: 1.5)
            } else {
                Rectangle()
                    .fill(Wandr.primaryText)
            }
        }
        .frame(width: markerSize, height: markerSize)
        // Sit on the baseline of the line beside it, not the top of the row — at large text sizes a
        // wrapping row would otherwise leave the square floating beside nothing.
        .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
    }

    private func textColor(_ state: RowState) -> Color {
        switch state {
        case .current: return Wandr.primaryText
        case .done:    return Wandr.secondaryText
        case .pending: return Wandr.primaryText.opacity(0.28)
        }
    }

    private enum RowState { case done, current, pending }

    private struct Row {
        let text: String
        let state: RowState
    }

    /// The four legs when there are legs to show, and a single line when there are not — so the
    /// extraction wait is the same screen with a shorter list rather than a different screen.
    private var rows: [Row] {
        guard let legIndex else {
            return line.map { [Row(text: $0, state: .current)] } ?? []
        }

        return Self.legs.enumerated().compactMap { index, leg in
            guard let text = leg.hostDescription else { return nil }
            if index < legIndex  { return Row(text: text, state: .done) }
            if index == legIndex { return Row(text: text, state: .current) }
            return Row(text: text, state: .pending)
        }
    }

    // MARK: Bar

    /// The one thing on the page that claims a position, and it only ever claims the pipeline's own.
    /// A hard outline with a hard fill: no radius, no gradient, no travelling head. With no progress
    /// to report the rail stays empty rather than filling on a clock.
    private var bar: some View {
        GeometryReader { proxy in
            let inner = max(0, proxy.size.width - Metrics.rule * 2)

            ZStack(alignment: .leading) {
                Rectangle()
                    .strokeBorder(Wandr.primaryText, lineWidth: Metrics.rule)

                Rectangle()
                    .fill(Wandr.primaryText)
                    .frame(width: inner * (progress ?? 0),
                           height: Self.barHeight - Metrics.rule * 2)
                    .offset(x: Metrics.rule)
            }
        }
        .frame(height: Self.barHeight)
        .animation(.easeOut(duration: 0.28), value: progress)
        .accessibilityHidden(true)
    }

    // MARK: Accessibility

    /// Title, position, and phase in one sentence, in the order they are read on screen.
    private var accessibilityLine: String {
        [title, legIndex.map { "Phase \($0 + 1) of \(Self.legs.count)" }, line]
            .compactMap { $0 }
            .joined(separator: ". ")
    }
}

/// The only thing on this screen that moves on a clock.
///
/// A terminal caret, and borrowed for the reason terminals use one: it is the smallest mark that
/// says a process is alive without saying anything about how far along it is. Everything else here
/// is pinned to `PlanningState`, so this is the whole activity budget for the page.
///
/// Hard on and hard off. A fade would put it back in the family of soft, continuous motion the rest
/// of this screen exists to get away from, and at this size a crossfade reads as a flicker anyway.
private struct BlinkingCaret: View {

    /// Reduce Motion gets the caret solid. It still marks which row is running — it just stops being
    /// the thing that draws the eye there.
    var steady: Bool = false

    private static let period: TimeInterval = 0.55

    /// Roughly the cap height of the row it sits beside. Measured taller first, which put a block
    /// standing a third of its own height above the letters — a marker floating over the line rather
    /// than a caret sitting on it.
    @ScaledMetric(relativeTo: .footnote) private var height: CGFloat = 12

    var body: some View {
        Group {
            if steady {
                block
            } else {
                // `.periodic`, not `.animation`. This changes twice a second, and an animation
                // schedule would wake the view every display frame to redraw a rectangle that is
                // identical 119 times out of 120. It also gives the hard cut for free.
                TimelineView(.periodic(from: .now, by: Self.period)) { timeline in
                    let tick = timeline.date.timeIntervalSinceReferenceDate / Self.period
                    block.opacity(Int(tick).isMultiple(of: 2) ? 1 : 0)
                }
            }
        }
        .frame(width: height * 0.6, height: height)
        .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var block: some View {
        Rectangle().fill(Wandr.primaryText)
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
