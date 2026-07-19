//
//  CurationModels+Grounded.swift
//  Wandr
//
//  The bridge from the grounded planning result to the swipe UI.
//
//  `WandrPlan` (validated, ID-only) plus the `GroundedVenue` evidence snapshot plus
//  the `SlotSchedule` (for window labels) become the `[Deck]` of `[Candidate]` the
//  existing `CurationView` already knows how to render. This is "how to display it":
//  the model's ranked picks, resolved back to real venue facts, with its rationale
//  and the validator's caveats carried through — and nothing invented in between.
//
//  Deterministic and pure. Display facts (name, price, hours) come only from the
//  venue; `rationale` is the only model prose, and it is presented as such.
//

import Foundation

// MARK: - Category bridge

extension StopCategory {
    /// The UI category for a planning `SlotCategory`. Same four cases, same raw values.
    init(_ slot: SlotCategory) {
        switch slot {
        case .food:      self = .food
        case .sights:    self = .sights
        case .nightlife: self = .nightlife
        case .discover:  self = .discover
        }
    }
}

// MARK: - Candidate from evidence

extension Candidate {
    /// Resolves one curated pick against its grounded venue. `rationale` is the
    /// model's; `warnings` are the validator's; every other field is dataset fact.
    init(groundedVenue venue: GroundedVenue, rationale: String?, warnings: [String]) {
        self.init(
            name: venue.name,
            area: venue.area,
            tagline: venue.tagline,
            category: StopCategory(venue.category),
            perHead: venue.cost.knownPerHeadRupees ?? 0,
            listPrice: venue.cost.listPriceRupees,
            offer: venue.offer,
            offerWindow: venue.offerWindow,
            openWindow: venue.openWindow.label ?? "Hours not listed",
            // Travel time between stops is a deferred rule (no MapKit yet), so we
            // show nothing rather than a faked distance.
            travelNote: "",
            imageSeed: venue.imageSeed,
            rationale: rationale,
            costUnknown: venue.cost == .unknown,
            warnings: warnings
        )
    }
}

// MARK: - Plan → decks

/// Turns a validated plan into the swipe decks, plus the one-line window banner.
enum GroundedPlanMapper {

    struct Output {
        let decks: [Deck]
        /// Shown atop "Pick your stops" when the group's time window shaped the plan.
        /// `nil` for an open-ended plan (no banner).
        let banner: String?
        /// Per-category window [start...end] in minutes-from-midnight, so the schedule
        /// screen places the squad's winners inside the group's real window.
        let slotWindows: [StopCategory: ClosedRange<Int>]
    }

    static func map(plan: WandrPlan, evidence: [GroundedVenue]) -> Output {
        let byID = Dictionary(evidence.map { ($0.venueID, $0) }, uniquingKeysWith: { first, _ in first })
        let schedule = SlotSchedule.compute(for: plan.brief.timeWindow.value)

        var decks: [Deck] = []
        for slot in plan.slots {
            let candidates: [Candidate] = slot.candidates.compactMap { curated in
                guard let venue = byID[curated.venueID] else { return nil }
                return Candidate(
                    groundedVenue: venue,
                    rationale: curated.rationale,
                    warnings: plan.warnings(about: curated.venueID).map(\.message)
                )
            }
            guard !candidates.isEmpty else { continue }

            decks.append(
                Deck(
                    category: StopCategory(slot.category),
                    slotName: slot.title,
                    window: schedule.slot(for: slot.category)?.windowLabel ?? "",
                    candidates: candidates
                )
            )
        }

        var slotWindows: [StopCategory: ClosedRange<Int>] = [:]
        for feasible in schedule.slots {
            slotWindows[StopCategory(feasible.category)] = feasible.startMinute...feasible.endMinute
        }

        return Output(decks: decks, banner: banner(for: schedule), slotWindows: slotWindows)
    }

    /// A short line explaining a window-shaped plan. `nil` when the group set no window.
    static func banner(for schedule: SlotSchedule) -> String? {
        guard schedule.isWindowConstrained, let first = schedule.slots.first else { return nil }

        if schedule.slots.count == 1 {
            return "You're free \(first.windowLabel) — time for one stop."
        }
        let last = schedule.slots.last ?? first
        let span = "\(SlotSchedule.clock(first.startMinute))–\(SlotSchedule.clock(last.endMinute))"
        return "You're free \(span) — \(schedule.slots.count) stops fit your window."
    }
}
