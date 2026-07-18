//
//  DeckView.swift
//  Wandr
//
//  A stack of candidates for one slot.
//
//  Swipe right to add to the squad's slate, left to pass. Both directions
//  advance — nothing is decided here, the host is only narrowing the field.
//
//  Motion follows the card-swipe idiom people already know: the card tracks the
//  finger in both axes with no damping, tilts proportionally to horizontal
//  travel around a low anchor, and the card beneath grows in as the top one
//  leaves. Commit is decided by distance OR velocity, so a flick works.
//

import SwiftUI

struct DeckView: View {
    @Binding var deck: Deck

    /// Live drag translation of the top card. Plain `@State` rather than
    /// `@GestureState` because the fly-off animates this same value after the
    /// gesture has already ended.
    @State private var drag: CGSize = .zero
    /// True while the exit animation runs, so a second swipe can't race it.
    @State private var isFlying = false
    /// Decided once per drag from the first meaningful movement. A drag that
    /// starts vertical belongs to the scroll view and the card ignores it for
    /// the rest of the gesture — otherwise every scroll attempt nudges a card.
    @State private var isHorizontalDrag: Bool?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Tuned against the standard card-swipe feel.
    private static let commitDistance: CGFloat = 100
    private static let commitVelocity: CGFloat = 300
    private static let maxTilt: Double = 15
    private static let flightDistance: CGFloat = 700

    /// -1 … 1 — horizontal travel as a fraction of the commit threshold.
    private var progress: CGFloat {
        max(-1, min(1, drag.width / Self.commitDistance))
    }

