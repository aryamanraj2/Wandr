// TimelineBlockView.swift Wandr A scheduled stop on the timeline. A tap does nothing — this is content, not a control. Rescheduling is not a mode you enter, it is a commitment you make with one finger: hold the block and an accent ring draws itself around the edge while the card tightens in your grip; hold it all the way and the block snaps free, takes the ink fill, and follows your finger, with a dashed ghost keeping the slot it came from so the original time stays legible. Letting go early costs nothing and the ring unwinds. The hold is deliberately long — a stop moving is a real edit to the night, and it should take a moment of intent rather than a brush of a thumb. All transient state lives in `@GestureState`, which SwiftUI resets automatically if the gesture is cancelled. That is what keeps a block from being stranded in the lifted state when a touch is interrupted.

import SwiftUI

struct TimelineBlockView: View {
    @Binding var block: ScheduleBlock

    /// Which block in the timeline is currently lifted. Exactly one at a time.
    @Binding var liftedID: ScheduleBlock.ID?

    /// Minute bounds of the visible day, for clamping.
    let dayRange: ClosedRange<Int>

    /// How long the finger has to stay down before the block comes free. Long enough that a scroll or a brushed thumb never moves a stop, short enough that a deliberate hold does not feel stuck — and the charge ring makes the wait legible rather than dead.
    private static let holdDuration: Double = 0.45

    /// Canonical long-press-then-drag state. Auto-resets on cancellation.
    private enum LiftState: Equatable {
        case inactive
        case pressing
        case dragging(translation: CGSize)

        var isLifted: Bool { self != .inactive }

        var verticalTranslation: CGFloat {
            if case .dragging(let translation) = self { return translation.height }
            return 0
        }
    }

    @GestureState private var lift: LiftState = .inactive

    /// True from touch-down until the finger leaves or travels far enough to be a scroll. This only reports the press — it never succeeds on its own, so it cannot claim the touch away from the gesture that actually does the work.
    @GestureState private var isCharging = false

    /// 0 → 1 over the hold, driving the ring that draws around the block. Plain `@State` because it has to animate over real time rather than track a value the finger is producing.
    @State private var charge: CGFloat = 0

    /// Pulsed after a release, purely to fire the landing haptic.
    @State private var isSettling = false

    private var height: CGFloat {
        CGFloat(block.durationMinutes) * Metrics.pointsPerMinute
    }

    private var accent: Color { Wandr.accent(for: block.category) }

    private var isLifted: Bool { lift.isLifted }

    /// The pinch is deepest at the moment of grab and relaxes once the block is travelling, so the squeeze reads as a response to the finger closing.
    private var isPressing: Bool { lift == .pressing }

    private var isDragging: Bool {
        if case .dragging = lift { return true }
        return false
    }

    /// Non-uniform on purpose — squashing slightly more vertically than horizontally is what makes it feel gripped rather than zoomed out. The charging stage is uniform and shallow by contrast: nothing has been decided yet, so the block is only tensing, not gripped.
    private var squeeze: CGSize {
        if isPressing { return CGSize(width: 0.88, height: 0.84) }
        if isDragging { return CGSize(width: 0.90, height: 0.89) }
        if isCharging { return CGSize(width: 0.965, height: 0.965) }
        return CGSize(width: 1, height: 1)
    }

    /// The squeeze is one motion with three tempos, and keying them apart is what makes the threshold land as a snap. Charging eases *in* so the tension builds and the release out of it reads as a break; the grab springs loose; the settle damps.
    private var squeezeAnimation: Animation {
        if isLifted { return .wandrLift }
        if isCharging { return .easeIn(duration: Self.holdDuration) }
        return .wandrSettle
    }

    /// Another block owns the interaction — this one must not respond.
    private var isBlocked: Bool { liftedID != nil && liftedID != block.id }

    private var canLift: Bool { !isBlocked }

    private var dragOffset: CGFloat {
        isLifted ? resisted(lift.verticalTranslation) : 0
    }

