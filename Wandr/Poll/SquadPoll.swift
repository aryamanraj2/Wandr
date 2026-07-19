//
//  SquadPoll.swift
//  Wandr
//
//  The per-slot squad poll. One `SquadSlotPoll` per shortlisted slot: the squad
//  votes on the places the host slated, and the slot locks to the place with the
//  most votes — but only once everyone (`size`) has voted (Docs/plan.md §6.5,
//  with the lock rule amended from Approve/Veto to plurality-max).
//
//  This is the pure, UI-free brain. Phase 1 drives it from an in-app simulation;
//  Phase 2 lifts the same types into the `WandrMessages` iMessage extension, where
//  `ParticipantID` maps to `MSConversation.localParticipantIdentifier` and the poll
//  is serialized onto `MSMessage.url`. Nothing here imports a UI framework.
//

import Foundation

// MARK: - Identity

/// The stable identity of one option inside a slot's poll.
///
/// Derived deterministically from the venue (a name slug in Phase 1), never a
/// runtime `UUID` — the same reason `CuratedCandidate` carries a `VenueID`. A
/// runtime id would not survive serialization into the iMessage payload or match
/// across devices. When curation runs on real `GroundedVenue` data this becomes
/// the dataset `VenueID`.
nonisolated struct PollOptionID: Sendable, Equatable, Hashable, Comparable, CustomStringConvertible {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// A deterministic, URL-safe slug of a display name: lowercased, each run of
    /// non-alphanumerics collapsed to a single hyphen, trimmed at both ends.
    init(slugging name: String) {
        var slug = ""
        var pendingHyphen = false
        for scalar in name.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if pendingHyphen, !slug.isEmpty { slug.append("-") }
                pendingHyphen = false
                slug.unicodeScalars.append(scalar)
            } else {
                pendingHyphen = true
            }
        }
        self.rawValue = slug
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var description: String { rawValue }
}

/// A voter's identity, scoped to one poll. Per-device and pseudonymous — no account,
/// no contact. Phase 2 sources this from `MSConversation.localParticipantIdentifier`;
/// Phase 1 mints synthetic ones for the in-app simulation.
nonisolated struct ParticipantID: Sendable, Equatable, Hashable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

// MARK: - Option

/// One place the squad can vote for in a slot. Carries only what the vote UI shows;
/// resolving a winner back to a schedule stop is the caller's job (it holds the
/// candidate lookup), which keeps this type free of any UI-layer model.
nonisolated struct PollOption: Sendable, Equatable, Identifiable {
    let id: PollOptionID
    let label: String
    let subtitle: String

    init(id: PollOptionID, label: String, subtitle: String) {
        self.id = id
        self.label = label
        self.subtitle = subtitle
    }
}

// MARK: - Poll

/// A single slot's poll plus its running votes.
///
/// A vote is one option per participant; a re-vote overwrites (honest dedupe).
/// Once `lockedWinner` is set the poll is closed — later votes are ignored, matching
/// the post-lock rule in the Docs. The poll never picks its own winner: `PollTally`
/// reads the state and the session decides when to `lock`.
nonisolated struct SquadSlotPoll: Sendable, Equatable, Identifiable {
    /// Stable slot identity (the slot's category raw value in Phase 1).
    let slotID: String
    /// Human name for the slot, e.g. "Dinner".
    let slotName: String
    let options: [PollOption]
    /// Quorum N — everyone who must vote before the slot can lock. Sourced from
    /// the brief's group size, host-adjustable before sending.
    let size: Int

    /// One option per participant. Re-voting overwrites the prior choice.
    private(set) var votes: [ParticipantID: PollOptionID]
    /// Set exactly once, when the slot locks. `nil` means the poll is still open.
    private(set) var lockedWinner: PollOptionID?

    var id: String { slotID }

    var isLocked: Bool { lockedWinner != nil }

    init(
        slotID: String,
        slotName: String,
        options: [PollOption],
        size: Int,
        votes: [ParticipantID: PollOptionID] = [:],
        lockedWinner: PollOptionID? = nil
    ) {
        self.slotID = slotID
        self.slotName = slotName
        self.options = options
        self.size = size
        self.votes = votes
        self.lockedWinner = lockedWinner
    }

    /// Records a vote. Ignored once locked, or when the option isn't in this poll.
    mutating func cast(_ option: PollOptionID, by participant: ParticipantID) {
        guard !isLocked else { return }
        guard options.contains(where: { $0.id == option }) else { return }
        votes[participant] = option
    }

    /// Closes the poll on a winner — the auto-resolved plurality leader, or the
    /// host's pick when the squad tied. Ignored if the winner isn't a real option.
    mutating func lock(to winner: PollOptionID) {
        guard options.contains(where: { $0.id == winner }) else { return }
        lockedWinner = winner
    }

    func option(_ id: PollOptionID) -> PollOption? {
        options.first { $0.id == id }
    }
}
