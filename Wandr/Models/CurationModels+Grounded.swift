// CurationModels+Grounded.swift Wandr The bridge from the grounded planning result to the swipe UI. `WandrPlan` (validated, ID-only) plus the `GroundedVenue` evidence snapshot plus the `SlotSchedule` (for window labels) become the `[Deck]` of `[Candidate]` the existing `CurationView` already knows how to render. This is "how to display it": the model's ranked picks, resolved back to real venue facts, with its rationale and the validator's caveats carried through — and nothing invented in between. Deterministic and pure. Display facts (name, price, hours) come only from the venue; `rationale` is the only model prose, and it is presented as such.

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
    /// Resolves one curated pick against its grounded venue. `rationale` is the model's; `warnings` are the validator's; every other field is dataset fact.
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
            // Travel time between stops is a deferred rule (no MapKit yet), so we show nothing rather than a faked distance.
            travelNote: "",
            imageSeed: venue.imageSeed,
            rationale: rationale,
            costUnknown: venue.cost == .unknown,
            warnings: warnings,
            vibeTags: venue.vibeTags,
            setting: StopSetting(rawValue: venue.setting.rawValue),
            dietary: venue.dietaryTags.displayNames,
            access: venue.accessibilityTags.displayNames
        )
    }
}

// MARK: - Evidence tags → display

private extension EvidenceTags where Tag: RawRepresentable, Tag.RawValue == String {
    /// The surveyed tags as the expanded card shows them, or `nil` when the provider never surveyed
    /// this venue at all. The three-state distinction survives the trip to the UI: `nil` renders as
    /// "not verified", an empty array renders as "none listed", and the card never turns the first
    /// into the second.
    var displayNames: [String]? {
        switch self {
        case .unknown:      return nil
        case .known(let set): return set.sorted().map(\.displayName)
        }
    }
}

private extension RawRepresentable where RawValue == String {
    /// `stepFreeEntry` → "Step-free entry". Derived from the case name rather than hand-listed, so a
    /// requirement added to either enum arrives on the card already readable instead of silently
    /// rendering as camel case.
    var displayName: String {
        var words = ""
        for character in rawValue {
            if character.isUppercase && !words.isEmpty { words.append(" ") }
            words.append(character)
        }
        // "gluten Free" → "gluten-free": a compound requirement reads as one word with a hyphen, not
        // as two.
        let spaced = words.replacingOccurrences(of: " Free", with: "-free")
            .replacingOccurrences(of: " free", with: "-free")
        return spaced.prefix(1).uppercased() + spaced.dropFirst().lowercased()
    }
}

// MARK: - Plan → decks

/// Turns a validated plan into the swipe decks, plus the one-line window banner.
enum GroundedPlanMapper {

    struct Output {
        let decks: [Deck]
        /// Shown atop "Pick your stops" when the group's time window shaped the plan. `nil` for an open-ended plan (no banner).
        let banner: String?
        /// Per-*slot* window [start...end] in minutes-from-midnight, keyed by `Deck.slotID`, so the schedule screen places the squad's winners inside the group's real window. Keyed by slot rather than category because a plan can hold both lunch and dinner, and those are not the same hour.
        let slotWindows: [String: ClosedRange<Int>]
    }

    static func map(plan: WandrPlan, evidence: [GroundedVenue]) -> Output {
        let byID = Dictionary(evidence.map { ($0.venueID, $0) }, uniquingKeysWith: { first, _ in first })
        let schedule = plan.brief.schedule

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
                    slotID: slot.slotID.rawValue,
                    category: StopCategory(slot.category),
                    slotName: slot.title,
                    window: schedule.slot(band: slot.band)?.windowLabel ?? "",
                    candidates: candidates
                )
            )
        }

        var slotWindows: [String: ClosedRange<Int>] = [:]
        for feasible in schedule.slots {
            slotWindows[feasible.band.rawValue] = feasible.startMinute...feasible.endMinute
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
