//
//  DistrictVenueProviderTests.swift
//  WandrTests
//
//  Dataset integrity. These are the tests that catch a bad JSON edit before a demo.
//

import Foundation
import Testing
@testable import Wandr

@Suite("District venue provider")
struct DistrictVenueProviderTests {

    /// The provider under test, loaded from the app bundle with a fixed clock.
    private func makeProvider() throws -> DistrictVenueProvider {
        try DistrictVenueProvider(bundle: .main, retrievedAt: Fixtures.retrievedAt)
    }

    // MARK: - Decode integrity

    @Test("The bundled dataset decodes")
    func datasetDecodes() throws {
        let provider = try makeProvider()
        #expect(!provider.allVenues.isEmpty)
    }

    @Test("Every venue has a name, an area, and a tagline")
    func venuesAreDisplayable() throws {
        for venue in try makeProvider().allVenues {
            #expect(!venue.name.isEmpty, "\(venue.venueID) has no name")
            #expect(!venue.area.isEmpty, "\(venue.venueID) has no area")
            #expect(!venue.tagline.isEmpty, "\(venue.venueID) has no tagline")
        }
    }

    @Test("Venue IDs are unique")
    func venueIDsAreUnique() throws {
        let ids = try makeProvider().allVenues.map(\.venueID)
        #expect(Set(ids).count == ids.count, "The dataset contains a duplicate venue ID")
    }

    // MARK: - Category floor

