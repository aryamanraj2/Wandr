// SquadPollView.swift Wandr Send-to-Squad: the slate becomes one place-poll per slot, and each slot locks to the place with the most votes — but only once everyone has voted. Everyone in the room is on this screen at the same time, voting on their own phone, watching the same bars move.
//
// Nothing here decides anything. Counts and resolutions come from `PollTally` via the session, and a tap only ever asks the relay; the snapshot that comes back is the truth. That is also why the motion is driven from `session.version` rather than wrapped around the tap — a snapshot arrives inside an async continuation, where `withAnimation` is unreliable, so the value animates instead. The same pattern as `.animation(.wandrResponse, value: headerCollapsed)` in `CurationView`.

import SwiftUI

struct SquadPollView: View {
    /// Owned by the presenter, not by this view. A poll survives the view being rebuilt, and in live mode it is a window onto `SquadRoom` — building one in `init` would be rebuilding it on every render.
    let session: PollSession

    /// Offline only: the winners handed back to curation to open the schedule. Live, the room advances by itself the moment the last slot decides.
    var onLockNight: (([(slotID: String, candidate: Candidate)]) -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 28) {
                    intro

                    ForEach(session.polls) { poll in
                        SlotPollCard(
                            poll: poll,
                            counts: session.counts(for: poll),
                            resolution: session.resolution(for: poll),
                            quorum: session.quorumSize,
                            voted: session.voted(in: poll.slotID),
                            myVote: session.myVote(in: poll.slotID),
                            isLeader: session.isLeader,
                            leaderName: session.leaderName,
                            interactive: session.canTap(poll)
                        ) { option in
                            session.tap(option, inSlot: poll.slotID)
                        }
                    }

                    Color.clear.frame(height: 80)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 8)
                // The one animation that matters: every tally, pill and bar on screen moves together when a new snapshot lands, and never on anything else.
                .animation(.wandrTransition, value: session.version)
                .animation(.wandrTransition, value: session.quorumSize)
            }
            .background(Wandr.pageBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Squad poll")
                        .font(.headline)
                        .foregroundStyle(Wandr.primaryText)
                }
                if !session.isLive {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") { dismiss() }
                    }
                }
            }
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .safeAreaBar(edge: .bottom) { statusBar }
        }
        .tint(Wandr.brand)
    }

    // MARK: Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.isLive ? "Everyone votes" : "Send it to the squad")
                .font(.wandrDisplay(34))
                .foregroundStyle(Wandr.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(session.isLive
                 ? "A stop locks to the place with the most votes — once all \(session.quorumSize) of you are in."
                 : "Each slot goes to a vote. A stop locks to the place with the most votes — once everyone’s in.")
                .font(.subheadline)
                .foregroundStyle(Wandr.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            // Live, there is no button: the room moves on by itself the moment the last slot decides, and a "lock" tap would be a second, redundant decision.
            if !session.isLive {
                Button {
                    onLockNight?(session.winners())
                } label: {
                    Label("Lock the night", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.glassProminent)
                .tint(Wandr.brand)
                .disabled(!session.allDecided)
            } else if session.allDecided {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 10)
        .animation(.wandrResponse, value: session.allDecided)
        .animation(.wandrResponse, value: session.version)
    }

    private var decidedCount: Int {
        session.polls.filter {
            if case .decided = session.resolution(for: $0) { return true }
            return false
        }.count
    }

    private var statusTitle: String {
        "\(decidedCount)/\(session.polls.count) slots locked"
    }

    private var subtitle: String {
        if session.allDecided {
            return session.isLive
                ? (session.isLeader ? "Opening the timeline…" : "\(session.leaderName) is finalising it")
                : "Every slot has a winner"
        }
        return session.isLive ? "Tap a place to cast your vote" : "Tap options to gather votes"
    }
}

// MARK: - Slot card

private struct SlotPollCard: View {
    let poll: SquadSlotPoll
    let counts: [PollOptionID: Int]
    let resolution: PollResolution
    let quorum: Int
    let voted: Int
    let myVote: PollOptionID?
    let isLeader: Bool
    let leaderName: String
    let interactive: Bool
    let onTap: (PollOptionID) -> Void

    private var category: StopCategory? { StopCategory(rawValue: poll.slotID) }
    private var accent: Color { category.map(Wandr.accent(for:)) ?? Wandr.brand }

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
            voterStrip

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
        case .pending:
            Label("\(voted)/\(quorum) in", systemImage: "person.2")
                .font(.caption.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
                .foregroundStyle(Wandr.secondaryText)
        case .tie:
            // A joiner watching a tie is not stuck — they are waiting on a named person, and saying whose call it is turns a dead screen into a beat.
            Label(isLeader ? "Tie — your call" : "\(leaderName)’s call",
                  systemImage: "arrow.triangle.branch")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
        case .decided:
            Label("Locked", systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
        }
    }

    /// One pip per person, filled as their vote lands. The count is in the pill; this is the thing you can read without reading.
    private var voterStrip: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(quorum, voted), id: \.self) { index in
                Capsule()
                    .fill(index < voted ? accent : Wandr.mist.opacity(0.45))
                    .frame(height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(voted) of \(quorum) voted")
    }

    private func optionRow(_ option: PollOption) -> some View {
        let votes = counts[option.id] ?? 0
        let isWinner = winnerID == option.id
        let isMine = myVote == option.id
        let locked = winnerID != nil
        // Votes stay hidden until quorum in the tally's own reading, but the *bar* is the honest live signal — it is what makes three people on three phones feel like one room.
        let fraction = quorum > 0 ? min(1, Double(votes) / Double(quorum)) : 0

        return Button {
            onTap(option.id)
        } label: {
            HStack(spacing: 12) {
                VenueThumbnail(
                    seed: option.imageSeed,
                    accent: accent,
                    symbol: category?.symbol ?? "mappin",
                    size: 34,
                    corner: 8
                )

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

                if isMine {
                    Text("your pick")
                        .wandrLabelStyle(accent)
                        .transition(.opacity)
                }

                Text("\(votes)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .foregroundStyle(votes > 0 ? accent : Wandr.secondaryText)
                    .frame(minWidth: 18)

                Image(systemName: isWinner ? "checkmark.circle.fill"
                      : (isMine ? "largecircle.fill.circle" : "circle"))
                    .foregroundStyle(isWinner || isMine ? accent : Wandr.hairline)
                    .opacity(locked && !isWinner ? 0.4 : 1)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background { tallyBar(fraction: fraction, isWinner: isWinner) }
        }
        .buttonStyle(WandrPressStyle())
        .disabled(!interactive)
        .opacity(locked && !isWinner ? 0.55 : 1)
        .accessibilityLabel("\(option.label), \(votes) votes\(isMine ? ", your pick" : "")\(isWinner ? ", winner" : "")")
    }

    /// The row's own share of the room, drawn behind it. A `GeometryReader` in a background reads the row's width without ever influencing the layout, and clipping to the row shape keeps the bar's leading corners honest — scaling a rounded rectangle would bend them into ellipses.
    private func tallyBar(fraction: Double, isWinner: Bool) -> some View {
        let shape = ConcentricRectangle(corners: .concentric(minimum: .fixed(Metrics.blockCorner)))
        return shape
            .fill(isWinner ? accent.opacity(0.12) : Wandr.pageBackground.opacity(0.5))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(accent.opacity(isWinner ? 0.18 : 0.13))
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .clipShape(shape)
    }
}

#Preview("Offline fallback") {
    let decks = Array(DemoPlan.decks.prefix(2)).map { deck -> Deck in
        var d = deck
        d.shortlist = Array(d.candidates.prefix(3)).map(\.id)
        return d
    }
    return SquadPollView(session: PollSession(decks: decks, groupSize: 4)) { _ in }
}
