// FakeItineraryCurator.swift Wandr TEMPORARY. Stands in for Step 4's Foundation Models curator. The one rule this fake must obey even though it is a fake: **it may only emit `VenueID`s drawn from the evidence it was handed.** That is also `FeasibilityValidator`'s Rule 1, and a fake that broke it would make Step 2's own tests unable to tell a broken coordinator from a broken curator. The `Misbehavior` knob below is the single, explicit exception: it exists so the coordinator's validation-failure branch is reachable in tests. It defaults to `.none` and nothing in the app ever sets it.

import Foundation

/// A deterministic, model-free `ItineraryCurating` stand-in. Ranking is "whatever order the provider handed me", which is already cheapest-first with a stable tiebreak — so curation adds no judgement of its own. Judgement is Step 4's problem.
nonisolated struct FakeItineraryCurator: ItineraryCurating, Sendable {

    /// Ways to make the curator misbehave on purpose, so the validator's teeth are provable through the coordinator. **Test-only.**
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

        // Deliberately *not* filtered here. `EvidenceResolver` runs before any curator and has already applied the hard constraints and given up whatever soft ones it had to; filtering again would make this fake stricter than production, which is the exact failure this file exists to prevent — a test passing against a rule the real curator doesn't apply.
        let eligible = evidence

        var slots: [CurationSlot] = []

        let builder = SlotDeckBuilder(maxCandidatesPerSlot: maxCandidatesPerSlot)

        // The same schedule production uses, so the fake produces the same *shape* of plan — including two stops of one category when the host asked for both.
        let schedule = brief.schedule

        // Mirrors production: two stops of one category must not share a venue.
        var spent: Set<VenueID> = []

        for feasible in schedule.slots {
            let inCategory = eligible.filter {
                $0.category == feasible.category && !spent.contains($0.venueID)
            }
            guard !inCategory.isEmpty else { continue }

            // Through `SlotDeckBuilder`, so the fake is held to the same deck rules as production. A blind `.prefix(n)` used to hand the validator over-budget venues whenever the dataset happened to list an expensive one early, which failed the whole run — a real bug the real curator shared, and one no test could catch while the two disagreed. Same reservation rule as production.
            let laterSharing = schedule.slots
                .drop { $0.band != feasible.band }
                .dropFirst()
                .count { $0.category == feasible.category }

            var picks = builder.deterministicDeck(
                venues: inCategory, brief: brief, excluding: spent,
                limit: max(1, inCategory.count - laterSharing)
            )
                .candidates
                .compactMap { candidate in inCategory.first { $0.venueID == candidate.venueID } }

            if misbehavior == .underPick {
                picks = Array(picks.prefix(1))
            }

            var venueIDs = picks.map(\.venueID)
            if misbehavior != .duplicateAcrossSlots { spent.formUnion(venueIDs) }

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
                    band: feasible.band,
                    title: feasible.title,
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

    /// Surveyed-and-contradicted is excluded. Never-surveyed is kept. Shared with the real curator via `ConstraintEligibility` so both apply the same rule.
    private func isEligible(_ venue: GroundedVenue, for brief: OutingBrief) -> Bool {
        ConstraintEligibility.isEligible(venue, for: brief)
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