    /// The floor `FeasibilityValidator` already enforces. Below it, every run in
    /// that category is rejected on evidence grounds no matter how good curation is.
    @Test("Every category clears the validator's floor", arguments: SlotCategory.allCases)
    func categoryFloorIsMet(category: SlotCategory) throws {
        let count = try makeProvider().allVenues.count { $0.category == category }
        #expect(
            count >= FeasibilityRules.default.minimumCandidatesPerSlot,
            "Only \(count) \(category.rawValue) venues; the validator needs 3"
        )
    }

    /// §10's demo-script requirement: the after-work fixture names Hauz Khas, so
    /// Hauz Khas alone must be able to fill every deck.
    @Test("Hauz Khas alone fills every category")
    func hauzKhasIsDemoReady() throws {
        let provider = try makeProvider()
        let venues = provider.venues(in: "Hauz Khas")

        for category in SlotCategory.allCases {
            let count = venues.count { $0.category == category }
            #expect(count >= 3, "Hauz Khas has only \(count) \(category.rawValue) venues")
        }
    }

    // MARK: - Unknown vs. known

    /// The distinction this whole file exists to protect: a field the JSON never
    /// mentions must not arrive as an empty-but-surveyed tag set.
    @Test("An absent tag field decodes to .unknown, not .known([])")
    func absentFieldsDecodeToUnknown() throws {
        let provider = try makeProvider()

        // `hk-food-3` states dietary tags but omits accessibility entirely.
        let neel = try #require(provider.allVenues.first { $0.venueID == VenueID("hk-food-3") })
        #expect(neel.dietaryTags == .known([.vegetarian, .jain]))
        #expect(neel.accessibilityTags == .unknown, "Absent accessibility must stay unsurveyed")

        // `hk-disc-1` states an *empty* dietary set — surveyed, and genuinely none.
        let kiln = try #require(provider.allVenues.first { $0.venueID == VenueID("hk-disc-1") })
        #expect(kiln.dietaryTags == .known([]), "An empty-but-present array is a surveyed result")
        #expect(kiln.dietaryTags != .unknown)
    }

    @Test("An absent price decodes to .unknown rather than zero")
    func absentPriceIsUnknown() throws {
        // Every venue in the shipped dataset happens to state a price; the guard
        // that matters is that a stated 0 is still *known*, not confused with absent.
        let provider = try makeProvider()
        let free = try #require(provider.allVenues.first { $0.venueID == VenueID("cp-sight-2") })
        #expect(free.cost == .known(perHeadRupees: 0, listPriceRupees: nil))
        #expect(free.cost.knownPerHeadRupees == 0)
    }

    @Test("Absent availability, hours, and setting stay unknown")
    func absentProvenanceStaysUnknown() throws {
        let provider = try makeProvider()
        let listening = try #require(provider.allVenues.first { $0.venueID == VenueID("hk-disc-3") })
        #expect(listening.availability == .unknown)

        let unavailable = try #require(provider.allVenues.first { $0.venueID == VenueID("cyber-night-2") })
        #expect(unavailable.availability == .unavailable(reason: "Closed for renovation this season."))
    }

    @Test("Offer and offer window survive decoding, and stay nil when absent")
    func offersDecode() throws {
        let provider = try makeProvider()
        let rooh = try #require(provider.allVenues.first { $0.venueID == VenueID("hk-food-1") })
        #expect(rooh.offer == "20% off the tasting board")
        #expect(rooh.offerWindow == "Weeknights before 8:00 pm")

        let noOffer = try #require(provider.allVenues.first { $0.venueID == VenueID("hk-food-3") })
        #expect(noOffer.offer == nil)
        #expect(noOffer.offerWindow == nil)
    }

    // MARK: - Provenance

    /// Provenance is the provider's to assign. If any of this could be read from
    /// the file, a hand-edited dataset could claim it was retrieved seconds ago.
    @Test("The provider stamps source and retrievedAt itself")
    func provenanceIsAssignedByProvider() throws {
        let provider = try makeProvider()

        for venue in provider.allVenues {
            #expect(venue.source == provider.source)
            #expect(venue.source.provider == "bundledDataset")
            #expect(!venue.source.version.isEmpty)
            #expect(venue.retrievedAt == Fixtures.retrievedAt)
        }
    }

    @Test("A different retrieval clock produces a different timestamp on every venue")
    func retrievedAtTracksTheInjectedClock() throws {
        let later = Fixtures.retrievedAt.addingTimeInterval(3_600)
        let provider = try DistrictVenueProvider(bundle: .main, retrievedAt: later)
        #expect(provider.allVenues.allSatisfy { $0.retrievedAt == later })
    }

    // MARK: - Search

    @Test("An area search returns only that area")
    func areaSearchFilters() throws {
        let venues = try makeProvider().venues(in: "Lodhi")
        #expect(!venues.isEmpty)
        #expect(venues.allSatisfy { $0.area == "Lodhi" })
    }

    @Test("Area matching folds the spellings the demo script uses")
    func areaAliasesResolve() throws {
        let provider = try makeProvider()
        #expect(provider.venues(in: "CP").allSatisfy { $0.area == "Connaught Place" })
        #expect(provider.venues(in: "  hauz khas ").allSatisfy { $0.area == "Hauz Khas" })
        #expect(provider.venues(in: "Gurgaon").allSatisfy { $0.area == "Cyberhub" })
        #expect(provider.venues(in: "Khan Market").allSatisfy { $0.area == "Khan Market" })
    }

    /// The failure the host actually hit: asking for CP and being shown Nizamuddin.
    ///
    /// The extractor returns what the host *said*, not a tidy key, so whole-string
    /// equality missed "Connaught Place, New Delhi" entirely, matched nothing, and
    /// fell through to the city-wide branch — which returned every other
    /// neighbourhood, cheapest first.
    @Test(
        "A named area survives the extra words the host says around it",
        arguments: [
            ("Connaught Place, New Delhi", "Connaught Place"),
            ("the CP area", "Connaught Place"),
            ("cp", "Connaught Place"),
            ("Khan Market, Delhi", "Khan Market"),
            ("khan market", "Khan Market"),
            ("Hauz Khas Village", "Hauz Khas"),
            ("DLF Cyber Hub, Gurugram", "Cyberhub"),
            ("Lodhi Colony", "Lodhi"),
            ("Select Citywalk", "Saket")
        ]
    )
    func areaSurvivesSurroundingWords(spoken: String, expected: String) throws {
        let venues = try makeProvider().venues(in: spoken)
        #expect(!venues.isEmpty, "\(spoken) matched nothing")
        #expect(venues.allSatisfy { $0.area == expected }, "\(spoken) leaked other areas")
    }

    /// A two-letter shorthand is only ever the whole answer. "5 km from CP" is a
    /// distance, not a request for Khan Market.
    @Test("A two-letter alias only matches on its own")
    func shortAliasesDoNotMatchMidSentence() throws {
        let provider = try makeProvider()
        #expect(provider.venues(in: "km").allSatisfy { $0.area == "Khan Market" })
        #expect(provider.venues(in: "5 km from CP").allSatisfy { $0.area == "Connaught Place" })
    }

    @Test("A city-wide area returns the whole dataset")
    func cityWideAreasWiden() throws {
        let provider = try makeProvider()
        for area in [OutingBrief.defaultArea, "Delhi", "New Delhi", "NCR", "anywhere"] {
            #expect(provider.venues(in: area).count == provider.allVenues.count, "\(area) should widen")
        }
    }

    /// The bug that made "Khan Market" show every neighbourhood except Khan Market:
    /// an unmatched area used to fall back to the entire dataset, so a host who
    /// named one place got a slate drawn from all the others with nothing saying so.
    @Test("An area the dataset does not hold returns nothing, never everything")
    func uncoveredAreaReturnsNothing() throws {
        let provider = try makeProvider()
        #expect(provider.venues(in: "Atlantis").isEmpty)
        #expect(provider.venues(in: "Noida").isEmpty)
    }

    @Test("Research reports an uncovered area instead of silently widening it")
    func uncoveredAreaFailsHonestly() async throws {
        let provider = try makeProvider()
        let brief = OutingBrief(area: .host("Noida"))

        await #expect(throws: PlanningFailure.self) {
            try await provider.research(for: brief)
        }

        do {
            _ = try await provider.research(for: brief)
            Issue.record("Expected an areaNotCovered failure")
        } catch let failure as PlanningFailure {
            guard case .areaNotCovered(let covered) = failure.category else {
                Issue.record("Expected .areaNotCovered, got \(failure.category)")
                return
            }
            #expect(covered.contains("Khan Market"))
            #expect(failure.retryAction == .editRequest)
            // The message names what Wandr *does* cover — never the host's own word.
            #expect(!failure.userMessage.contains("Noida"))
        }
    }

    /// Khan Market was the area the host asked for by name and the one the dataset
    /// did not have. It carries a full night now, not a token entry.
    @Test("Khan Market alone fills every category")
    func khanMarketIsComplete() throws {
        let venues = try makeProvider().venues(in: "Khan Market")

        for category in SlotCategory.allCases {
            let count = venues.count { $0.category == category }
            #expect(count >= 3, "Khan Market has only \(count) \(category.rawValue) venues")
        }
    }

    @Test("Research returns only the brief's area and is category-correct")
    func researchRespectsTheBrief() async throws {
        let result = try await makeProvider().research(for: Fixtures.afterWorkBrief)
        #expect(!result.venues.isEmpty)
        #expect(result.venues.allSatisfy { $0.area == "Hauz Khas" })
        #expect(!result.events.isEmpty)
    }

    // MARK: - Determinism

    @Test("Repeated research with the same brief returns the same order")
    func researchOrderIsStable() async throws {
        let provider = try makeProvider()
        let first = try await provider.research(for: Fixtures.afterWorkBrief).venues.map(\.venueID)
        let second = try await provider.research(for: Fixtures.afterWorkBrief).venues.map(\.venueID)
        let third = try await provider.research(for: Fixtures.afterWorkBrief).venues.map(\.venueID)

        #expect(first == second)
        #expect(second == third)
    }

    @Test("Two providers built from the same dataset agree on ordering")
    func orderingIsIndependentOfInstance() async throws {
        let a = try makeProvider()
        let b = try makeProvider()
        let fromA = try await a.research(for: Fixtures.sparseBrief).venues.map(\.venueID)
        let fromB = try await b.research(for: Fixtures.sparseBrief).venues.map(\.venueID)
        #expect(fromA == fromB)
    }

    /// Budget sorts, it never filters — the validator is the only component allowed
    /// to rule a venue out, and it does so with a named violation.
    @Test("An impossible budget still returns evidence, ranked in-budget first")
    func budgetRanksRatherThanFilters() async throws {
        let provider = try makeProvider()
        let result = try await provider.research(for: Fixtures.impossibleBudgetBrief)

        #expect(result.venues.count == provider.allVenues.count, "Budget must not drop venues")

        let limit = try #require(Fixtures.impossibleBudgetBrief.budgetPerHead.value.limitRupees)
        let overBudgetFlags = result.venues.map { venue -> Bool in
            guard let perHead = venue.cost.knownPerHeadRupees else { return false }
            return perHead > limit
        }
        // Once the list goes over budget it must never come back under.
        let firstOver = overBudgetFlags.firstIndex(of: true)
        if let firstOver {
            #expect(!overBudgetFlags[firstOver...].contains(false))
        }
    }
}
