// SquadLobbyView.swift Wandr The room before the vote: a code big enough to read across a table, and the squad arriving one chip at a time. The leader starts the vote; everyone else waits. This is also the screen that has to say "the relay went away" out loud rather than spinning forever, because a room that silently stops is the worst thing that can happen mid-demo.

import SwiftUI

struct SquadLobbyView: View {
    let room: SquadRoom

    /// The leader's way out of the room. `nil` for a joiner, who has nowhere to go back to.
    var onCancel: (() -> Void)?

    /// The relay never came up. Offered only once that is actually the case, and only to the leader — a demo must not be able to die because a terminal window got closed.
    var onFallBackOffline: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            if room.failure == .noSuchRoom {
                ended
            } else {
                header
                codePlate
                roster
            }

            Spacer(minLength: 0)

            footer
        }
        .padding(.horizontal, Metrics.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Wandr.pageBackground)
        .animation(.wandrTransition, value: room.participants.count)
        .animation(.wandrResponse, value: room.connection)
        .animation(.wandrTransition, value: room.failure)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            Text(room.isLeader ? "Your room is open" : "You're in")
                .font(.wandrDisplay(34))
                .foregroundStyle(Wandr.primaryText)
                .multilineTextAlignment(.center)

            Text(room.isLeader
                 ? "Read the code out. Everyone types it in on their own phone."
                 : "\(room.leaderName) starts the vote when everyone's here.")
                .font(.subheadline)
                .foregroundStyle(Wandr.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
        }
        .padding(.bottom, 30)
    }

    // MARK: Code

    /// The one thing on this screen anyone actually needs. Set at display size and in two halves, which is how a code gets dictated out loud.
    private var codePlate: some View {
        VStack(spacing: 8) {
            Text(room.code?.spoken ?? "· · ·  · · ·")
                .font(.system(size: 52, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .tracking(4)
                .contentTransition(.numericText())
                .foregroundStyle(Wandr.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text("Room code")
                .wandrLabelStyle()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(WandrCardBackground())
        .padding(.bottom, 26)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(room.code.map { "Room code \($0.rawValue.map(String.init).joined(separator: " "))" } ?? "Waiting for a room code")
    }

    // MARK: Roster

    private var roster: some View {
        VStack(spacing: 14) {
            Text(room.participants.count == 1 ? "1 in the room" : "\(room.participants.count) in the room")
                .font(.footnote.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
                .foregroundStyle(Wandr.secondaryText)

            // Wrapping, so a sixth arrival pushes onto a second line rather than squeezing the first five.
            WrappingChips(participants: room.participants, me: room.me)
        }
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 14) {
            connectionLine

            if room.failure == .noSuchRoom {
                Button {
                    onCancel?()
                } label: {
                    Text("Back")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .tint(Wandr.brand)
            } else if room.isLeader {
                Button {
                    room.startVoting()
                } label: {
                    Label("Start voting", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .tint(Wandr.brand)
                // A poll of one is not a poll.
                .disabled(room.participants.count < 2 || room.connection != .live)

                if room.connection != .live, let onFallBackOffline {
                    Button("Vote on this device instead", action: onFallBackOffline)
                        .font(.subheadline.weight(.medium))
                        .tint(Wandr.brand)
                } else if let onCancel {
                    Button("Cancel the room", action: onCancel)
                        .font(.subheadline.weight(.medium))
                        .tint(Wandr.secondaryText)
                }
            } else {
                Label("Waiting for \(room.leaderName)…", systemImage: "hourglass")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Wandr.secondaryText)
                    .padding(.vertical, 10)
            }
        }
        .padding(.bottom, 24)
    }

    /// Quiet until it matters. A live room says nothing; a reconnecting one says so, because the alternative is a screen that just stops updating.
    @ViewBuilder
    private var connectionLine: some View {
        switch room.connection {
        case .live:
            EmptyView()
        case .connecting:
            Label("Finding the room…", systemImage: "antenna.radiowaves.left.and.right")
                .font(.caption)
                .foregroundStyle(Wandr.secondaryText)
        case .offline:
            Label("Reconnecting…", systemImage: "antenna.radiowaves.left.and.right.slash")
                .font(.caption)
                .foregroundStyle(Wandr.secondaryText)
        }
    }

    // MARK: Ended

    /// The relay restarted and took the room with it. Nothing to recover, so say that plainly.
    private var ended: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.bubble")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Wandr.secondaryText)

            Text("That room has ended")
                .font(.wandrDisplay(30))
                .foregroundStyle(Wandr.primaryText)

            Text("The host will need to send a new code.")
                .font(.subheadline)
                .foregroundStyle(Wandr.secondaryText)
        }
        .multilineTextAlignment(.center)
    }
}

// MARK: - Chips

/// The squad, as they arrive. Laid out with `Layout` rather than an `HStack` so the row wraps instead of compressing — a name is not something to squeeze.
private struct WrappingChips: View {
    let participants: [ParticipantWire]
    let me: ParticipantID

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(participants) { participant in
                chip(participant)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
    }

    private func chip(_ participant: ParticipantWire) -> some View {
        let isMe = participant.id == me
        return HStack(spacing: 6) {
            if participant.isLeader {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Wandr.brand)
            }
            Text(isMe ? "\(participant.name) (you)" : participant.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Wandr.primaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background {
            Capsule()
                .fill(isMe ? Wandr.brand.opacity(0.12) : Wandr.mist.opacity(0.3))
        }
        .overlay {
            Capsule().stroke(Wandr.mist.opacity(0.5), lineWidth: 1)
        }
    }
}

/// A minimal wrapping row. Only used here, so it stays private rather than becoming a design-system component on the strength of one caller.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(subviews, in: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, in: bounds.width) {
            // Centred, so a trailing half-row reads as part of the group rather than as an orphan.
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(_ subviews: Subviews, in width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let projected = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if projected > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }

        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
