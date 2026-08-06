// SquadWireTests.swift WandrTests The protocol three devices and a relay agree on. Two things are being defended here.
//
// First, that every type survives a round trip — a wire format that silently drops a field is a bug that only ever shows up on someone else's phone, mid-demo.
//
// Second, and more important: that `PollOptionID(slugging:)` is stable for the same venue name across separately-constructed `Candidate`s. Every `Candidate` mints a fresh `UUID`, so the slug is the *only* thing that can identify a place on two devices at once. The whole cross-device design rests on that one property; if it ever stops holding, votes stop landing on the same option and nothing above it can compensate.

import Foundation
import Testing
@testable import Wandr

@Suite("SquadWire")
struct SquadWireTests {

    // MARK: - Helpers

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try SquadWire.encoder.encode(value)
        return try SquadWire.decoder.decode(T.self, from: data)
    }

    private var candidate: Candidate {
        Candidate(
            name: "Olive Bistro", area: "Mehrauli",
            tagline: "Whitewashed Mediterranean courtyard beside the Qutub.",
            category: .food, perHead: 1_800, listPrice: 2_200,
            offer: "Complimentary dessert", offerWindow: "all evening",
            openWindow: "Open till midnight", travelNote: "22 min by cab",
            imageSeed: 2,
            rationale: "Fits the budget and the vibe.",
            costUnknown: false,
            warnings: ["Hours unverified"],
            story: "Bougainvillea over whitewashed walls.",
            highlights: ["Qutub visible from the courtyard", "Wood-fired breads"],
            insiderTip: "Ask for the upper terrace."
        )
    }

    // MARK: - The property everything else rests on

    @Test("The same venue name slugs identically across separately built candidates")
    func slugIsStableAcrossCandidates() {
        let here = candidate
        let there = candidate

        // Two Candidates for the same place, built independently — as they are on a host's device and on a joiner's.
        #expect(here.id != there.id, "Candidate ids are per-process UUIDs and must never be the identity on the wire")
        #expect(here.wire.optionID == there.wire.optionID)
        #expect(here.wire.optionID == PollOptionID(slugging: "Olive Bistro"))
    }

    @Test("Slugging normalises punctuation, case and spacing the same way everywhere")
    func slugNormalises() {
        #expect(PollOptionID(slugging: "Dhaba by Claridges").rawValue == "dhaba-by-claridges")
        #expect(PollOptionID(slugging: "  Humayun's  Tomb ").rawValue == "humayun-s-tomb")
        #expect(PollOptionID(slugging: "Depot48 — Open Mic").rawValue == "depot48-open-mic")
    }

    // MARK: - Round trips

    @Test("A candidate survives the wire with every card field intact")
    func candidateRoundTrips() throws {
        let wire = candidate.wire
        let decoded = try roundTrip(wire)
        #expect(decoded == wire)

        // And back into the model a joiner will render.
        let rebuilt = Candidate(wire: decoded)
        #expect(rebuilt.name == candidate.name)
        #expect(rebuilt.category == candidate.category)
        #expect(rebuilt.listPrice == candidate.listPrice)
        #expect(rebuilt.offerWindow == candidate.offerWindow)
        #expect(rebuilt.warnings == candidate.warnings)
        #expect(rebuilt.highlights == candidate.highlights)
        #expect(rebuilt.insiderTip == candidate.insiderTip)
        #expect(rebuilt.rationale == candidate.rationale)
        #expect(rebuilt.story == candidate.story)
        #expect(rebuilt.savings == candidate.savings)
    }

    @Test("Identities encode as bare strings, not as wrapped objects")
    func identitiesAreFlat() throws {
        let option = PollOptionID("diggin")
        #expect(String(decoding: try SquadWire.encoder.encode(option), as: UTF8.self) == "\"diggin\"")

        let participant = ParticipantID("p-1")
        #expect(String(decoding: try SquadWire.encoder.encode(participant), as: UTF8.self) == "\"p-1\"")

        let decodedOption = try roundTrip(option)
        let decodedParticipant = try roundTrip(participant)
        #expect(decodedOption == option)
        #expect(decodedParticipant == participant)
    }

    @Test("A room code is six digits and only accepts six digits")
    func roomCode() throws {
        let code = RoomCode.random()
        #expect(code.rawValue.count == RoomCode.length)
        let allDigits = code.rawValue.allSatisfy(\.isNumber)
        #expect(allDigits)
        let decoded = try roundTrip(code)
        #expect(decoded == code)

        #expect(RoomCode(entering: "428301") != nil)
        #expect(RoomCode(entering: "42830") == nil)
        #expect(RoomCode(entering: "4283011") == nil)
        #expect(RoomCode(entering: "42830a") == nil)
        #expect(RoomCode(entering: "428 301") == nil)
    }

    @Test("A whole snapshot round trips")
    func snapshotRoundTrips() throws {
        let snapshot = RoomSnapshot(
            version: 7,
            code: RoomCode("428301"),
            phase: .voting,
            participants: [
                ParticipantWire(id: ParticipantID("pA"), name: "Aryaman", isLeader: true),
                ParticipantWire(id: ParticipantID("pB"), name: "Nikhil", isLeader: false)
            ],
            ballot: [
                SlotBallotWire(slotID: "dinner", slotName: "Dinner", window: "8–10 pm",
                               options: [candidate.wire])
            ],
            votes: [VoteWire(participant: ParticipantID("pB"), slot: "dinner",
                             option: candidate.wire.optionID)],
            tieBreaks: ["late": PollOptionID("piano-man")],
            itinerary: nil
        )

        let decoded = try roundTrip(snapshot)
        #expect(decoded == snapshot)
        #expect(decoded.leader?.name == "Aryaman")
    }

    @Test("Every client and server message round trips")
    func messagesRoundTrip() throws {
        let ballot = [SlotBallotWire(slotID: "dinner", slotName: "Dinner", window: "8–10 pm",
                                     options: [candidate.wire])]

        // Compared as values, not as bytes. `JSONEncoder` gives no ordering guarantee across encodes, and it does not need to — both ends decode by key. What must hold is that the message that comes out means the same thing as the one that went in.
        for message: ClientMessage in [
            .host(ballot: ballot, name: "Aryaman", participant: ParticipantID("pA")),
            .join(code: RoomCode("428301"), name: "Ria", participant: ParticipantID("pC")),
            .vote(slot: "dinner", option: PollOptionID("diggin")),
            .tieBreak(slot: "late", option: PollOptionID("piano-man")),
            .advance(to: .adjusting),
            .publish(itinerary: [ScheduleBlockWire(title: "Diggin", category: "food",
                                                   startMinute: 1_200, durationMinutes: 90,
                                                   dayDate: Date(timeIntervalSince1970: 1_770_000_000))])
        ] {
            let decoded = try roundTrip(message)
            #expect(decoded == message)
        }

        let welcome = try SquadWire.encoder.encode(
            ServerMessage.welcome(code: RoomCode("428301"), you: ParticipantID("pA"))
        )
        let decoded = try SquadWire.decoder.decode(ServerMessage.self, from: welcome)
        guard case .welcome(let code, let you) = decoded else {
            Issue.record("welcome did not decode as welcome"); return
        }
        #expect(code == RoomCode("428301"))
        #expect(you == ParticipantID("pA"))

        for failure in [RoomFailure.noSuchRoom, .roomFull, .notLeader] {
            let data = try SquadWire.encoder.encode(ServerMessage.failure(failure))
            guard case .failure(let decoded) = try SquadWire.decoder.decode(ServerMessage.self, from: data) else {
                Issue.record("failure did not decode as failure"); return
            }
            #expect(decoded == failure)
        }
    }

    // MARK: - Schedule blocks carry a date, never a day id

    @Test("A published block resolves to the receiving device's own day")
    func scheduleBlockResolvesLocally() throws {
        let day = DemoPlan.days[0]
        let block = ScheduleBlock(title: "Piano Man", category: .nightlife,
                                  startMinute: 21 * 60, durationMinutes: 120, dayID: day.id)

        let wire = try roundTrip(block.wire())
        #expect(Calendar.current.isDate(wire.dayDate, inSameDayAs: day.date))

        // The receiving device knows nothing of the sender's `PlanDay.ID` — it matches on the calendar day and uses its own.
        let rebuilt = ScheduleBlock(wire: wire)
        #expect(rebuilt.dayID == day.id)
        #expect(rebuilt.title == block.title)
        #expect(rebuilt.category == block.category)
        #expect(rebuilt.startMinute == block.startMinute)
        #expect(rebuilt.durationMinutes == block.durationMinutes)
    }

    @Test("A date outside the plan's span still lands on a real day rather than nothing")
    func scheduleBlockFallsBack() {
        let stray = ScheduleBlockWire(title: "Somewhere", category: "food",
                                      startMinute: 1_200, durationMinutes: 60,
                                      dayDate: Date(timeIntervalSince1970: 0))
        #expect(ScheduleBlock(wire: stray).dayID == DemoPlan.days[0].id)
    }

    // MARK: - Ballot → the untouched poll brain

    @Test("A ballot plus wire votes rebuilds the exact poll the brain expects")
    func ballotBecomesPoll() {
        let deck = DemoPlan.decks[0]
        var slated = deck
        slated.shortlist = Array(deck.candidates.prefix(3)).map(\.id)

        guard let ballot = slated.ballot else {
            Issue.record("a deck with a shortlist must produce a ballot"); return
        }
        #expect(ballot.slotID == deck.slotID)
        #expect(ballot.options.count == 3)

        let first = ballot.options[0].optionID
        let votes = [
            VoteWire(participant: ParticipantID("pA"), slot: ballot.slotID, option: first),
            VoteWire(participant: ParticipantID("pB"), slot: ballot.slotID, option: first),
            // A vote in another slot must not leak into this poll.
            VoteWire(participant: ParticipantID("pC"), slot: "elsewhere", option: first)
        ]

        let poll = ballot.poll(votes: votes, size: 2, tieBreak: nil)
        #expect(poll.votes.count == 2)
        #expect(PollTally.resolution(poll) == .decided(first))
    }

    @Test("A deck the host kept nothing from contributes no ballot")
    func emptyDeckHasNoBallot() {
        #expect(DemoPlan.decks[0].ballot == nil)
        #expect(DemoPlan.decks.ballot.isEmpty)
    }

    @Test("Three devices given the same votes reach the same winner")
    func tallyIsDeviceIndependent() {
        // The claim the whole architecture rests on: the relay never sends a winner, so the only thing keeping three screens in agreement is that `PollTally` is a pure function of the votes.
        let deck = DemoPlan.decks[0]
        var slated = deck
        slated.shortlist = Array(deck.candidates.prefix(3)).map(\.id)
        guard let ballot = slated.ballot else {
            Issue.record("expected a ballot"); return
        }

        let options = ballot.options.map(\.optionID)
        let votes = [
            VoteWire(participant: ParticipantID("pA"), slot: ballot.slotID, option: options[0]),
            VoteWire(participant: ParticipantID("pB"), slot: ballot.slotID, option: options[1]),
            VoteWire(participant: ParticipantID("pC"), slot: ballot.slotID, option: options[2])
        ]

        // A three-way tie resolves to the same sorted leaders regardless of the order the votes arrived in on each device.
        let inOrder = ballot.poll(votes: votes, size: 3, tieBreak: nil)
        let reversed = ballot.poll(votes: votes.reversed(), size: 3, tieBreak: nil)
        let shuffled = ballot.poll(votes: [votes[1], votes[2], votes[0]], size: 3, tieBreak: nil)

        #expect(PollTally.resolution(inOrder) == PollTally.resolution(reversed))
        #expect(PollTally.resolution(inOrder) == PollTally.resolution(shuffled))
        #expect(PollTally.resolution(inOrder) == .tie(options.sorted()))

        // And the leader's tie-break settles it identically everywhere.
        let broken = ballot.poll(votes: votes, size: 3, tieBreak: options[1])
        #expect(PollTally.resolution(broken) == .decided(options[1]))
    }
}
