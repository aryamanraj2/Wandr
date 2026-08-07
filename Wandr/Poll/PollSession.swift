// PollSession.swift Wandr The app-layer state behind the Send-to-Squad surface, and the one seam between a real squad and a simulated one.
//
// Originally this type *was* the squad: `castSimulatedVote` minted a throwaway `ParticipantID` on every tap so one finger could play six voters. That simulation seam is now the network seam. Given a `SquadRoom` it delegates every reading to the live snapshot and forwards every tap to the relay; given none it behaves exactly as it always did. The fallback is deliberate rather than vestigial — a relay that isn't running must not be able to kill a demo.
//
// The vote maths are untouched either way: `PollTally` is pure and deterministic, so the offline session and three networked devices are all running the identical rule.

import Foundation
import Observation

@MainActor
@Observable
final class PollSession {

    /// The live room, when there is one. `nil` runs the offline simulation.
    private let room: SquadRoom?

    /// Polls owned by this session — the offline path only. In live mode the polls are rebuilt from the snapshot on every read and this stays empty.
    private var localPolls: [SquadSlotPoll]
    private var localQuorum: Int

    /// A poll needs at least two voters to be a poll.
    let minQuorum = 2

    /// Resolves a winning option back to the place the host slated, keyed per slot so two slots sharing a venue name never cross-resolve. Offline only; the live path resolves through the ballot on the wire, which works on devices that never ran curation.
    private let candidatesByKey: [String: Candidate]

    /// Monotonic counter minting a fresh pseudonymous voter per simulated vote, and doubling as the offline animation clock.
    private var simulatedVoterCount = 0

    /// Builds an offline session from the curation decks. Only slots the host actually slated (non-empty shortlist) get a poll.
    init(decks: [Deck], groupSize: Int?) {
        self.room = nil

        let slated = decks.filter { !$0.shortlist.isEmpty }

        // Default N: the brief's stated size, else the widest slate as a stand-in.
        let impliedSize = slated.map(\.shortlisted.count).max() ?? minQuorum
        let n = max(minQuorum, groupSize ?? impliedSize)
        self.localQuorum = n

        var lookup: [String: Candidate] = [:]
        self.localPolls = slated.map { deck in
            let options = deck.shortlisted.map { candidate -> PollOption in
                let id = PollOptionID(slugging: candidate.name)
                lookup[Self.key(slotID: deck.slotID, option: id)] = candidate
                return PollOption(
                    id: id,
                    label: candidate.name,
                    subtitle: "\(candidate.area) · ₹\(candidate.perHead)",
                    imageSeed: candidate.imageSeed
                )
            }
            return SquadSlotPoll(
                slotID: deck.slotID,
                slotName: deck.slotName,
                options: options,
                size: n
            )
        }
        self.candidatesByKey = lookup
    }

    /// Builds a session against a live room. The ballot arrives over the wire, so this is the same initializer on the leader's device and on a joiner that never saw a deck.
    init(room: SquadRoom) {
        self.room = room
        self.localPolls = []
        self.localQuorum = minQuorum
        self.candidatesByKey = [:]
    }

    // MARK: - Derived state

    var isLive: Bool { room != nil }

    /// One poll per slated slot, in slate order.
    var polls: [SquadSlotPoll] {
        room?.polls ?? localPolls
    }

    /// Quorum N — how many votes each slot waits for. Live, that is simply how many people are in the room; there is nothing left to set by hand.
    var quorumSize: Int {
        room?.quorum ?? localQuorum
    }

    /// Every slot has a winner — the night is decided.
    var allDecided: Bool {
        if let room { return room.allDecided }
        return !localPolls.isEmpty && localPolls.allSatisfy(\.isLocked)
    }

    /// Only the leader breaks a tie. Offline there is only one person, so they are it.
    var isLeader: Bool {
        room.map(\.isLeader) ?? true
    }

    var leaderName: String {
        room?.leaderName ?? "you"
    }

    /// Changes on every mutation the room has seen. Views animate on this rather than wrapping the mutation, because snapshots arrive inside an async continuation where a transaction is unreliable.
    var version: Int {
        room?.snapshot?.version ?? simulatedVoterCount
    }

    func resolution(for poll: SquadSlotPoll) -> PollResolution {
        PollTally.resolution(poll)
    }

    func counts(for poll: SquadSlotPoll) -> [PollOptionID: Int] {
        PollTally.counts(poll)
    }

    /// What *this* device chose in a slot, so its own row reads as chosen rather than merely counted. Nothing to show offline: the simulated voters are not you.
    func myVote(in slotID: String) -> PollOptionID? {
        room?.myVote(in: slotID)
    }

    /// How many people have voted in a slot — the live "2 of 3 in" figure.
    func voted(in slotID: String) -> Int {
        room?.voted(in: slotID) ?? (polls.first { $0.slotID == slotID }?.votes.count ?? 0)
    }

    /// The winning place per decided slot, in slate order — the input to the schedule.
    func winners() -> [(slotID: String, candidate: Candidate)] {
        if let room { return room.winners() }
        return localPolls.compactMap { poll in
            guard let winner = poll.lockedWinner,
                  let candidate = candidatesByKey[Self.key(slotID: poll.slotID, option: winner)]
            else { return nil }
            return (poll.slotID, candidate)
        }
    }

    // MARK: - Acting on a slot

    /// Whether a tap on this slot does anything right now. A decided slot is closed to everyone; a tied one is the leader's call alone, and a joiner watching that tie should not be offered a button that quietly does nothing.
    func canTap(_ poll: SquadSlotPoll) -> Bool {
        switch PollTally.resolution(poll) {
        case .decided: return false
        case .tie:     return isLeader
        case .pending: return true
        }
    }

    /// The one interaction on a slot's options. Below quorum a tap is a vote. At a tie it is the leader breaking it.
    func tap(_ option: PollOptionID, inSlot slotID: String) {
        guard let poll = polls.first(where: { $0.slotID == slotID }), canTap(poll) else { return }

        if case .tie = PollTally.resolution(poll) {
            breakTie(option, in: slotID)
        } else {
            cast(option, in: slotID)
        }
    }

    private func cast(_ option: PollOptionID, in slotID: String) {
        if let room {
            room.vote(option, in: slotID)
        } else if let index = localPolls.firstIndex(where: { $0.slotID == slotID }) {
            castSimulatedVote(option, at: index)
        }
    }

    private func breakTie(_ option: PollOptionID, in slotID: String) {
        if let room {
            room.breakTie(option, in: slotID)
        } else if let index = localPolls.firstIndex(where: { $0.slotID == slotID }) {
            localPolls[index].lock(to: option)
        }
    }

    // MARK: - Offline simulation

    /// Records one vote from a fresh pseudonymous voter. Only reachable with no room attached.
    private func castSimulatedVote(_ option: PollOptionID, at index: Int) {
        simulatedVoterCount += 1
        localPolls[index].cast(option, by: ParticipantID("sim-\(simulatedVoterCount)"))
        autoLock(at: index)
    }

    /// Locks a slot the moment it has a single plurality leader at quorum. Ties are left open for the host to break. Live, no equivalent exists and none is needed — every device derives the same winner from the same votes through the same pure tally, so there is no winner to record.
    private func autoLock(at index: Int) {
        guard !localPolls[index].isLocked else { return }
        if case .decided(let winner) = PollTally.resolution(localPolls[index]) {
            localPolls[index].lock(to: winner)
        }
    }

    private static func key(slotID: String, option: PollOptionID) -> String {
        "\(slotID)#\(option.rawValue)"
    }
}
