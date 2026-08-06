// SquadWire+Curation.swift Wandr The translation between the app's curation/schedule models and the wire. It lives beside the wire types rather than inside CurationModels.swift so the UI models stay unaware that a network exists, and so SquadWire.swift itself can be symlinked into the relay without dragging `Candidate` along with it.

import Foundation

// MARK: - Candidate

extension Candidate {

    /// This candidate as the squad will see it. `optionID` is the slug — the same value `PollSession` already uses as the poll's option identity, which is what makes a vote cast on one device resolvable on another.
    var wire: CandidateWire {
        CandidateWire(
            optionID: PollOptionID(slugging: name),
            name: name,
            area: area,
            tagline: tagline,
            category: category.rawValue,
            perHead: perHead,
            listPrice: listPrice,
            offer: offer,
            offerWindow: offerWindow,
            openWindow: openWindow,
            travelNote: travelNote,
            imageSeed: imageSeed,
            rationale: rationale,
            costUnknown: costUnknown,
            warnings: warnings,
            story: story,
            highlights: highlights,
            insiderTip: insiderTip
        )
    }

    /// Rebuilds a candidate on a device that never ran curation. `id` is minted locally and deliberately not carried over — it is a per-process `UUID` and means nothing to anyone else.
    init(wire: CandidateWire) {
        self.init(
            name: wire.name,
            area: wire.area,
            tagline: wire.tagline,
            category: StopCategory(rawValue: wire.category) ?? .discover,
            perHead: wire.perHead,
            listPrice: wire.listPrice,
            offer: wire.offer,
            offerWindow: wire.offerWindow,
            openWindow: wire.openWindow,
            travelNote: wire.travelNote,
            imageSeed: wire.imageSeed,
            rationale: wire.rationale,
            costUnknown: wire.costUnknown,
            warnings: wire.warnings,
            story: wire.story,
            highlights: wire.highlights,
            insiderTip: wire.insiderTip
        )
    }
}

// MARK: - Deck

extension Deck {

    /// The slate this deck contributes to the squad's ballot — the host's shortlist, in the order they swiped it. `nil` when the host kept nothing here: a slot with no slate is not a poll.
    var ballot: SlotBallotWire? {
        let options = shortlisted.map(\.wire)
        guard !options.isEmpty else { return nil }
        return SlotBallotWire(
            slotID: slotID,
            slotName: slotName,
            window: window,
            options: options
        )
    }
}

extension Array where Element == Deck {
    /// Every slated slot, in curation order.
    var ballot: [SlotBallotWire] { compactMap(\.ballot) }
}

// MARK: - Ballot → poll brain

extension SlotBallotWire {

    /// This slot as the pure poll brain wants it: options plus whoever has voted so far. `size` is the quorum — the number of people actually in the room — and `lockedWinner` is only ever the leader's tie-break, because a plurality winner is something `PollTally` derives rather than something anyone records.
    func poll(votes: [VoteWire], size: Int, tieBreak: PollOptionID?) -> SquadSlotPoll {
        let mine = votes.filter { $0.slot == slotID }
        let cast = Dictionary(mine.map { ($0.participant, $0.option) }, uniquingKeysWith: { _, latest in latest })

        return SquadSlotPoll(
            slotID: slotID,
            slotName: slotName,
            options: options.map {
                PollOption(
                    id: $0.optionID,
                    label: $0.name,
                    subtitle: "\($0.area) · ₹\($0.perHead)"
                )
            },
            size: size,
            votes: cast,
            lockedWinner: tieBreak
        )
    }

    func candidate(_ option: PollOptionID) -> CandidateWire? {
        options.first { $0.optionID == option }
    }
}

// MARK: - Schedule

extension ScheduleBlock {

    /// This block as published. The day travels as its calendar date; `dayID` does not travel at all.
    func wire(on days: [PlanDay] = DemoPlan.days) -> ScheduleBlockWire {
        ScheduleBlockWire(
            title: title,
            category: category.rawValue,
            startMinute: startMinute,
            durationMinutes: durationMinutes,
            dayDate: days.first { $0.id == dayID }?.date ?? Date()
        )
    }

    /// Rebuilds a published block against *this* device's days, matching on the calendar day. Both devices compute `DemoPlan.days` from their own clock, so the same evening resolves to the same pill on both — and a date outside that span falls back to the first day rather than rendering nothing.
    init(wire: ScheduleBlockWire, days: [PlanDay] = DemoPlan.days) {
        let calendar = Calendar.current
        let day = days.first { calendar.isDate($0.date, inSameDayAs: wire.dayDate) } ?? days[0]
        self.init(
            title: wire.title,
            category: StopCategory(rawValue: wire.category) ?? .discover,
            startMinute: wire.startMinute,
            durationMinutes: wire.durationMinutes,
            dayID: day.id
        )
    }
}

extension Array where Element == ScheduleBlock {
    var wire: [ScheduleBlockWire] { map { $0.wire() } }
}

extension Array where Element == ScheduleBlockWire {
    var blocks: [ScheduleBlock] { map { ScheduleBlock(wire: $0) } }
}
