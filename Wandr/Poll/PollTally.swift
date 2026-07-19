//
//  PollTally.swift
//  Wandr
//
//  The lock rule, as a set of pure functions over a `SquadSlotPoll`. This is the
//  single owner of "who won and are we done yet" — the plurality-max analogue of
//  the Docs' `LockRule`. It reads a poll and never mutates one; deciding *when* to
//  lock belongs to the session, which acts on this reading.
//
//  Like `FeasibilityValidator`, nothing here touches a model, the network, disk, or
//  a UI framework — which is the point. It is exercised entirely by `PollTallyTests`.
//

import Foundation

/// Where a slot poll stands.
nonisolated enum PollResolution: Sendable, Equatable {
    /// Not everyone has voted yet. No winner is revealed.
    case pending(received: Int, of: Int)
    /// Quorum reached with a single plurality leader — the winning option.
    case decided(PollOptionID)
    /// Quorum reached but two or more options are tied at the top. The host breaks it.
    case tie([PollOptionID])
}

nonisolated enum PollTally {

    /// Votes per option. Options with zero votes are omitted.
    static func counts(_ poll: SquadSlotPoll) -> [PollOptionID: Int] {
        poll.votes.values.reduce(into: [:]) { tallies, option in
            tallies[option, default: 0] += 1
        }
    }

    /// Whether everyone has voted. Quorum is met when the number of distinct
    /// voters reaches `size` (dedupe means each participant counts once).
    static func quorumReached(_ poll: SquadSlotPoll) -> Bool {
        poll.votes.count >= poll.size
    }

    /// The poll's standing. A locked poll reports its recorded winner. Otherwise the
    /// winner stays hidden until quorum, then it is the plurality leader — or a tie
    /// when several options share the top count.
    static func resolution(_ poll: SquadSlotPoll) -> PollResolution {
        if let winner = poll.lockedWinner {
            return .decided(winner)
        }

        guard quorumReached(poll) else {
            return .pending(received: poll.votes.count, of: poll.size)
        }

        let counts = counts(poll)
        guard let top = counts.values.max() else {
            // Quorum with no counted votes is unreachable for size > 0, but stay total.
            return .pending(received: poll.votes.count, of: poll.size)
        }

        // Sort tied leaders for a deterministic result and message.
        let leaders = counts.filter { $0.value == top }.keys.sorted()
        return leaders.count == 1 ? .decided(leaders[0]) : .tie(leaders)
    }
}
