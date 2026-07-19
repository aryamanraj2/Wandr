//
//  PollTallyTests.swift
//  WandrTests
//
//  The plurality lock rule, one test per rule. Like the feasibility tests, none of
//  these touch a model, the network, disk, or a UI framework — `PollTally` is pure,
//  and if this file ever needs a simulator the poll brain has grown a dependency it
//  shouldn't have.
//

import Foundation
import Testing
@testable import Wandr

@Suite("PollTally")
struct PollTallyTests {

    // MARK: - Helpers

    private func poll(size: Int) -> SquadSlotPoll {
        SquadSlotPoll(
            slotID: "food",
            slotName: "Dinner",
            options: [
                PollOption(id: PollOptionID("diggin"), label: "Diggin", subtitle: ""),
                PollOption(id: PollOptionID("comorin"), label: "Comorin", subtitle: ""),
                PollOption(id: PollOptionID("olive"), label: "Olive Bistro", subtitle: "")
            ],
            size: size
        )
    }

    private func voter(_ n: Int) -> ParticipantID { ParticipantID("p\(n)") }

    // MARK: - Rules

    @Test("Winner stays hidden until everyone has voted")
    func pendingBelowQuorum() {
        var p = poll(size: 3)
        p.cast(PollOptionID("diggin"), by: voter(1))
        p.cast(PollOptionID("diggin"), by: voter(2))

        #expect(PollTally.quorumReached(p) == false)
        #expect(PollTally.resolution(p) == .pending(received: 2, of: 3))
    }

    @Test("At quorum the plurality leader wins")
    func pluralityWinnerAtQuorum() {
        var p = poll(size: 3)
        p.cast(PollOptionID("diggin"), by: voter(1))
        p.cast(PollOptionID("diggin"), by: voter(2))
        p.cast(PollOptionID("comorin"), by: voter(3))

        #expect(PollTally.quorumReached(p))
        #expect(PollTally.resolution(p) == .decided(PollOptionID("diggin")))
    }

    @Test("A top-count tie is reported, not silently resolved")
    func tieIsReported() {
        var p = poll(size: 2)
        p.cast(PollOptionID("diggin"), by: voter(1))
        p.cast(PollOptionID("comorin"), by: voter(2))

        // Sorted for determinism: "comorin" < "diggin".
        #expect(PollTally.resolution(p) == .tie([PollOptionID("comorin"), PollOptionID("diggin")]))
    }

    @Test("Host tie-break locks the poll to the chosen option")
    func hostBreaksTie() {
        var p = poll(size: 2)
        p.cast(PollOptionID("diggin"), by: voter(1))
        p.cast(PollOptionID("comorin"), by: voter(2))
        p.lock(to: PollOptionID("comorin"))

        #expect(p.isLocked)
        #expect(PollTally.resolution(p) == .decided(PollOptionID("comorin")))
    }

    @Test("Votes arriving after lock are ignored")
    func postLockVotesIgnored() {
        var p = poll(size: 2)
        p.cast(PollOptionID("diggin"), by: voter(1))
        p.cast(PollOptionID("diggin"), by: voter(2))
        p.lock(to: PollOptionID("diggin"))

        p.cast(PollOptionID("comorin"), by: voter(3))

        #expect(PollTally.counts(p)[PollOptionID("comorin")] == nil)
        #expect(PollTally.resolution(p) == .decided(PollOptionID("diggin")))
    }

    @Test("A participant re-voting overwrites rather than double-counts")
    func revoteDedupes() {
        var p = poll(size: 3)
        p.cast(PollOptionID("diggin"), by: voter(1))
        p.cast(PollOptionID("comorin"), by: voter(1)) // same voter changes mind

        #expect(p.votes.count == 1)
        #expect(PollTally.counts(p)[PollOptionID("diggin")] == nil)
        #expect(PollTally.counts(p)[PollOptionID("comorin")] == 1)
        #expect(PollTally.quorumReached(p) == false)
    }

    @Test("A vote for an option outside the poll is rejected")
    func unknownOptionRejected() {
        var p = poll(size: 1)
        p.cast(PollOptionID("not-a-real-place"), by: voter(1))

        #expect(p.votes.isEmpty)
    }

    @Test("Option id slugs are deterministic, lowercased, and collapse punctuation")
    func slugging() {
        #expect(PollOptionID(slugging: "Olive Bistro").rawValue == "olive-bistro")
        #expect(PollOptionID(slugging: "Dhaba by Claridges").rawValue == "dhaba-by-claridges")
        // Runs of non-alphanumerics collapse to one hyphen; leading/trailing are trimmed.
        #expect(PollOptionID(slugging: "  Depot48 — Open Mic! ").rawValue == "depot48-open-mic")
    }
}
