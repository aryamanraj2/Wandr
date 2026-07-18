//
//  TimelineBlockView.swift
//  Wandr
//
//  A scheduled stop on the timeline.
//
//  A tap does nothing — this is content, not a control. Press and hold and the
//  block shrinks, takes the ink fill, and follows your finger; a dashed ghost
//  holds the slot it came from so the original time stays legible.
//
//  All transient state lives in `@GestureState`, which SwiftUI resets
//  automatically if the gesture is cancelled. That is what keeps a block from
//  being stranded in the lifted state when a touch is interrupted.
//

import SwiftUI

struct TimelineBlockView: View {
    @Binding var block: ScheduleBlock

    /// Which block in the timeline is currently lifted. Exactly one at a time.
    @Binding var liftedID: ScheduleBlock.ID?

    /// Minute bounds of the visible day, for clamping.
    let dayRange: ClosedRange<Int>

    /// Rescheduling is only possible in edit mode. Outside it the block is
    /// pure content and swallows nothing.
    let isEditing: Bool

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

    /// Pulsed after a release, purely to fire the landing haptic.
    @State private var isSettling = false

    private var height: CGFloat {
        CGFloat(block.durationMinutes) * Metrics.pointsPerMinute
    }

    private var accent: Color { Wandr.accent(for: block.category) }

    private var isLifted: Bool { lift.isLifted }

    /// The pinch is deepest at the moment of grab and relaxes once the block is
    /// travelling, so the squeeze reads as a response to the finger closing.
    private var isPressing: Bool { lift == .pressing }

    private var isDragging: Bool {
        if case .dragging = lift { return true }
        return false
    }

    /// Non-uniform on purpose — squashing slightly more vertically than
    /// horizontally is what makes it feel gripped rather than zoomed out.
    private var squeeze: CGSize {
        if isPressing { return CGSize(width: 0.88, height: 0.84) }
        if isDragging { return CGSize(width: 0.90, height: 0.89) }
        return CGSize(width: 1, height: 1)
    }

    /// Another block owns the interaction — this one must not respond.
    private var isBlocked: Bool { liftedID != nil && liftedID != block.id }

    private var canLift: Bool { isEditing && !isBlocked }

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
        // Publishing the lift upward is what enforces one-at-a-time and lets the
        // timeline suspend scrolling. Driven by onChange so a cancelled gesture
        // clears it just as reliably as a completed one.
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

                Image(systemName: block.category.symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(isLifted ? Wandr.cream.opacity(0.75) : accent)
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
        // Shrinking on lift is what makes the block read as detached from the
        // timeline rather than merely recolored.
        .scaleEffect(squeeze, anchor: .center)
        .shadow(color: Wandr.ink.opacity(isLifted ? 0.34 : 0.06),
                radius: isLifted ? 26 : 4,
                x: 0, y: isLifted ? 16 : 2)
        .offset(y: dragOffset)
        .zIndex(isLifted ? 10 : 0)
        // The grab springs, the release settles — two different feelings. Keyed
        // on the phase rather than a bool so press → drag also animates.
        .animation(isLifted ? .wandrLift : .wandrSettle, value: squeeze)
        .contentShape(RoundedRectangle(cornerRadius: Metrics.blockCorner))
        .gesture(liftAndDrag, isEnabled: canLift)
        // Three distinct taps, quietest to loudest in the order you feel them:
        // the grab, each slot you cross, and the landing.
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
        .accessibilityHint(isEditing ? "Adjust to reschedule" : "")
        // Press-and-hold is not reachable for every input method, so the same
        // capability is exposed through the adjustable trait.
        .accessibilityAdjustableAction { direction in
            guard isEditing else { return }
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

    /// Long press to lift, then drag to reschedule. Sequencing them means a
    /// scroll never accidentally moves a block, and a tap does nothing at all.
    private var liftAndDrag: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .updating($lift) { value, state, transaction in
                switch value {
                case .first(true):
                    state = .pressing
                    transaction.animation = .wandrSettle

                case .second(true, let drag):
                    // No animation while tracking — the block must sit under the
                    // finger, not chase it.
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
                // Project the release forward so a flick lands where it was
                // headed, rather than where the finger happened to stop.
                settle(to: minute(forOffset: translation + velocity * 0.25))
            }
    }

    private func settle(to target: Int) {
        // `lift` resets itself the instant the gesture ends, so the block
        // animates from wherever it was released into the committed slot.
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
        // Keep a fraction of the overflow so the finger stays attached, but make
        // the boundary unmistakable.
        return raw - overshootPoints + overshootPoints * 0.28
    }
}