    /// Proportional tilt, capped. Rotating around a low anchor is what makes
    /// the card read as a held object pivoting rather than a sprite spinning.
    private var tilt: Angle {
        .degrees(min(Self.maxTilt, max(-Self.maxTilt, Double(drag.width) / 12)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            ZStack {
                if deck.isExhausted {
                    exhaustedState
                } else if deck.isReviewed {
                    reviewedState
                } else {
                    cardStack
                }
            }
            .frame(height: 400)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Label(deck.category.title, systemImage: deck.category.symbol)
                    .wandrLabelStyle(Wandr.accent(for: deck.category))

                Text(deck.slotName)
                    .font(.wandrTitle(22))
                    .foregroundStyle(Wandr.primaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(deck.window)
                    .font(.footnote)
                    .foregroundStyle(Wandr.secondaryText)

                Text(shortlistSummary)
                    .font(.caption2.monospacedDigit())
                    .contentTransition(.numericText())
                    .foregroundStyle(deck.shortlist.isEmpty
                                     ? Wandr.secondaryText.opacity(0.8)
                                     : Wandr.accent(for: deck.category))
            }
        }
        .padding(.horizontal, 4)
    }

    private var shortlistSummary: String {
        let kept = deck.shortlist.count
        if deck.isReviewed { return "\(kept) on the slate" }
        return kept == 0 ? "\(deck.remaining) to review" : "\(kept) kept · \(deck.remaining) left"
    }

    // MARK: Card stack

    private var cardStack: some View {
        ZStack {
            ForEach(Array(deck.backdrop.enumerated().reversed()), id: \.element.id) { index, candidate in
                backdropCard(candidate, depth: CGFloat(index + 1))
            }

            if let top = deck.topCandidate {
                CandidateCardView(candidate: top, dragProgress: progress)
                    .offset(drag)
                    .rotationEffect(tilt, anchor: .bottom)
                    .gesture(swipeGesture)
                    .allowsHitTesting(!isFlying)
                    // The swipe is the only visible affordance, so it must also
                    // exist as a named action for VoiceOver, Voice Control, and
                    // Switch Control users who cannot perform it.
                    .accessibilityAction(named: "Add to slate") { commit(keep: true) }
                    .accessibilityAction(named: "Pass") { commit(keep: false) }
            }
        }
        .animation(.wandrTransition, value: deck.cursor)
    }

    /// The card behind eases up to full size as the top card clears — the stack
    /// should look like it is resolving, not like a card vanished off one.
    private func backdropCard(_ candidate: Candidate, depth: CGFloat) -> some View {
        let advance = min(abs(progress), 1)
        let lift = depth == 1 ? advance : 0

        return CandidateCardView(candidate: candidate)
            .scaleEffect(1 - depth * 0.05 + lift * 0.05, anchor: .top)
            .offset(y: depth * 26 - lift * 26)
            .rotationEffect(.degrees(depth == 1 ? 1.2 * (1 - lift) : -0.9), anchor: .top)
            .opacity(1 - Double(depth - 1) * 0.3)
            .allowsHitTesting(false)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !isFlying else { return }

                if isHorizontalDrag == nil {
                    // Wait for enough travel to actually have a direction, then
                    // require a clear horizontal bias. A 2:1 cone leaves the
                    // diagonal to the scroll view, where a scrolling finger lives.
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    guard max(dx, dy) > 10 else { return }
                    isHorizontalDrag = dx > dy * 2
                }
                guard isHorizontalDrag == true else { return }

                // Follow the finger exactly across, and mostly down — full
                // vertical tracking on a card inside a scroll view reads as the
                // page failing to scroll.
                drag = CGSize(width: value.translation.width,
                              height: value.translation.height * 0.4)
            }
            .onEnded { value in
                guard !isFlying else { return }
                let wasHorizontal = isHorizontalDrag == true
                isHorizontalDrag = nil
                guard wasHorizontal else { return }

                let travel = value.translation.width
                let velocity = value.predictedEndTranslation.width - travel

                if abs(travel) > Self.commitDistance || abs(velocity) > Self.commitVelocity {
                    commit(keep: travel > 0)
                } else {
                    // Snap back with a touch of overshoot — the card was thrown
                    // and did not make it, and that should be felt.
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.68)) {
                        drag = .zero
                    }
                }
            }
    }

    private func commit(keep: Bool) {
        guard !isFlying else { return }
        isFlying = true

        let direction: CGFloat = keep ? 1 : -1
        let flight: Duration = .milliseconds(reduceMotion ? 90 : 260)

        // Continue the throw rather than starting a new motion from rest.
        withAnimation(reduceMotion ? .wandrResponse : .easeOut(duration: 0.28)) {
            drag = CGSize(width: direction * Self.flightDistance,
                          height: drag.height + 60)
        }

        Task { @MainActor in
            try? await Task.sleep(for: flight)
            drag = .zero
            isFlying = false
            withAnimation(.wandrTransition) {
                if keep { deck.shortlistTop() } else { deck.passTop() }
            }
        }
    }

    // MARK: Resolved states

    private var reviewedState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(deck.shortlist.count) options for the squad")
                .font(.wandrTitle(20))
                .foregroundStyle(Wandr.primaryText)

            Text("Everyone votes on these in the thread. Whichever wins takes the \(deck.slotName.lowercased()) slot.")
                .font(.footnote)
                .foregroundStyle(Wandr.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(deck.shortlisted) { candidate in
                    shortlistRow(candidate)
                }
            }

            Spacer(minLength: 0)

            Button("Review this slot again") {
                withAnimation(.wandrTransition) { deck.restart() }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Wandr.secondaryText)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(WandrCardBackground(fill: Wandr.cardSurface))
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private func shortlistRow(_ candidate: Candidate) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9)
                .fill(Wandr.accent(for: candidate.category))
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: candidate.category.symbol)
                        .font(.system(size: 15))
                        .foregroundStyle(Wandr.cream)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Wandr.primaryText)
                Text(candidate.area)
                    .font(.caption)
                    .foregroundStyle(Wandr.secondaryText)
            }

            Spacer()

            Text(candidate.perHead == 0 ? "Free" : "₹\(candidate.perHead)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Wandr.secondaryText)

            Button {
                withAnimation(.wandrTransition) {
                    deck.shortlist.removeAll { $0 == candidate.id }
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Wandr.secondaryText)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Wandr.sand.opacity(0.4)))
            }
            .accessibilityLabel("Remove \(candidate.name) from the slate")
        }
        .padding(.vertical, 4)
    }

    private var exhaustedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 30))
                .foregroundStyle(Wandr.secondaryText)

            Text("You passed on all \(deck.candidates.count)")
                .font(.wandrTitle(19))
                .foregroundStyle(Wandr.primaryText)

            Text("Loosen the budget or the area and Wandr will research this slot again.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Wandr.secondaryText)
                .padding(.horizontal, 40)

            Button("Start over") {
                withAnimation(.wandrTransition) { deck.restart() }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Wandr.primaryText)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WandrCardBackground(fill: Wandr.sand.opacity(0.22)))
        .transition(.opacity)
    }
}

#Preview("Deck") {
    @Previewable @State var deck = DemoPlan.decks[0]

    ZStack {
        Wandr.pageBackground.ignoresSafeArea()
        DeckView(deck: $deck)
            .padding(Metrics.gutter)
    }
}
