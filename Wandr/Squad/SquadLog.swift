// SquadLog.swift Wandr One log stream for the whole live-poll feature, so a room that misbehaves can be read from the outside.
//
// During a demo the two things you need to tell apart are "the app never sent it" and "the relay never answered". The relay prints its own line per event; this is the other half. Stream it with:
//
//   xcrun simctl spawn <udid> log stream --level debug --predicate 'subsystem == "aryaman.Wandr"'
//
// Every line is prefixed so three simulators tailing at once stay legible.

import Foundation
import OSLog

nonisolated enum SquadLog {

    private static let logger = Logger(subsystem: "aryaman.Wandr", category: "squad")

    /// The socket layer: connects, retries, bytes in and out.
    static func net(_ message: String) {
        logger.debug("⇄ \(message, privacy: .public)")
    }

    /// The room layer: what this device asked for and what the relay said back.
    static func room(_ message: String) {
        logger.info("◆ \(message, privacy: .public)")
    }

    /// Something the UI has to explain to a human.
    static func problem(_ message: String) {
        logger.error("✗ \(message, privacy: .public)")
    }
}

// MARK: - Wire descriptions
// Short, honest one-liners. A ballot prints its shape rather than its contents, because a full slate would bury every other line in the stream.

extension ClientMessage {
    var summary: String {
        switch self {
        case .host(let ballot, let name, let participant):
            return "host(\(ballot.count) slots, \(name), \(participant.rawValue.prefix(8)))"
        case .join(let code, let name, let participant):
            return "join(\(code), \(name), \(participant.rawValue.prefix(8)))"
        case .vote(let slot, let option):
            return "vote(\(slot) ← \(option))"
        case .tieBreak(let slot, let option):
            return "tieBreak(\(slot) ← \(option))"
        case .advance(let phase):
            return "advance(\(phase.rawValue))"
        case .publish(let itinerary):
            return "publish(\(itinerary.count) stops)"
        }
    }
}

extension ServerMessage {
    var summary: String {
        switch self {
        case .welcome(let code, let you):
            return "welcome(\(code), you=\(you.rawValue.prefix(8)))"
        case .snapshot(let snapshot):
            return "snapshot(v\(snapshot.version) \(snapshot.phase.rawValue) "
                + "\(snapshot.participants.count)p \(snapshot.votes.count)v "
                + "\(snapshot.ballot.count)slots\(snapshot.itinerary.map { " \($0.count)stops" } ?? ""))"
        case .failure(let failure):
            return "failure(\(failure.rawValue))"
        }
    }
}
