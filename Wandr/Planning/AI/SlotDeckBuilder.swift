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
//  ## The two ways a deck kills a run
//
//  `FeasibilityValidator` fails the **entire run**, not the slot, when either of
//  these is true of any deck it is handed:
//
//    1. **Rule 6, depth** — fewer than `minimumCandidatesPerSlot` candidates while
//       the category had enough venues to do better.
//    2. **Rule 4, budget** — any candidate whose *known* per-head price is above the
//       host's ceiling.
//
//  A language model honours neither reliably, and `.prefix(n)` honours the second
//  by luck. So neither is left to chance here: this type fills depth from the
//  provider's own ranking, and treats over-budget venues as a last resort.
//
//  ## Why over-budget venues are not simply filtered out
//
//  Because "we couldn't find anything in your budget" is a *better* answer than
//  "that plan didn't hold up", and only the validator can say it. If a category has
//  enough in-budget venues, an over-budget one has no business in the deck. If it
//  has none, the deck is built from over-budget venues *on purpose* so the validator
//  can name the ceiling the host set and tell them to widen it.
//
//  That is the same shape as the surveyed-and-contradicted rule in
//  `ConstraintEligibility`: prefer what provably fits, but never manufacture a
//  silence where a specific, actionable message belongs.
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
        guard let limit = brief.budgetPerHead.value.limitRupees else { return venues }

        var affordable: [GroundedVenue] = []
        var overBudget: [GroundedVenue] = []
        for venue in venues {
            if let perHead = venue.cost.knownPerHeadRupees, perHead > limit {
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
    func build(
        preferredIndices: [Int],
        rationales: [Int: String] = [:],
        venues: [GroundedVenue],
        brief: OutingBrief
    ) -> Deck {
        let ordered = budgetPreferred(venues, for: brief)

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
            guard candidates.count < maxCandidatesPerSlot else { break }

            guard venues.indices.contains(index) else {
                outOfRange += 1
                continue
            }

            let venue = venues[index]

            // Silently dropping a pick the budget rules out is correct here: the
            // curator only ever ranks, and a deck it over-filled is still a deck the
            // validator would have destroyed the whole run over.
            guard allowed.contains(venue.venueID) else {
                overBudget += 1
                continue
            }
            guard !taken.contains(venue.venueID) else {
                duplicate += 1
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
                guard candidates.count < maxCandidatesPerSlot else { break }
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
    func deterministicDeck(venues: [GroundedVenue], brief: OutingBrief) -> Deck {
        build(preferredIndices: [], venues: venues, brief: brief)
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
