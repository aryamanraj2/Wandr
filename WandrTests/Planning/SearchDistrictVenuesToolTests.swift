//
//  SearchDistrictVenuesToolTests.swift
//  WandrTests
//
//  §13.1 deterministic tier for the tool. No model runs — these call the tool's
//  own `matches(for:)` / record helpers directly and assert the four properties
//  the grounding story rests on: only dataset IDs come back, the result bound is
//  honoured, repeated calls are identical, and the compact record excludes every
//  field the spec forbids.
//

import Foundation
import Testing
@testable import Wandr

@Suite("Search district venues tool")
struct SearchDistrictVenuesToolTests {

    /// A snapshot with more than eight venues in one category, so the bound bites.
    private static func snapshot() -> [GroundedVenue] {
        (1...12).map { i in
            Fixtures.venue("food-\(i)", category: .food, perHead: 800 + i)
        } + [
            Fixtures.venue("night-1", category: .nightlife, perHead: 1_300),
            Fixtures.venue("sight-1", category: .sights, perHead: 0)
        ]
    }

    private func tool() -> SearchDistrictVenuesTool {
        SearchDistrictVenuesTool(venues: Self.snapshot())
    }

    private func args(area: String = "", category: String = "food", limit: Int = 8) -> SearchDistrictVenuesTool.Arguments {
        SearchDistrictVenuesTool.Arguments(area: area, category: category, limit: limit)
    }

    // MARK: - Dataset IDs only

    @Test("Every returned venue is one the snapshot owns")
    func onlyDatasetIDs() {
        let snapshot = Self.snapshot()
        let ids = Set(snapshot.map(\.venueID))
        let results = tool().matches(for: args(category: "food", limit: 8))

        #expect(!results.isEmpty)
        #expect(results.allSatisfy { ids.contains($0.venueID) })
        #expect(results.allSatisfy { $0.category == .food })
    }

    // MARK: - Bounding

    @Test("The result count never exceeds the tool's ceiling, even when asked for more")
    func honoursBound() {
        // 12 food venues exist, but the ceiling is 8.
        let overAsk = SearchDistrictVenuesTool.Arguments(area: "", category: "food", limit: 999)
        #expect(tool().matches(for: overAsk).count == SearchDistrictVenuesTool.maxResults)

        // A smaller explicit limit is honoured.
        #expect(tool().matches(for: args(limit: 3)).count == 3)
    }

    // MARK: - Determinism

    @Test("The same arguments return the exact same venues in the same order")
    func deterministic() {
        let a = tool().matches(for: args(category: "food", limit: 6)).map(\.venueID)
        let b = tool().matches(for: args(category: "food", limit: 6)).map(\.venueID)
        #expect(a == b)
    }

    // MARK: - Category / area handling

    @Test("An unrecognised category still returns only real venues, never a fabrication")
    func unknownCategory() {
        let results = tool().matches(for: args(category: "teleport", limit: 8))
        let ids = Set(Self.snapshot().map(\.venueID))
        #expect(results.allSatisfy { ids.contains($0.venueID) })
    }

    @Test("A thin area widens rather than returning nothing")
    func thinAreaWidens() {
        // "Nowhere" matches no venue's area, so the search widens to the category set.
        let results = tool().matches(for: args(area: "Nowhere-ville", category: "food", limit: 8))
        #expect(!results.isEmpty)
    }

    // MARK: - Compact record

    @Test("The compact line carries id, name, category, area and a cost band — and nothing the spec excludes")
    func compactRecordShape() {
        let venue = Fixtures.venue("food-1", category: .food, perHead: 1_000)
        let line = SearchDistrictVenuesTool.compactLine(venue)

        #expect(line.contains("food-1"))
        #expect(line.contains(venue.name))
        #expect(line.contains("food"))
        #expect(line.contains(venue.area))
        #expect(line.contains("moderate"))

        // Excluded fields (§10.3): no tagline, no limitations, no timestamp.
        #expect(!line.contains(venue.tagline))
        #expect(line.split(separator: "\n").count == 1)
    }

    @Test("An unknown cost renders as 'unknown', never a guessed number")
    func unknownCostBand() {
        let venue = Fixtures.venue("food-x", category: .food, perHead: nil)
        #expect(SearchDistrictVenuesTool.costBand(venue.cost) == "unknown")
        #expect(SearchDistrictVenuesTool.compactLine(venue).contains("unknown"))
    }

    @Test("Cost bands are coarse ranges, not exact prices")
    func costBands() {
        #expect(SearchDistrictVenuesTool.costBand(.known(perHeadRupees: 300, listPriceRupees: nil)).hasPrefix("budget"))
        #expect(SearchDistrictVenuesTool.costBand(.known(perHeadRupees: 900, listPriceRupees: nil)).hasPrefix("moderate"))
        #expect(SearchDistrictVenuesTool.costBand(.known(perHeadRupees: 1_800, listPriceRupees: nil)).hasPrefix("premium"))
        #expect(SearchDistrictVenuesTool.costBand(.known(perHeadRupees: 5_000, listPriceRupees: nil)).hasPrefix("splurge"))
    }

    // MARK: - Offer

    @Test("A stated offer appears; its absence adds no field")
    func offerRendering() {
        let withOffer = GroundedVenue(
            venueID: VenueID("food-offer"),
            name: "Offer Place",
            category: .food,
            area: "Test Area",
            cost: .known(perHeadRupees: 900, listPriceRupees: 1_200),
            offer: "2-for-1 on cocktails",
            vibeTags: ["lively"],
            source: Fixtures.source,
            retrievedAt: Fixtures.retrievedAt
        )
        #expect(SearchDistrictVenuesTool.compactLine(withOffer).contains("offer: 2-for-1 on cocktails"))

        let noOffer = Fixtures.venue("food-plain", category: .food, perHead: 900)
        #expect(!SearchDistrictVenuesTool.compactLine(noOffer).contains("offer:"))
    }
}
