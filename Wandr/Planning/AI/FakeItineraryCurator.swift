//
//  FakeItineraryCurator.swift
//  Wandr
//
//  TEMPORARY. Stands in for Step 4's Foundation Models curator.
//
//  The one rule this fake must obey even though it is a fake: **it may only emit
//  `VenueID`s drawn from the evidence it was handed.** That is also
//  `FeasibilityValidator`'s Rule 1, and a fake that broke it would make Step 2's
//  own tests unable to tell a broken coordinator from a broken curator.
//
//  The `Misbehavior` knob below is the single, explicit exception: it exists so the
//  coordinator's validation-failure branch is reachable in tests. It defaults to
//  `.none` and nothing in the app ever sets it.
//

import Foundation

/// A deterministic, model-free `ItineraryCurating` stand-in.
///
/// Ranking is "whatever order the provider handed me", which is already
/// cheapest-first with a stable tiebreak — so curation adds no judgement of its
/// own. Judgement is Step 4's problem.
nonisolated struct FakeItineraryCurator: ItineraryCurating, Sendable {

    /// Ways to make the curator misbehave on purpose, so the validator's teeth are
    /// provable through the coordinator. **Test-only.**
    nonisolated enum Misbehavior: Sendable, Equatable {
        case none
        /// Emit a `VenueID` that is not in the evidence snapshot.
        case inventVenue
        /// Emit the same venue twice inside one deck.
        case duplicateWithinSlot
        /// Emit the same venue in two different decks.
        case duplicateAcrossSlots
        /// Deliberately under-pick, so a deep snapshot still yields a thin deck.
        case underPick
        /// Return nothing at all.
        case returnNothing
    }

    /// How many candidates a deck gets, when there are enough to give.
    let maxCandidatesPerSlot: Int
    let misbehavior: Misbehavior
    /// Set to make the fake throw instead of curating.
    let failure: PlanningFailure?

    init(
        maxCandidatesPerSlot: Int = 5,
        misbehavior: Misbehavior = .none,
        failure: PlanningFailure? = nil
    ) {
        self.maxCandidatesPerSlot = maxCandidatesPerSlot
        self.misbehavior = misbehavior
        self.failure = failure
    }

    // MARK: - Curation

    func curate(brief: OutingBrief, evidence: [GroundedVenue]) async throws -> [CurationSlot] {
        if let failure { throw failure }
        if misbehavior == .returnNothing { return [] }

        // Venues the evidence *proves* incompatible with a hard constraint are
        // dropped. Venues that were merely never surveyed are kept — the validator
        // turns those into warnings, and dropping them here would hide the gap.
        let eligible = evidence.filter { isEligible($0, for: brief) }

        var slots: [CurationSlot] = []

        for category in SlotCategory.allCases {
            let inCategory = eligible.filter { $0.category == category }
            guard !inCategory.isEmpty else { continue }

            var picks = Array(inCategory.prefix(maxCandidatesPerSlot))

            if misbehavior == .underPick {
                picks = Array(picks.prefix(1))
            }

            var venueIDs = picks.map(\.venueID)

            switch misbehavior {
            case .inventVenue:
                venueIDs.append(VenueID("invented-venue-not-in-evidence"))
            case .duplicateWithinSlot:
                if let first = venueIDs.first { venueIDs.append(first) }
            case .duplicateAcrossSlots:
                // Force every deck to include the same venue.
                if let shared = eligible.first?.venueID, !venueIDs.contains(shared) {
                    venueIDs.append(shared)
                }
            case .none, .underPick, .returnNothing:
                break
            }

            slots.append(
                CurationSlot(
                    slotID: SlotID(category.rawValue),
                    category: category,
                    title: Self.title(for: category),
                    candidates: venueIDs.enumerated().map { index, venueID in
                        CuratedCandidate(
                            venueID: venueID,
                            rank: index + 1,
                            rationale: nil
                        )
                    }
                )
            )
        }

        return slots
    }

    // MARK: - Hard constraints

    /// Surveyed-and-contradicted is excluded. Never-surveyed is kept.
    private func isEligible(_ venue: GroundedVenue, for brief: OutingBrief) -> Bool {
        if brief.dietary.isHardConstraint,
           let missing = venue.dietaryTags.unsatisfied(by: brief.dietary.requirements),
           !missing.isEmpty {
            return false
        }

        if brief.accessibility.isHardConstraint,
           let missing = venue.accessibilityTags.unsatisfied(by: brief.accessibility.requirements),
           !missing.isEmpty {
            return false
        }

        if brief.setting.isHardConstraint, venue.setting.satisfies(brief.setting) == false {
            return false
        }

        return true
    }

    /// Slot names matching the decks the current curation UI already shows.
    private static func title(for category: SlotCategory) -> String {
        switch category {
        case .food: return "Dinner"
        case .sights: return "Afternoon"
        case .nightlife: return "Late"
        case .discover: return "Something new"
        }
    }
}
