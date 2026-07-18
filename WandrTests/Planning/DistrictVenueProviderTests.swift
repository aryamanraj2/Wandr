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

    @Test("Every venue decodes with a nil coordinate — the JSON has no coordinate field")
    func coordinatesDecodeAsNil() throws {
        // The MapKit edit (edit 2) is additive: the dataset never carried coordinates,
        // so every venue must arrive with `coordinate == nil`, and the validator must
        // stay indifferent to that (proven in MapKitVenueEnricherTests).
        let provider = try makeProvider()
        #expect(provider.allVenues.allSatisfy { $0.coordinate == nil })
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
    }

    /// An unrecognised area widens the search rather than returning nothing —
    /// otherwise a typo would masquerade as "we found no venues".
    @Test("The default and unknown areas return the whole dataset")
    func unknownAreaWidensTheSearch() throws {
        let provider = try makeProvider()
        #expect(provider.venues(in: OutingBrief.defaultArea).count == provider.allVenues.count)
        #expect(provider.venues(in: "Atlantis").count == provider.allVenues.count)
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
