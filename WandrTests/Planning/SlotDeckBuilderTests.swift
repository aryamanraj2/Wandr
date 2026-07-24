//
//  SlotDeckBuilderTests.swift
//  WandrTests
//
//  The deck contract, tested without a model.
//
//  These are the tests the old curator could not have: it called
//  `LanguageModelSession` inline, so "what happens when the model returns two picks"
//  was only answerable on a device with Apple Intelligence switched on — which is
//  exactly why it shipped returning two picks and failing the run.
//
//  Every case below is a way a language model actually misbehaves. The rule they all
//  defend is the same one: **whatever the curator does or fails to do, the deck
//  handed to `FeasibilityValidator` must be one it accepts.**
//

import Testing
@testable import Wandr

@Suite("Slot deck builder")
struct SlotDeckBuilderTests {

    private let builder = SlotDeckBuilder(maxCandidatesPerSlot: 5, minimumCandidatesPerSlot: 3)

    /// Five affordable food venues against `afterWorkBrief`'s ₹1,500 ceiling.
    private let affordable: [GroundedVenue] = [
        Fixtures.venue("food-1", category: .food, perHead: 900),
        Fixtures.venue("food-2", category: .food, perHead: 1_000),
        Fixtures.venue("food-3", category: .food, perHead: 1_100),
        Fixtures.venue("food-4", category: .food, perHead: 1_200),
        Fixtures.venue("food-5", category: .food, perHead: 1_300)
    ]

    private var brief: OutingBrief { Fixtures.afterWorkBrief }

    // MARK: - Depth
    //
    // The bug that made the app feel broken: the prompt said "returning fewer places
    // is fine", the validator said three or the run dies.

    @Test("One pick is topped up to a full deck")
    func underDeliveryIsBackfilled() {
        let deck = builder.build(preferredIndices: [2], venues: affordable, brief: brief)

        #expect(deck.candidates.count == 5)
        #expect(deck.fromCurator == 1)
        #expect(deck.backfilled == 4)
        // The model's one opinion still leads the deck.
        #expect(deck.candidates.first?.venueID == VenueID("food-3"))
    }

    @Test("No picks at all still produces a full deck")
    func emptyPicksStillFillTheDeck() {
        let deck = builder.build(preferredIndices: [], venues: affordable, brief: brief)

        #expect(deck.candidates.count == 5)
        #expect(deck.fromCurator == 0)
        // Provider order is preserved, so the deck is the cheapest-first ranking.
        #expect(deck.candidates.map(\.venueID) == affordable.map(\.venueID))
    }

    @Test("A deck at or above the floor is left alone")
    func sufficientPicksAreNotPadded() {
        let deck = builder.build(preferredIndices: [4, 0, 2], venues: affordable, brief: brief)

        #expect(deck.candidates.count == 3)
        #expect(deck.backfilled == 0)
        #expect(deck.candidates.map(\.venueID) == [VenueID("food-5"), VenueID("food-1"), VenueID("food-3")])
    }

    @Test("A category thinner than the floor yields everything it has, not a crash")
    func thinCategoryYieldsWhatExists() {
        let two = Array(affordable.prefix(2))
        let deck = builder.build(preferredIndices: [0], venues: two, brief: brief)

        // Two is all there is. The validator turns this into `.insufficientEvidence`,
        // which is the honest answer — the builder must not invent a third.
        #expect(deck.candidates.count == 2)
    }

    // MARK: - Malformed picks

    @Test("Out-of-range indices are dropped and the deck is still filled")
    func outOfRangeIndicesAreDropped() {
        let deck = builder.build(preferredIndices: [99, -1, 7], venues: affordable, brief: brief)

        #expect(deck.candidates.count == 5)
        #expect(deck.fromCurator == 0, "None of those indices address a real venue")
        #expect(Set(deck.candidates.map(\.venueID)).count == 5)
    }

    @Test("Repeated indices are deduped, then backfilled")
    func duplicateIndicesAreDeduped() {
        let deck = builder.build(preferredIndices: [1, 1, 1], venues: affordable, brief: brief)

        #expect(deck.fromCurator == 1)
        #expect(deck.candidates.count == 5)
        #expect(Set(deck.candidates.map(\.venueID)).count == 5, "A duplicate inside one deck fails validation")
    }

    @Test("Ranks are always 1...n with no gaps")
    func ranksAreContiguous() {
        let deck = builder.build(preferredIndices: [3, 99, 3, 0], venues: affordable, brief: brief)

        #expect(deck.candidates.map(\.rank) == Array(1...deck.candidates.count))
    }

