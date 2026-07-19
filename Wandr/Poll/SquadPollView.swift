//
//  SquadPollView.swift
//  Wandr
//
//  Send-to-Squad: the slate becomes one place-poll per slot, and each slot locks to
//  the place with the most votes — but only once everyone (the quorum N) has voted.
//
//  Phase 1 simulates the squad in-app: tapping an option casts a pseudonymous vote, so
//  the tally / quorum / winner / tie flow can be exercised on one device. Phase 2 swaps
//  that seam for real votes arriving on an `MSMessage` in the iMessage thread; the host
//  taps Send (Apple's rule) and the squad disposes.
//

import SwiftUI

struct SquadPollView: View {
    @State private var session: PollSession
    /// Winners handed back to curation to open the schedule.
    let onLockNight: ([(slotID: String, candidate: Candidate)]) -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        session: PollSession,
        onLockNight: @escaping ([(slotID: String, candidate: Candidate)]) -> Void
    ) {
        _session = State(initialValue: session)
        self.onLockNight = onLockNight
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 28) {
                    intro
                    quorumCard

                    ForEach(session.polls) { poll in
                        SlotPollCard(
                            poll: poll,
                            counts: session.counts(for: poll),
                            resolution: session.resolution(for: poll)
                        ) { option in
                            withAnimation(.wandrTransition) {
                                session.tap(option, inSlot: poll.slotID)
                            }
                        }
                    }

                    Color.clear.frame(height: 80)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 8)
            }
            .background(Wandr.pageBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Squad poll")
                        .font(.headline)
                        .foregroundStyle(Wandr.primaryText)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back") { dismiss() }
                }
            }
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .safeAreaBar(edge: .bottom) { lockBar }
        }
        .tint(Wandr.ink)
    }

    // MARK: Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Send it to the squad")
                .font(.wandrDisplay(34))
                .foregroundStyle(Wandr.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Each slot goes to a vote. A stop locks to the place with the most votes — once everyone’s in.")
                .font(.subheadline)
                .foregroundStyle(Wandr.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Quorum

    /// The host sets how many people are voting. Pre-filled from the brief's group size.
    private var quorumCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Everyone in the group")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Wandr.primaryText)
                Text("Winners reveal once all \(session.quorumSize) have voted")
                    .font(.caption)
                    .foregroundStyle(Wandr.secondaryText)
            }

            Spacer(minLength: 0)

            Stepper(
                value: Binding(
                    get: { session.quorumSize },
                    set: { session.setQuorum($0) }
                ),
                in: session.minQuorum...20
            ) {
                Text("\(session.quorumSize)")
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .foregroundStyle(Wandr.primaryText)
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(16)
        .background(WandrCardBackground())
    }

    // MARK: Lock bar

    private var lockBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.footnote.weight(.semibold))
                    .contentTransition(.numericText())
                Text(session.allDecided ? "Every slot has a winner" : "Tap options to gather votes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                onLockNight(session.winners())
            } label: {
                Label("Lock the night", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(Wandr.ink)
            .disabled(!session.allDecided)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 10)
        .animation(.wandrResponse, value: session.allDecided)
    }

    private var decidedCount: Int {
        session.polls.filter(\.isLocked).count
    }

    private var statusTitle: String {
        "\(decidedCount)/\(session.polls.count) slots locked"
    }
}

// MARK: - Slot card

private struct SlotPollCard: View {
    let poll: SquadSlotPoll
    let counts: [PollOptionID: Int]
    let resolution: PollResolution
    let onTap: (PollOptionID) -> Void

    private var category: StopCategory? { StopCategory(rawValue: poll.slotID) }
    private var accent: Color { category.map(Wandr.accent(for:)) ?? Wandr.ink }

    private var winnerID: PollOptionID? {
        if case .decided(let id) = resolution { return id }
        return nil
    }

    private var isTie: Bool {
        if case .tie = resolution { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            VStack(spacing: 10) {
                ForEach(poll.options) { option in
                    optionRow(option)
                }
            }
        }
        .padding(18)
        .background(WandrCardBackground())
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                if let category {
                    Text(category.title).wandrLabelStyle(accent)
                }
                Text(poll.slotName)
                    .font(.wandrTitle(20))
                    .foregroundStyle(Wandr.primaryText)
            }

            Spacer(minLength: 0)

            statusPill
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        switch resolution {
        case .pending(let received, let size):
            Label("\(received)/\(size) voted", systemImage: "person.2")
                .font(.caption.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
                .foregroundStyle(Wandr.secondaryText)
        case .tie:
            Label("Tie — you pick", systemImage: "arrow.triangle.branch")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
        case .decided:
            Label("Locked", systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
        }
    }

    private func optionRow(_ option: PollOption) -> some View {
        let votes = counts[option.id] ?? 0
        let isWinner = winnerID == option.id
        let locked = poll.isLocked
        // A tie invites the host to pick; before quorum, every row gathers votes.
        let interactive = !locked

        return Button {
            onTap(option.id)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.subheadline.weight(isWinner ? .bold : .semibold))
                        .foregroundStyle(isWinner ? accent : Wandr.primaryText)
                    Text(option.subtitle)
                        .font(.caption)
                        .foregroundStyle(Wandr.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text("\(votes)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .foregroundStyle(votes > 0 ? accent : Wandr.secondaryText)
                    .frame(minWidth: 18)

                Image(systemName: isWinner ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isWinner ? accent : Wandr.hairline)
                    .opacity(locked && !isWinner ? 0.4 : 1)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background {
                ConcentricRectangle(corners: .concentric(minimum: .fixed(Metrics.blockCorner)))
                    .fill(isWinner ? accent.opacity(0.12) : Wandr.pageBackground.opacity(0.5))
            }
        }
        .buttonStyle(WandrPressStyle())
        .disabled(!interactive)
        .opacity(locked && !isWinner ? 0.55 : 1)
        .accessibilityLabel("\(option.label), \(votes) votes\(isWinner ? ", winner" : "")")
    }
}

#Preview {
    let decks = Array(DemoPlan.decks.prefix(2)).map { deck -> Deck in
        var d = deck
        d.shortlist = Array(d.candidates.prefix(3)).map(\.id)
        return d
    }
    return SquadPollView(session: PollSession(decks: decks, groupSize: 4)) { _ in }
}
