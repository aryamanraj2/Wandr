// RoomStore.swift WandrRelay Every room the relay is holding, behind one serial queue. That serialization is the entire concurrency story: nothing here is an actor, nothing is locked twice, and every mutation happens in a single ordered stream — which is also what makes the version counter meaningful.
//
// The relay knows nothing about Wandr. It does not tally votes, does not know what a plurality is, and never decides a winner. It holds an opaque ballot, an upserted vote list and a phase, and rebroadcasts the whole room on every change. All three devices then feed that same snapshot into the app's `PollTally`, which is pure and deterministic, so they cannot disagree. That is what lets the poll brain stay untouched.

import Foundation
import Network

final class RoomStore {

    /// Six voters plus a little headroom. A poll bigger than this is a different product.
    private static let capacity = 8

    private let queue = DispatchQueue(label: "wandr.relay.rooms")
    private var rooms: [String: Room] = [:]

    /// Every live socket, whether or not it has joined a room yet. This is the peer's *only* owner — the receive loop captures itself weakly, so a connection that nothing here retains is torn down the instant the accept handler returns, and its messages are never read.
    private var connected: [ObjectIdentifier: Peer] = [:]

    // MARK: - Entry points
    // All three hop onto the serial queue immediately. Callers are `Peer` handlers running on the listener's queue, so nothing below this line is ever re-entered concurrently.

    func accept(_ peer: Peer) {
        queue.async { self.connected[ObjectIdentifier(peer)] = peer }
    }

    func handle(_ message: ClientMessage, from peer: Peer) {
        queue.async { self.apply(message, from: peer) }
    }

    func disconnect(_ peer: Peer) {
        queue.async {
            self.connected[ObjectIdentifier(peer)] = nil

            guard let code = peer.code?.rawValue,
                  let participant = peer.participant,
                  var room = self.rooms[code],
                  room.peers[participant] === peer
            else { return }

            // The person stays in the room; only their socket leaves. Their vote stands, and a relaunched simulator rejoining with the same persisted `ParticipantID` simply reclaims the slot — which is the behaviour that keeps a mid-demo rebuild from stalling quorum forever.
            room.peers[participant] = nil
            self.rooms[code] = room
            Log.event(room.code, "left", peer.name, room.summary)
        }
    }

    // MARK: - Rules

    private func apply(_ message: ClientMessage, from peer: Peer) {
        switch message {
        case .host(let ballot, let name, let participant):
            host(ballot: ballot, name: name, participant: participant, peer: peer)

        case .join(let code, let name, let participant):
            join(code: code, name: name, participant: participant, peer: peer)

        case .vote(let slot, let option):
            vote(slot: slot, option: option, peer: peer)

        case .tieBreak(let slot, let option):
            mutateAsLeader(peer, "tie") { room in
                guard room.ballot.first(where: { $0.slotID == slot })?
                    .options.contains(where: { $0.optionID == option }) == true else { return nil }
                room.tieBreaks[slot] = option
                return "\(option) ← \(peer.name)"
            }

        case .advance(let phase):
            mutateAsLeader(peer, "phase") { room in
                guard phase != room.phase else { return nil }
                room.phase = phase
                return phase.rawValue
            }

        case .publish(let itinerary):
            mutateAsLeader(peer, "publish") { room in
                room.itinerary = itinerary
                room.phase = .published
                return "\(itinerary.count) stops"
            }
        }
    }

    private func host(ballot: [SlotBallotWire], name: String, participant: ParticipantID, peer: Peer) {
        let code = freshCode()
        var room = Room(code: code)
        room.ballot = ballot
        room.participants = [ParticipantWire(id: participant, name: name, isLeader: true)]

        attach(peer, to: &room, as: participant, name: name)
        rooms[code.rawValue] = room

        Log.event(code, "host", "\(name) · \(ballot.count) slots", room.summary)
        peer.send(.welcome(code: code, you: participant))
        broadcast(code)
    }

    private func join(code: RoomCode, name: String, participant: ParticipantID, peer: Peer) {
        guard var room = rooms[code.rawValue] else {
            Log.event(code, "join", "\(name) — no such room", "")
            peer.send(.failure(.noSuchRoom))
            return
        }

        if let index = room.participants.firstIndex(where: { $0.id == participant }) {
            // A rejoin, not a new person: same device coming back after a relaunch, a backgrounding, or a relay hiccup. Everything they already did is still in the room.
            room.participants[index] = ParticipantWire(
                id: participant,
                name: name,
                isLeader: room.participants[index].isLeader
            )
        } else if room.participants.count >= Self.capacity {
            peer.send(.failure(.roomFull))
            return
        } else {
            room.participants.append(ParticipantWire(id: participant, name: name, isLeader: false))
        }

        attach(peer, to: &room, as: participant, name: name)
        rooms[code.rawValue] = room

        Log.event(code, "join", name, room.summary)
        peer.send(.welcome(code: code, you: participant))
        broadcast(code)
    }

