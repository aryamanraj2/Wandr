//
//  PlanPresentation.swift
//  Wandr
//
//  The UI side of the bridge: a pure mapping from a validated `WandrPlan` to the
//  `Deck`/`Candidate` shapes the curation screen draws.
//
//  Foundation only — no SwiftUI, no view knowledge beyond the UI models. The
//  dependency points inward: this file knows `Domain/`, `Domain/` never learns
//  this file exists.
//
//  The mapper may only read `GroundedVenue` fields. It never infers a cost band
//  from a category, synthesizes a travel note, invents hours, or promotes
//  `rationale` into a factual claim. Unknown renders as absent, never as a
//  plausible number.
//

import Foundation

enum PlanPresentation {

    // MARK: - Category mapping

    /// `StopCategory` (UI) and `SlotCategory` (domain) are parallel enums with
    /// identical cases, kept separate on purpose — this mapping is the one place
    /// they meet, and it is total by exhaustiveness.
    static func stopCategory(_ category: SlotCategory) -> StopCategory {
        switch category {
        case .food:      return .food
        case .sights:    return .sights
        case .nightlife: return .nightlife
        case .discover:  return .discover
        }
    }

    static func slotCategory(_ category: StopCategory) -> SlotCategory {
        switch category {
        case .food:      return .food
        case .sights:    return .sights
        case .nightlife: return .nightlife
        case .discover:  return .discover
        }
    }

    // MARK: - Plan → decks

    /// Maps the validated plan into swipeable decks.
    ///
    /// - Slot order follows `plan.slots` verbatim; candidates are ordered by
    ///   `rank` ascending.
    /// - A `venueID` with no match in `plan.evidence` is dropped, not rendered as
    ///   a placeholder. (Unreachable in practice — the validator's Rule 1 rejects
    ///   invented IDs — but a half-drawn card is worse than an absent one.)
    /// - `Deck.window` comes from the schedule draft's block for the slot when
    ///   one exists, else stays empty. Never a hardcoded string.
    /// - Every plan warning reaches exactly one rendered surface: on the card for
    ///   a rendered venue, else on the deck header — so a dropped candidate can
    ///   never take its warnings down with it.
    static func decks(from plan: WandrPlan, schedule: ScheduleDraft? = nil) -> [Deck] {
        plan.slots.map { slot in
            let candidates = slot.candidates
                .sorted { $0.rank < $1.rank }
                .compactMap { curated -> Candidate? in
                    guard let venue = plan.venue(curated.venueID) else { return nil }
                    return candidate(for: venue, in: plan)
                }

            let renderedIDs = Set(candidates.compactMap(\.venueID))
            let deckWarnings = plan.warnings(for: slot.slotID)
                .filter { !renderedIDs.contains($0.venueID) }
                .map(\.message)

            return Deck(
                category: stopCategory(slot.category),
                slotName: slot.title,
                window: window(for: slot.slotID, in: schedule),
                candidates: candidates,
                warnings: deckWarnings
            )
        }
    }

    /// One card, every field read straight off the evidence. Unknown cost and
    /// unknown hours stay `nil`; `travelNote` is `nil` until MKDirections exists.
    private static func candidate(for venue: GroundedVenue, in plan: WandrPlan) -> Candidate {
        Candidate(
            venueID: venue.venueID,
            name: venue.name,
            area: venue.area,
            tagline: venue.tagline,
            category: stopCategory(venue.category),
            perHead: venue.cost.knownPerHeadRupees,
            listPrice: venue.cost.listPriceRupees,
            offer: venue.offer,
            offerWindow: venue.offerWindow,
            openWindow: venue.openWindow.label,
            travelNote: nil,
            imageSeed: venue.imageSeed,
            warnings: plan.warnings(about: venue.venueID).map(\.message)
        )
    }

    /// The deck window as drafted, e.g. "8:00 pm – 9:30 pm". Empty when the
    /// draft has no block for this slot — absent, never invented.
    static func window(for slotID: SlotID, in schedule: ScheduleDraft?) -> String {
        guard let block = schedule?.blocks.first(where: { $0.slotID == slotID }) else {
            return ""
        }
        return "\(ScheduleBlock.clock(block.startMinute)) – \(ScheduleBlock.clock(block.endMinute))"
    }
}
