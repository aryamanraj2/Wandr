// SquadWire.swift Wandr The vocabulary the three devices and the relay share, and nothing else. One file, `nonisolated` throughout, `Codable`, `Sendable`, no UI and no `Network` import — it is symlinked verbatim into `Tools/WandrRelay` so there is exactly one definition of the protocol rather than two that drift.
//
// The one rule that governs every type here: **never put a runtime `UUID` on the wire.** `Candidate.id`, `Deck.id` and `PlanDay.id` are all `let id = UUID()`, minted fresh in each process, so they can never match across devices. Everything cross-device keys off `PollOptionID(slugging:)` and `slotID` — which is exactly why `PollOptionID` was built as a deterministic name slug in the first place (see SquadPoll.swift). `ScheduleBlockWire` carries a *date* rather than a `PlanDay.ID` for the same reason: the receiving device rebuilds its own day identity from the calendar.

import Foundation

// MARK: - Room identity

/// The six digits a host reads out and the squad types in. The relay mints it; clients only ever echo it back.
nonisolated struct RoomCode: Codable, Sendable, Hashable, CustomStringConvertible {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Accepts only what the join pad is allowed to produce: exactly six digits.
    init?(entering text: String) {
        let digits = text.filter(\.isNumber)
        guard digits.count == Self.length, digits.count == text.count else { return nil }
        self.rawValue = digits
    }

    static let length = 6

    /// A fresh code. The relay rejects collisions and rolls again, so uniqueness is its business, not this initializer's.
    static func random() -> RoomCode {
        RoomCode(String(format: "%06d", Int.random(in: 0..<1_000_000)))
    }

    var description: String { rawValue }

    /// "428 301" — read aloud in two halves, which is how someone actually dictates it across a table.
    var spoken: String {
        guard rawValue.count == Self.length else { return rawValue }
        let mid = rawValue.index(rawValue.startIndex, offsetBy: 3)
        return "\(rawValue[..<mid]) \(rawValue[mid...])"
    }

    init(from decoder: any Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Where the room is in the night. The relay stores it and rebroadcasts it; only the leader may change it.
nonisolated enum RoomPhase: String, Codable, Sendable, Equatable {
    /// Gathering people around the code. No ballot is shown yet.
    case lobby
    /// The slate is live and votes are landing.
    case voting
    /// Every slot has a winner; the leader is arranging the timeline.
    case adjusting
    /// The leader published. Everyone sees the same itinerary.
    case published
}

// MARK: - Identity conformances
//
// `PollOptionID` and `ParticipantID` live in SquadPoll.swift — the pure poll brain, which this design deliberately does not modify. Their `Codable` conformances belong here instead, written by hand because Swift only synthesizes `Codable` in the type's own file. Encoding them as bare strings keeps the wire readable in the relay's log.

nonisolated extension PollOptionID: Codable {
    init(from decoder: any Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

nonisolated extension ParticipantID: Codable {
    init(from decoder: any Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Ballot

/// One shortlisted place, flattened for the wire. Every field the vote card renders travels, because the joiners never ran curation and have no other source for any of it — they know a venue only by what arrives here.
nonisolated struct CandidateWire: Codable, Sendable, Hashable, Identifiable {
    /// The cross-device identity: `PollOptionID(slugging: name)`. Not a `UUID`.
    let optionID: PollOptionID

    let name: String
    let area: String
    let tagline: String
    /// `StopCategory.rawValue`. Kept raw so this file never imports the app's UI models.
    let category: String

    let perHead: Int
    let listPrice: Int?
    let offer: String?
    let offerWindow: String?

    let openWindow: String
    let travelNote: String
    let imageSeed: Int

    let rationale: String?
    let costUnknown: Bool
    let warnings: [String]

    let story: String?
    let highlights: [String]
    let insiderTip: String?

    var id: PollOptionID { optionID }
}

/// One slot's ballot: what is being voted on and what the slot is called.
nonisolated struct SlotBallotWire: Codable, Sendable, Hashable, Identifiable {
    /// Matches `Deck.slotID` — stable across devices, and distinct from category because a plan can hold both lunch and dinner.
    let slotID: String
    let slotName: String
    /// Display only, e.g. "8:00 – 10:00 pm".
    let window: String
    let options: [CandidateWire]

    var id: String { slotID }
}

// MARK: - Votes and people

/// One person's current choice in one slot. The relay upserts on `(participant, slot)`, which is the wire-level expression of `SquadSlotPoll.cast`'s re-vote-overwrites rule.
nonisolated struct VoteWire: Codable, Sendable, Hashable {
    let participant: ParticipantID
    let slot: String
    let option: PollOptionID
}

/// Someone in the room. `isLeader` is set by the relay for whoever hosted, so no client can claim it.
nonisolated struct ParticipantWire: Codable, Sendable, Hashable, Identifiable {
    let id: ParticipantID
    let name: String
    let isLeader: Bool
}

// MARK: - Itinerary

/// A published schedule block. Carries a *date* rather than `ScheduleBlock.dayID`, because that id is a per-process `UUID`; the receiving device matches the date back to its own `PlanDay`.
nonisolated struct ScheduleBlockWire: Codable, Sendable, Hashable {
    let title: String
    /// `StopCategory.rawValue`.
    let category: String
    let startMinute: Int
    let durationMinutes: Int
    let dayDate: Date
    /// Optional on purpose. A non-optional addition would make every snapshot published by
    /// a newer host fail to decode on a peer still running the previous build — the join
    /// would break, not the picture. Missing decodes to `nil` and reads as "no photograph".
    let imageSeed: Int?

    /// Spelled out rather than left to the memberwise default so `imageSeed` can carry one.
    /// It cannot be given an inline initialiser instead: a stored property that arrives
    /// already initialised is dropped from the synthesised decoder, which would silently
    /// stop the seed crossing the wire at all.
    init(
        title: String,
        category: String,
        startMinute: Int,
        durationMinutes: Int,
        dayDate: Date,
        imageSeed: Int? = nil
    ) {
        self.title = title
        self.category = category
        self.startMinute = startMinute
        self.durationMinutes = durationMinutes
        self.dayDate = dayDate
        self.imageSeed = imageSeed
    }
}

// MARK: - Snapshot

/// The whole room, every time. The relay never sends deltas: any mutation rebroadcasts this, and `version` increases by one each time. That is what makes reconnects, relaunches and out-of-order taps fall out for free — a client that missed a message is corrected by the next one.
nonisolated struct RoomSnapshot: Codable, Sendable, Equatable {
    let version: Int
    let code: RoomCode
    let phase: RoomPhase
    let participants: [ParticipantWire]
    let ballot: [SlotBallotWire]
    let votes: [VoteWire]
    /// Leader's pick for slots the squad tied on, keyed by `slotID`.
    let tieBreaks: [String: PollOptionID]
    /// Set once, on publish.
    let itinerary: [ScheduleBlockWire]?

    var leader: ParticipantWire? { participants.first(where: \.isLeader) }
}

// MARK: - Messages

/// Everything a device can say. Note there is no "cast this vote *as* someone" — the relay attributes every vote to the participant that connection joined as, so a client cannot vote on anyone else's behalf.
nonisolated enum ClientMessage: Codable, Sendable, Equatable {
    /// Open a room around this slate. The relay assigns the code and marks the sender leader.
    case host(ballot: [SlotBallotWire], name: String, participant: ParticipantID)
    /// Enter an existing room. Also the *reconnect* message — the leader re-sends `join` with its own code rather than `host`, so a dropped connection never mints a second room.
    case join(code: RoomCode, name: String, participant: ParticipantID)
    case vote(slot: String, option: PollOptionID)
    /// Leader-only: resolve a slot the squad tied on.
    case tieBreak(slot: String, option: PollOptionID)
    /// Leader-only: move the room forward (lobby → voting, voting → adjusting).
    case advance(to: RoomPhase)
    /// Leader-only: reveal the finished night to everyone.
    case publish(itinerary: [ScheduleBlockWire])
}

/// Why a message was refused. Anything here is a state the UI has to name out loud rather than hang on.
nonisolated enum RoomFailure: String, Codable, Sendable {
    /// The code was wrong, or the relay restarted and the room went with it.
    case noSuchRoom
    case roomFull
    /// A non-leader tried a leader-only action.
    case notLeader
}

nonisolated enum ServerMessage: Codable, Sendable, Equatable {
    /// Sent once per successful `host`/`join`, before the first snapshot, so the client learns the code it was assigned and confirms the identity it is voting under.
    case welcome(code: RoomCode, you: ParticipantID)
    case snapshot(RoomSnapshot)
    case failure(RoomFailure)
}

// MARK: - Framing

/// The one encoder/decoder pair both ends use. Dates go over as ISO-8601 so a relay written against a different Foundation still reads them.
nonisolated enum SquadWire {
    static let port: UInt16 = 8787

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func encode(_ value: some Encodable) -> Data? {
        try? encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? decoder.decode(type, from: data)
    }
}
