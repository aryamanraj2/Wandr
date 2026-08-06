// SquadRoom.swift Wandr The live room, as the UI sees it. One shared instance for the process — the same shape as `IntakeInbox.shared`, and for the same reason: a connection is a process-wide thing, and the screens that show it come and go.
//
// The important thing this type does *not* do is decide anything. It holds the last snapshot the relay sent and rebuilds the pure `SquadSlotPoll`s from it, then hands them straight to the untouched `PollTally`. Because that tally is deterministic — tied leaders are already `sorted()` through `PollOptionID: Comparable` — three devices given the same votes always agree on the same winner without ever exchanging a winner. That is what lets SquadPoll.swift and PollTally.swift stay exactly as they were, and `PollTallyTests` stay green.
//
// Landmine: never build this inside a view's `init` via `State(initialValue:)`, the way `SquadPollView` used to build its `PollSession`. That initializer re-runs on every view re-instantiation, so a network-connected object built there would open a fresh socket on every render.

import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class SquadRoom {

    static let shared = SquadRoom()

    enum Role: Equatable {
        /// Not in a room. The app behaves exactly as it did before this feature existed.
        case none
        case leader
        case joiner
    }

    // MARK: - State

    /// The last thing the relay said. Everything on screen is derived from this and nothing else.
    private(set) var snapshot: RoomSnapshot?
    private(set) var connection: SquadConnection = .offline
    private(set) var role: Role = .none

    /// A refusal worth naming on screen. `noSuchRoom` after a successful join means the relay restarted and took the room with it — the one failure that must read as "this ended" rather than as a spinner that never stops.
    private(set) var failure: RoomFailure?

    /// This device's voter identity, minted once and kept. Persisted because a simulator rebuilt mid-demo would otherwise rejoin as a fourth person and quorum would never complete again — which is exactly the moment a hackathon demo dies.
    let me: ParticipantID

    /// What the squad sees this device called. Persisted so a rejoin does not rename anyone.
    var myName: String {
        didSet { UserDefaults.standard.set(myName, forKey: Self.nameKey) }
    }

    private let transport: SquadTransport
    private var pump: Task<Void, Never>?

    private static let identityKey = "squadParticipantID"
    private static let nameKey = "squadParticipantName"

    init(transport: SquadTransport = SquadTransport()) {
        self.transport = transport

        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: Self.identityKey) {
            self.me = ParticipantID(stored)
        } else {
            let minted = UUID().uuidString
            defaults.set(minted, forKey: Self.identityKey)
            self.me = ParticipantID(minted)
        }

        self.myName = defaults.string(forKey: Self.nameKey) ?? Self.deviceName
    }

    private static var deviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "This device"
        #endif
    }

    // MARK: - Derived

    var code: RoomCode? { snapshot?.code }
    var phase: RoomPhase { snapshot?.phase ?? .lobby }
    var participants: [ParticipantWire] { snapshot?.participants ?? [] }
    var isLeader: Bool { snapshot?.leader?.id == me }
    var leaderName: String { snapshot?.leader?.name ?? "the host" }

    /// Quorum is simply the number of people in the room — no stepper, no guess. Someone arriving mid-vote raises the bar for everyone, which is the honest reading of "once everyone's in".
    var quorum: Int { max(1, participants.count) }

    /// The ballot rebuilt as the pure poll brain wants it, in slate order.
    var polls: [SquadSlotPoll] {
        guard let snapshot else { return [] }
        return snapshot.ballot.map {
            $0.poll(
                votes: snapshot.votes,
                size: quorum,
                tieBreak: snapshot.tieBreaks[$0.slotID]
            )
        }
    }

    func resolution(for poll: SquadSlotPoll) -> PollResolution { PollTally.resolution(poll) }
    func counts(for poll: SquadSlotPoll) -> [PollOptionID: Int] { PollTally.counts(poll) }

    /// What this device chose in a slot, so its own row can read as chosen rather than merely counted.
    func myVote(in slot: String) -> PollOptionID? {
        snapshot?.votes.first { $0.participant == me && $0.slot == slot }?.option
    }

    func voted(in slot: String) -> Int {
        Set((snapshot?.votes ?? []).filter { $0.slot == slot }.map(\.participant)).count
    }

    /// Every slot has a single winner — the night is decided and the room can move on by itself.
    var allDecided: Bool {
        let polls = polls
        guard !polls.isEmpty else { return false }
        return polls.allSatisfy {
            if case .decided = PollTally.resolution($0) { return true }
            return false
        }
    }

    /// The winning place per decided slot, in slate order — the input to the schedule. Candidates are rebuilt from the wire, so this works identically on a device that never ran curation.
    func winners() -> [(slotID: String, candidate: Candidate)] {
        guard let snapshot else { return [] }
        return snapshot.ballot.compactMap { ballot in
            let poll = ballot.poll(
                votes: snapshot.votes,
                size: quorum,
                tieBreak: snapshot.tieBreaks[ballot.slotID]
            )
            guard case .decided(let winner) = PollTally.resolution(poll),
                  let candidate = ballot.candidate(winner)
            else { return nil }
            return (ballot.slotID, Candidate(wire: candidate))
        }
    }

    /// The published night, rebuilt against this device's own calendar days.
    var itinerary: [ScheduleBlock] {
        (snapshot?.itinerary ?? []).blocks
    }

    // MARK: - Opening a room

    /// The host's slate becomes the squad's ballot. The relay assigns the code.
    func host(decks: [Deck]) {
        let ballot = decks.ballot
        guard !ballot.isEmpty else { return }
        begin(role: .leader, identity: .host(ballot: ballot, name: myName, participant: me))
    }

    /// Enter someone else's room.
    func join(code: RoomCode, name: String) {
        myName = name
        begin(role: .joiner, identity: .join(code: code, name: name, participant: me))
    }

    private func begin(role: Role, identity: ClientMessage) {
        self.role = role
        self.snapshot = nil
        self.failure = nil
        SquadLog.room("as \(role) — \(identity.summary), me=\(me.rawValue.prefix(8))")
        listen()
        transport.connect(as: identity)
    }

    /// Leaves for good. The app falls back to exactly the behaviour it had before a room existed.
    func leave() {
        transport.disconnect()
        role = .none
        snapshot = nil
        failure = nil
        connection = .offline
    }

    // MARK: - Actions
    // Every one of these is fire-and-forget. The server is authoritative and the snapshot that comes back is the truth; a tap only ever *asks*.

    func vote(_ option: PollOptionID, in slot: String) {
        // Paint this device's own row immediately. The next snapshot overwrites it either way, so an optimistic row that turns out wrong is corrected within a frame or two rather than being a state anyone can get stuck in.
        apply(VoteWire(participant: me, slot: slot, option: option))
        transport.send(.vote(slot: slot, option: option))
    }

    func breakTie(_ option: PollOptionID, in slot: String) {
        guard isLeader else { return }
        transport.send(.tieBreak(slot: slot, option: option))
    }

    func startVoting() {
        advance(to: .voting)
    }

    func publish(_ blocks: [ScheduleBlock]) {
        guard isLeader else { return }
        transport.send(.publish(itinerary: blocks.wire))
    }

    private func advance(to phase: RoomPhase) {
        guard isLeader, self.phase != phase else { return }
        transport.send(.advance(to: phase))
    }

    // MARK: - The pump

    private func listen() {
        guard pump == nil else { return }
        pump = Task { [weak self] in
            guard let self else { return }
            for await event in transport.events {
                receive(event)
            }
        }
    }

    /// A plain synchronous assignment per event. Deliberately *not* wrapped in `withAnimation` — these arrive inside an async continuation rather than from a user event, where a transaction is unreliable. Motion is driven from the value instead, with `.animation(_:value: snapshot.version)` at the views, which is the pattern the rest of the app already uses.
    private func receive(_ event: SquadTransport.Event) {
        switch event {
        case .connection(let state):
            connection = state

        case .message(.welcome(let code, _)):
            // From here on a reconnect must *rejoin* rather than re-host: hosting again would mint a second room and strand the squad in the first.
            transport.rememberIdentity(.join(code: code, name: myName, participant: me))

        case .message(.snapshot(let snapshot)):
            self.snapshot = snapshot
            self.failure = nil
            // The single most useful line in the stream: what this device now believes, and what it derived from it. If two phones disagree on screen, they disagree here first.
            SquadLog.room("v\(snapshot.version) \(snapshot.phase.rawValue) · \(participants.count)p · "
                + "decided \(polls.filter { if case .decided = PollTally.resolution($0) { return true }; return false }.count)/\(polls.count)"
                + (isLeader ? " · leading" : ""))
            advanceIfSettled()

        case .message(.failure(let failure)):
            self.failure = failure
            SquadLog.problem("relay refused: \(failure.rawValue)")
            if failure != .notLeader {
                // Nothing to reconnect to. Stop trying, so the screen can say so instead of spinning.
                transport.disconnect()
                connection = .offline
            }
        }
    }

    /// No "lock the night" tap: the moment the last slot has a winner, the leader moves the room on and everyone follows.
    private func advanceIfSettled() {
        guard isLeader, phase == .voting, allDecided else { return }
        advance(to: .adjusting)
    }

    /// Upserts a vote into the held snapshot, matching the relay's own `(participant, slot)` rule.
    private func apply(_ vote: VoteWire) {
        guard let current = snapshot else { return }
        var votes = current.votes
        votes.removeAll { $0.participant == vote.participant && $0.slot == vote.slot }
        votes.append(vote)

        snapshot = RoomSnapshot(
            version: current.version,
            code: current.code,
            phase: current.phase,
            participants: current.participants,
            ballot: current.ballot,
            votes: votes,
            tieBreaks: current.tieBreaks,
            itinerary: current.itinerary
        )
    }
}
