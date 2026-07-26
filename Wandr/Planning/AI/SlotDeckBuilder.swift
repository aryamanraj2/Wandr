//
//  SlotDeckBuilder.swift
//  Wandr
//
//  Turns a curator's *preferences* into a deck the validator will accept.
//
//  Both curators funnel through this, for the same reason `ConstraintEligibility`
//  exists: a rule that lives in only one of them is a rule the other can silently
//  break, and then a passing test proves nothing about production.
//
//  Foundation only — no FoundationModels — so the whole deck contract is unit
//  testable without a device, a model, or Apple Intelligence being switched on.
//
//  ## The one way a deck can still kill a run
//
//  Depth and budget no longer end anything — a thin deck is a thin deck, and a price
//  over the host's ceiling is a note on the card. What `FeasibilityValidator` still
//  fails the **entire run** over is venue *reuse*: the same place in two stops.
//
//  That rule became reachable the moment a plan could hold two stops of one category
//  ("lunch and dinner"), because both decks draw from an identical pool. Preventing
//  it is this type's job — `excluding:` drops what an earlier stop took, and `limit:`
//  stops the first deck swallowing the whole pool so the second still has something.
//  The validator only *detects* the collision; by then the host has lost their plan.
//
//  ## Why over-budget venues are not simply filtered out
//
//  Ordering, not exclusion: `budgetPreferred` puts affordable venues first and keeps
//  the rest as a tail. `EvidenceResolver` has already decided whether the ceiling had
//  to be given up at all, and discloses it when so; this type just makes sure the
//  cheap ones are seen first. An unknown price counts as affordable — the validator
//  warns about the missing price rather than assuming the worst.
//

import Foundation