    // MARK: - Budget
    //
    // The second run-killer, and the quieter one: `FeasibilityValidator` Rule 4 fails
    // the whole run for a single over-budget candidate, and nothing upstream stopped
    // a curator from choosing one.

    /// Three affordable venues plus one well over the ₹1,500 ceiling.
    private var mixedBudget: [GroundedVenue] {
        [
            Fixtures.venue("food-1", category: .food, perHead: 900),
            Fixtures.venue("food-2", category: .food, perHead: 1_000),
            Fixtures.venue("food-3", category: .food, perHead: 1_100),
            Fixtures.venue("food-rich", category: .food, perHead: 2_400)
        ]
    }

    @Test("An over-budget pick is dropped when affordable venues can fill the deck")
    func overBudgetPickIsDropped() {
        let deck = builder.build(preferredIndices: [3, 0, 1], venues: mixedBudget, brief: brief)

        #expect(!deck.candidates.map(\.venueID).contains(VenueID("food-rich")))
        #expect(deck.candidates.count == 3)
    }

    @Test("Backfill never reaches for an over-budget venue it doesn't need")
    func backfillPrefersAffordable() {
        let deck = builder.build(preferredIndices: [], venues: mixedBudget, brief: brief)

        #expect(deck.candidates.count == 3)
        #expect(!deck.candidates.map(\.venueID).contains(VenueID("food-rich")))
    }

    @Test("An impossible budget still builds a deck, so the validator can name the ceiling")
    func impossibleBudgetStillBuildsADeck() {
        // ₹200 a head against venues starting at ₹900. Filtering these out would
        // replace "nothing here fits ₹200 a head" with "that plan didn't hold up",
        // which tells the host nothing and hides the one number they can change.
        let deck = builder.build(
            preferredIndices: [],
            venues: affordable,
            brief: Fixtures.impossibleBudgetBrief
        )

        #expect(deck.candidates.count == 5)
    }

    @Test("An unstated budget rules nothing out")
    func unspecifiedBudgetKeepsEverything() {
        let deck = builder.build(preferredIndices: [], venues: mixedBudget, brief: Fixtures.sparseBrief)

        #expect(deck.candidates.count == 4)
        #expect(deck.candidates.map(\.venueID).contains(VenueID("food-rich")))
    }

    @Test("An unknown price is treated as affordable, never demoted below a known overspend")
    func unknownCostIsNotPenalised() {
        let venues = [
            Fixtures.venue("food-rich", category: .food, perHead: 2_400),
            Fixtures.venue("food-mystery", category: .food, perHead: nil),
            Fixtures.venue("food-1", category: .food, perHead: 900),
            Fixtures.venue("food-2", category: .food, perHead: 1_000)
        ]
        let deck = builder.build(preferredIndices: [], venues: venues, brief: brief)

        // Unknown cost is a validator *warning*, not a violation — so it belongs in
        // the deck ahead of a venue that is known to break the ceiling.
        #expect(deck.candidates.map(\.venueID).contains(VenueID("food-mystery")))
        #expect(!deck.candidates.map(\.venueID).contains(VenueID("food-rich")))
    }

    // MARK: - Rationale

    @Test("Rationales follow their pick, and blanks become nil")
    func rationalesAreAttachedAndTrimmed() {
        let deck = builder.build(
            preferredIndices: [1, 0],
            rationales: [1: "  Good for a loud table.  ", 0: "   "],
            venues: affordable,
            brief: brief
        )

        #expect(deck.candidates[0].rationale == "Good for a loud table.")
        #expect(deck.candidates[1].rationale == nil, "A blank rationale must not render as an empty line")
    }

    @Test("Backfilled candidates carry no invented rationale")
    func backfilledCandidatesHaveNoRationale() {
        let deck = builder.build(
            preferredIndices: [0],
            rationales: [0: "The model's one thought."],
            venues: affordable,
            brief: brief
        )

        #expect(deck.candidates[0].rationale != nil)
        #expect(deck.candidates.dropFirst().allSatisfy { $0.rationale == nil })
    }

    // MARK: - Determinism

    @Test("The same inputs always produce the same deck")
    func buildingIsDeterministic() {
        let first = builder.build(preferredIndices: [3, 1], venues: mixedBudget, brief: brief)
        let second = builder.build(preferredIndices: [3, 1], venues: mixedBudget, brief: brief)

        #expect(first == second)
    }
}
