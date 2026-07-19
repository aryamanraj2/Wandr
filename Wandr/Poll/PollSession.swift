//
//  PollSession.swift
//  Wandr
//
//  The app-layer state behind the Send-to-Squad surface. It seeds one `SquadSlotPoll`
//  per slated slot from the host's slate and the brief's group size, holds the running
//  votes, and resolves each slot's winning place back to a `Candidate` for the schedule.
//
//  The vote maths live in `PollTally` (pure); this type only decides *when* to lock and
//  owns the Phase-1 simulation seam. In Phase 2 the same polls ride an `MSMessage` and
//  real participant votes replace `castSimulatedVote`.
//

import Foundation
import Observation

@MainActor
@Observable
final class PollSession {

    /// One poll per slated slot, in curation order.
    private(set) var polls: [SquadSlotPoll]

    /// Quorum N — how many votes each slot waits for. Host-adjustable before the votes
    /// come in; sourced from the brief's group size.
    private(set) var quorumSize: Int

    /// A poll needs at least two voters to be a poll.
    let minQuorum = 2

    /// Resolves a winning option back to the place the host slated, keyed per slot so
    /// two slots sharing a venue name never cross-resolve.
    private let candidatesByKey: [String: Candidate]

    /// Monotonic counter minting a fresh pseudonymous voter per simulated vote.
    private var simulatedVoterCount = 0

    /// Builds a session from the curation decks. Only slots the host actually slated
    /// (non-empty shortlist) get a poll.
    init(decks: [Deck], groupSize: Int?) {
        let slated = decks.filter { !$0.shortlist.isEmpty }

        // Default N: the brief's stated size, else the widest slate as a stand-in.
        let impliedSize = slated.map(\.shortlisted.count).max() ?? minQuorum
        let n = max(minQuorum, groupSize ?? impliedSize)
        self.quorumSize = n

        var lookup: [String: Candidate] = [:]
        self.polls = slated.map { deck in
            let options = deck.shortlisted.map { candidate -> PollOption in
                let id = PollOptionID(slugging: candidate.name)
                lookup[Self.key(slotID: deck.category.rawValue, option: id)] = candidate
                return PollOption(
                    id: id,
                    label: candidate.name,
                    subtitle: "\(candidate.area) · ₹\(candidate.perHead)"
                )
            }
            return SquadSlotPoll(
                slotID: deck.category.rawValue,
                slotName: deck.slotName,
                options: options,
                size: n
            )
        }
        self.candidatesByKey = lookup
    }

    // MARK: - Derived state

    /// Every slot has locked to a winner — the night is decided.
    var allDecided: Bool {
        !polls.isEmpty && polls.allSatisfy(\.isLocked)
    }

    func resolution(for poll: SquadSlotPoll) -> PollResolution {
        PollTally.resolution(poll)
    }

    func counts(for poll: SquadSlotPoll) -> [PollOptionID: Int] {
        PollTally.counts(poll)
    }

    /// The winning place per decided slot, in curation order — the input to the schedule.
    func winners() -> [(slotID: String, candidate: Candidate)] {
        polls.compactMap { poll in
            guard let winner = poll.lockedWinner,
                  let candidate = candidatesByKey[Self.key(slotID: poll.slotID, option: winner)]
            else { return nil }
            return (poll.slotID, candidate)
        }
    }

    // MARK: - Host actions

    /// Adjusts quorum for every slot, preserving votes already cast. Lowering N can push
    /// a slot to a decision immediately, so re-evaluate locks afterward.
    func setQuorum(_ n: Int) {
        let clamped = max(minQuorum, n)
        guard clamped != quorumSize else { return }
        quorumSize = clamped
        polls = polls.map { poll in
            SquadSlotPoll(
                slotID: poll.slotID,
                slotName: poll.slotName,
                options: poll.options,
                size: clamped,
                votes: poll.votes,
                lockedWinner: poll.lockedWinner
            )
        }
        for index in polls.indices { autoLock(at: index) }
    }

    /// The one interaction on a slot's options. Below quorum a tap is a (simulated) vote.
    /// At a tie a tap is the host breaking it. A decided slot has already auto-locked.
    func tap(_ option: PollOptionID, inSlot slotID: String) {
        guard let index = polls.firstIndex(where: { $0.slotID == slotID }) else { return }
        guard !polls[index].isLocked else { return }

        if PollTally.quorumReached(polls[index]) {
            // Quorum met but still open ⇒ it was a tie; the host's tap is the tie-break.
            polls[index].lock(to: option)
        } else {
            castSimulatedVote(option, at: index)
        }
    }

    // MARK: - Phase 1 simulation seam

    /// Records one vote from a fresh pseudonymous voter. Phase 2 replaces this with real
    /// `MSSession` votes keyed on `MSConversation.localParticipantIdentifier`.
    private func castSimulatedVote(_ option: PollOptionID, at index: Int) {
        simulatedVoterCount += 1
        polls[index].cast(option, by: ParticipantID("sim-\(simulatedVoterCount)"))
        autoLock(at: index)
    }

    /// Locks a slot the moment it has a single plurality leader at quorum. Ties are left
    /// open for the host to break.
    private func autoLock(at index: Int) {
        guard !polls[index].isLocked else { return }
        if case .decided(let winner) = PollTally.resolution(polls[index]) {
            polls[index].lock(to: winner)
        }
    }

    private static func key(slotID: String, option: PollOptionID) -> String {
        "\(slotID)#\(option.rawValue)"
    }
}