/// Builds one slot's deck from a curator's ranked preferences plus the evidence.
nonisolated struct SlotDeckBuilder: Sendable {

    /// Deck ceiling. More than this is more than anyone swipes.
    let maxCandidatesPerSlot: Int

    /// Deck floor, mirroring `FeasibilityRules.minimumCandidatesPerSlot` so the
    /// builder and the validator cannot disagree about what "deep enough" means.
    let minimumCandidatesPerSlot: Int

    init(
        maxCandidatesPerSlot: Int = 5,
        minimumCandidatesPerSlot: Int = FeasibilityRules.default.minimumCandidatesPerSlot
    ) {
        self.maxCandidatesPerSlot = maxCandidatesPerSlot
        self.minimumCandidatesPerSlot = minimumCandidatesPerSlot
    }

    /// What one deck ended up being made of. `backfilled` is the interesting number:
    /// it is how much of the deck the curator failed to supply.
    ///
    /// The `rejected*` counts exist for the log. Since a bad pick is now silently
    /// repaired instead of failing the run, these are the only evidence that the
    /// model is drifting — a rising `rejectedOutOfRange` means it has stopped
    /// understanding the numbered list, which no user-visible symptom would reveal.
    nonisolated struct Deck: Sendable, Equatable {
        let candidates: [CuratedCandidate]
        /// Candidates that came from the curator's own ordering.
        let fromCurator: Int
        /// Candidates added deterministically to meet the deck contract.
        let backfilled: Int
        /// Picks naming a position that does not exist in the list shown.
        let rejectedOutOfRange: Int
        /// Picks naming a venue already in this deck.
        let rejectedDuplicate: Int
        /// Picks the budget ruled out while affordable venues were still available.
        let rejectedOverBudget: Int

        /// A one-line summary for the log.
        var summary: String {
            """
            fromModel=\(fromCurator) backfilled=\(backfilled) total=\(candidates.count) \
            rejectedOutOfRange=\(rejectedOutOfRange) rejectedDuplicate=\(rejectedDuplicate) \
            rejectedOverBudget=\(rejectedOverBudget)
            """
        }
    }

    // MARK: - Ordering

    /// `venues`, reordered so everything that fits the budget comes first.
    ///
    /// Order *within* each group is preserved, so `DistrictVenueProvider`'s ranking
    /// (cheapest-in-budget first, `venueID` as a stable tiebreak) still decides
    /// everything this method doesn't. An unknown price counts as in-budget — the
    /// validator warns about it rather than failing, so it must not be demoted
    /// below a venue that is *known* to break the ceiling.
    func budgetPreferred(_ venues: [GroundedVenue], for brief: OutingBrief) -> [GroundedVenue] {
        guard let ceiling = brief.budget.value.ceilingPerHead(for: brief.groupSize.value) else { return venues }

        var affordable: [GroundedVenue] = []
        var overBudget: [GroundedVenue] = []
        for venue in venues {
            if let perHead = venue.cost.knownPerHeadRupees, perHead > ceiling {
                overBudget.append(venue)
            } else {
                affordable.append(venue)
            }
        }

        // Falling back to the over-budget tail only when the affordable ones cannot
        // fill a deck is what preserves the validator's `.overBudget` message for
        // genuinely impossible budgets, without spending it on decks that had a
        // perfectly good affordable option sitting right there.
        guard affordable.count < minimumCandidatesPerSlot else { return affordable }
        return affordable + overBudget
    }

    // MARK: - Building

    /// The deck for one slot.
    ///
    /// - Parameters:
    ///   - preferredIndices: the curator's choices, as indices into `venues`, best
    ///     first. Out-of-range and repeated entries are dropped rather than trusted.
    ///   - rationales: optional prose per index, keyed the same way. A missing or
    ///     blank entry simply yields no rationale.
    ///   - venues: the slot's eligible evidence, already in provider rank order.
    ///   - excluding: venues already spent on an earlier stop.
    ///
    ///     This is what keeps lunch and dinner from being the same restaurant. Two
    ///     stops of one category draw from an identical pool, so without it the same
    ///     place lands in both decks — and `FeasibilityValidator`'s no-reuse rule then
    ///     fails the *whole run* with "The same place was picked for two different
    ///     stops". That rule detects the collision; only this prevents it.
    ///   - limit: a tighter ceiling than `maxCandidatesPerSlot` for this deck alone.
    ///
    ///     Set when a later stop shares this one's category and needs venues left for
    ///     it. Without it the first deck takes the whole pool and the second is
    ///     skipped for having nothing — so "lunch and dinner" quietly became lunch.
    func build(
        preferredIndices: [Int],
        rationales: [Int: String] = [:],
        venues: [GroundedVenue],
        brief: OutingBrief,
        excluding spent: Set<VenueID> = [],
        limit: Int? = nil
    ) -> Deck {
        let ceiling = min(limit ?? maxCandidatesPerSlot, maxCandidatesPerSlot)
        let ordered = budgetPreferred(venues.filter { !spent.contains($0.venueID) }, for: brief)

        // The curator was shown `venues`, so its indices address that array — but the
        // deck is drawn from `ordered`. Resolving through the venue ID rather than the
        // position is what keeps those two from silently diverging.
        let allowed = Set(ordered.map(\.venueID))

        var taken: Set<VenueID> = []
        var candidates: [CuratedCandidate] = []
        var outOfRange = 0
        var duplicate = 0
        var overBudget = 0

        for index in preferredIndices {
            guard candidates.count < ceiling else { break }

            guard venues.indices.contains(index) else {
                outOfRange += 1
                continue
            }

            let venue = venues[index]

            // Checked before the budget test so the counts stay honest: a pick that
            // an earlier stop already took is a duplicate, not an expensive one, and
            // a rising `rejectedOverBudget` is supposed to mean the model has stopped
            // reading prices.
            guard !spent.contains(venue.venueID), !taken.contains(venue.venueID) else {
                duplicate += 1
                continue
            }

            // Silently dropping a pick the budget rules out is correct here: the
            // curator only ever ranks, and a deck it over-filled is still a deck the
            // validator would have destroyed the whole run over.
            guard allowed.contains(venue.venueID) else {
                overBudget += 1
                continue
            }

            taken.insert(venue.venueID)
            candidates.append(
                CuratedCandidate(
                    venueID: venue.venueID,
                    rank: candidates.count + 1,
                    rationale: Self.cleaned(rationales[index])
                )
            )
        }

        let fromCurator = candidates.count

        // Below the floor, fill from the provider's order. Fill to the *full* deck
        // rather than just to the floor, so a failed generation still reads as a
        // complete slate instead of a visibly stunted one.
        if candidates.count < minimumCandidatesPerSlot {
            for venue in ordered {
                guard candidates.count < ceiling else { break }
                guard !taken.contains(venue.venueID) else { continue }
                taken.insert(venue.venueID)
                candidates.append(
                    CuratedCandidate(
                        venueID: venue.venueID,
                        rank: candidates.count + 1,
                        rationale: nil
                    )
                )
            }
        }

        return Deck(
            candidates: candidates,
            fromCurator: fromCurator,
            backfilled: candidates.count - fromCurator,
            rejectedOutOfRange: outOfRange,
            rejectedDuplicate: duplicate,
            rejectedOverBudget: overBudget
        )
    }

    /// The deck a curator with no opinion would produce: the provider's ranking,
    /// budget-preferred, capped. Used when there is nothing to curate.
    func deterministicDeck(
        venues: [GroundedVenue],
        brief: OutingBrief,
        excluding spent: Set<VenueID> = [],
        limit: Int? = nil
    ) -> Deck {
        build(preferredIndices: [], venues: venues, brief: brief, excluding: spent, limit: limit)
    }

    // MARK: - Helpers

    /// Trims a rationale; an empty one becomes `nil` rather than "".
    private static func cleaned(_ rationale: String?) -> String? {
        guard let trimmed = rationale?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