    private func vote(slot: String, option: PollOptionID, peer: Peer) {
        guard let code = peer.code?.rawValue,
              let participant = peer.participant,
              var room = rooms[code]
        else { return }

        // A vote for something that isn't on the ballot is a bug on the client, not a state the room should carry.
        guard room.ballot.first(where: { $0.slotID == slot })?
            .options.contains(where: { $0.optionID == option }) == true else { return }

        // Upsert on (participant, slot) — the wire-level form of the re-vote-overwrites rule `SquadSlotPoll.cast` already has, and the reason tapping a second option moves the count instead of doubling it.
        room.votes.removeAll { $0.participant == participant && $0.slot == slot }
        room.votes.append(VoteWire(participant: participant, slot: slot, option: option))
        rooms[code] = room

        let voted = room.votes.filter { $0.slot == slot }.count
        Log.event(room.code, "vote", "\(option) ← \(peer.name)", "(\(voted)/\(room.participants.count) \(slot))")
        broadcast(room.code)
    }

    /// The shape every leader-only action shares: verify the sender leads this room, let the body mutate it, and rebroadcast if anything actually changed. Returning `nil` from the body means "no change" and skips the version bump.
    private func mutateAsLeader(_ peer: Peer, _ label: String, _ body: (inout Room) -> String?) {
        guard let code = peer.code?.rawValue,
              let participant = peer.participant,
              var room = rooms[code]
        else { return }

        guard room.participants.first(where: { $0.id == participant })?.isLeader == true else {
            peer.send(.failure(.notLeader))
            return
        }

        guard let detail = body(&room) else { return }
        rooms[code] = room
        Log.event(room.code, label, detail, room.summary)
        broadcast(room.code)
    }

    // MARK: - Plumbing

    private func attach(_ peer: Peer, to room: inout Room, as participant: ParticipantID, name: String) {
        // A second connection for the same participant replaces the first rather than joining alongside it, so a device that relaunched does not leave a ghost receiving snapshots.
        room.peers[participant]?.connection.cancel()
        room.peers[participant] = peer
        peer.code = room.code
        peer.participant = participant
        peer.name = name
    }

    /// Every mutation ends here: bump the version once, build the snapshot once, send the same bytes to everyone. No deltas — a client that missed a message is corrected by the next one it receives.
    private func broadcast(_ code: RoomCode) {
        guard var room = rooms[code.rawValue] else { return }
        room.version += 1
        rooms[code.rawValue] = room

        let message = ServerMessage.snapshot(room.snapshot)
        for peer in room.peers.values { peer.send(message) }
    }

    private func freshCode() -> RoomCode {
        var code = RoomCode.random()
        while rooms[code.rawValue] != nil { code = RoomCode.random() }
        return code
    }
}

// MARK: - Room

struct Room {
    let code: RoomCode
    var phase: RoomPhase = .lobby
    var participants: [ParticipantWire] = []
    var ballot: [SlotBallotWire] = []
    var votes: [VoteWire] = []
    var tieBreaks: [String: PollOptionID] = [:]
    var itinerary: [ScheduleBlockWire]?
    var version = 0

    /// Live sockets, keyed by participant so a reconnect replaces rather than duplicates. Not part of the snapshot.
    var peers: [ParticipantID: Peer] = [:]

    var snapshot: RoomSnapshot {
        RoomSnapshot(
            version: version,
            code: code,
            phase: phase,
            participants: participants,
            ballot: ballot,
            votes: votes,
            tieBreaks: tieBreaks,
            itinerary: itinerary
        )
    }

    var summary: String {
        "\(participants.count)p · \(votes.count)v · \(phase.rawValue)"
    }
}

// MARK: - Log

/// One readable line per event, because during a demo this terminal is the ground truth for whether the room or the app is the thing that's stuck.
enum Log {
    static func event(_ code: RoomCode, _ verb: String, _ detail: String, _ summary: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        print("▸ \(code)  \(verb.padded(8))\(detail.padded(34))\(summary)   \(stamp)")
    }

    static func line(_ text: String) {
        print(text)
    }
}

private extension String {
    func padded(_ width: Int) -> String {
        count >= width ? self + " " : self + String(repeating: " ", count: width - count)
    }
}