    /// The snapped minute this block would land on if released now.
    private var proposedMinute: Int? {
        guard case .dragging(let translation) = lift else { return nil }
        return minute(forOffset: translation.height)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isLifted { ghost }
            card
        }
        .frame(height: height, alignment: .top)
        // Publishing the lift upward is what enforces one-at-a-time and lets the timeline suspend scrolling. Driven by onChange so a cancelled gesture clears it just as reliably as a completed one.
        .onChange(of: isLifted) { _, lifted in
            liftedID = lifted ? block.id : nil
        }
    }

    // MARK: Ghost

    /// Dashed outline of the slot the block was picked up from.
    private var ghost: some View {
        RoundedRectangle(cornerRadius: Metrics.blockCorner)
            .strokeBorder(
                Wandr.slate.opacity(0.7),
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
            )
            .frame(height: height)
            .transition(.opacity)
    }

    // MARK: Charge ring

    /// The commitment, drawn. A hold with no feedback is indistinguishable from a screen that has stopped responding — this is what turns the wait into a visible countdown, and what makes letting go early an obvious, costless choice.
    private var chargeRing: some View {
        RoundedRectangle(cornerRadius: Metrics.blockCorner)
            .trim(from: 0, to: charge)
            .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .opacity(isLifted ? 0 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(block.title)
                        .font(.wandrTitle(20))
                        .foregroundStyle(isLifted ? Wandr.cream : Wandr.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(block.category.title)
                        .wandrLabelStyle(isLifted ? Wandr.cream.opacity(0.6) : Wandr.secondaryText)
                }

                Spacer(minLength: 8)

                // A short block has no room for a picture — below roughly an hour the
                // thumbnail would crowd the title it is meant to accompany, so the glyph
                // that was always here stays.
                if height >= 76 {
                    VenueThumbnail(
                        seed: block.imageSeed,
                        accent: accent,
                        symbol: block.category.symbol,
                        size: 38,
                        corner: 10
                    )
                    .opacity(isLifted ? 0.85 : 1)
                } else {
                    Image(systemName: block.category.symbol)
                        .font(.system(size: 15))
                        .foregroundStyle(isLifted ? Wandr.cream.opacity(0.75) : accent)
                }
            }

            Spacer(minLength: 0)

            Text(displayedStartLabel)
                .font(.wandrClock(19))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(isLifted ? Wandr.cream : Wandr.secondaryText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .background {
            RoundedRectangle(cornerRadius: Metrics.blockCorner)
                .fill(isLifted ? Wandr.liftedSurface : Wandr.cardSurface)
        }
        .overlay { chargeRing }
        // Shrinking on lift is what makes the block read as detached from the timeline rather than merely recolored.
        .scaleEffect(squeeze, anchor: .center)
        .shadow(color: Wandr.charcoal.opacity(isLifted ? 0.34 : 0.06),
                radius: isLifted ? 26 : 4,
                x: 0, y: isLifted ? 16 : 2)
        .offset(y: dragOffset)
        .zIndex(isLifted ? 10 : 0)
        // Three tempos, one motion: tension, grab, settle.
        .animation(squeezeAnimation, value: squeeze)
        // While one block is in the air the rest of the night steps back, so there is never a question about which stop the finger owns.
        .opacity(isBlocked ? 0.45 : 1)
        .animation(.wandrResponse, value: isBlocked)
        .contentShape(RoundedRectangle(cornerRadius: Metrics.blockCorner))
        .gesture(liftAndDrag, isEnabled: canLift)
        // Simultaneous, and deliberately never satisfiable: this exists only to know a finger is down. A `.gesture` here would claim the touch and starve both the real lift and the scroll view.
        .simultaneousGesture(pressTracker, isEnabled: canLift)
        // The ring is time-based, not finger-based, so it is driven from the press rather than tracked. Winding down faster than it wound up makes an abandoned hold feel released rather than undone.
        .onChange(of: isCharging) { _, charging in
            guard !isLifted else { return }
            withAnimation(charging ? .linear(duration: Self.holdDuration)
                                   : .easeOut(duration: 0.16)) {
                charge = charging ? 1 : 0
            }
        }
        // The ring has done its job the instant the block comes free — it must not survive into the drag as a stray outline.
        .onChange(of: isLifted) { _, lifted in
            guard lifted else { return }
            withAnimation(.wandrResponse) { charge = 0 }
        }
        // Three distinct taps, quietest to loudest in the order you feel them: the grab, each slot you cross, and the landing.
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.75),
                         trigger: isPressing) { _, pressing in pressing }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.4),
                         trigger: isDragging) { _, dragging in dragging }
        .sensoryFeedback(.selection, trigger: proposedMinute)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.9),
                         trigger: isSettling) { _, settling in settling }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(block.title), \(block.category.title)")
        .accessibilityValue("\(block.startLabel) to \(block.endLabel)")
        .accessibilityHint("Adjust to reschedule")
        // Press-and-hold is now the only gesture that moves a stop, and it is not reachable for every input method — so the adjustable trait is not a convenience here, it is the whole capability.
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? Metrics.snapMinutes : -Metrics.snapMinutes
            withAnimation(.wandrSettle) {
                block.startMinute = clamped(block.startMinute + delta)
            }
        }
    }

    private var displayedStartLabel: String {
        ScheduleBlock.clock(proposedMinute ?? block.startMinute)
    }

    // MARK: Gesture

    /// Reports the press and nothing else. A long press publishes its state from the moment the finger lands rather than only on success, which is the whole trick: the duration is set past any real hold so the gesture never completes and never claims the touch, and `updating` still tells us a finger is down. `maximumDistance` is what keeps it honest — a finger that travels is scrolling, the press fails, and the ring unwinds on its own.
    ///
    /// The duration is a large *finite* number on purpose. `.infinity` and `.greatestFiniteMagnitude` are the obvious way to say "never", and both hand an unrepresentable deadline to a gesture that schedules a real timer.
    private var pressTracker: some Gesture {
        LongPressGesture(minimumDuration: 60, maximumDistance: 24)
            .updating($isCharging) { pressing, state, _ in state = pressing }
    }

    /// Long press to lift, then drag to reschedule. Sequencing them means a scroll never accidentally moves a block, and a tap does nothing at all.
    private var liftAndDrag: some Gesture {
        LongPressGesture(minimumDuration: Self.holdDuration, maximumDistance: 24)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .updating($lift) { value, state, transaction in
                switch value {
                case .first(true):
                    // The threshold. Everything before this was tension; this is the break, so it springs rather than eases.
                    state = .pressing
                    transaction.animation = .wandrLift

                case .second(true, let drag):
                    // No animation while tracking — the block must sit under the finger, not chase it.
                    state = .dragging(translation: drag?.translation ?? .zero)
                    transaction.animation = nil

                default:
                    state = .inactive
                }
            }
            .onEnded { value in
                guard case .second(true, let drag) = value else { return }
                let translation = drag?.translation.height ?? 0
                let velocity = (drag?.predictedEndTranslation.height ?? translation) - translation
                // Project the release forward so a flick lands where it was headed, rather than where the finger happened to stop.
                settle(to: minute(forOffset: translation + velocity * 0.25))
            }
    }

    private func settle(to target: Int) {
        // `lift` resets itself the instant the gesture ends, so the block animates from wherever it was released into the committed slot.
        withAnimation(.wandrSettle) {
            block.startMinute = clamped(target)
        }
        isSettling = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            isSettling = false
        }
    }

    // MARK: Time math

    /// Snapped minute for a given vertical translation.
    private func minute(forOffset offset: CGFloat) -> Int {
        let deltaMinutes = Int((offset / Metrics.pointsPerMinute).rounded())
        let raw = block.startMinute + deltaMinutes
        let snapped = Int((Double(raw) / Double(Metrics.snapMinutes)).rounded()) * Metrics.snapMinutes
        return clamped(snapped)
    }

    private func clamped(_ minute: Int) -> Int {
        min(max(minute, dayRange.lowerBound), dayRange.upperBound - block.durationMinutes)
    }

    /// Progressive resistance past the ends of the day instead of a hard stop.
    private func resisted(_ raw: CGFloat) -> CGFloat {
        let unclamped = block.startMinute + Int((raw / Metrics.pointsPerMinute).rounded())
        let allowed = clamped(unclamped)
        guard allowed != unclamped else { return raw }

        let overshootPoints = CGFloat(unclamped - allowed) * Metrics.pointsPerMinute
        // Keep a fraction of the overflow so the finger stays attached, but make the boundary unmistakable.
        return raw - overshootPoints + overshootPoints * 0.28
    }
}
