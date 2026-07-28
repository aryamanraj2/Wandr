//
//  SemanticVenueRankerTests.swift
//  WandrTests
//
//  Whether ranking by meaning actually beats ranking by nothing.
//
//  These run against the **real bundled dataset**, not fixtures, because the thing
//  under test is precisely whether the taglines a human wrote carry enough signal to
//  order a deck. A fixture with "quiet" in the tagline and "quiet" in the query would
//  prove only that cosine similarity works.
//
//  The embedding assets ship separately from the app and are genuinely absent on some
//  devices, so every test here skips rather than fails when the ranker reports
//  unavailable. A skip is honest; a green suite that measured nothing is not.
//

import Foundation
import NaturalLanguage
import Testing
@testable import Wandr

@Suite("Semantic venue ranking")
struct SemanticVenueRankerTests {

    private func venues() throws -> [GroundedVenue] {
        try DistrictVenueProvider(bundle: .main, retrievedAt: Fixtures.retrievedAt).allVenues
    }

    /// The stated intent, and a venue whose own description should answer it.
    ///
    /// Chosen so no expected venue repeats a content word from its query — "loud to
    /// dance" against a tagline that says "resident DJs", not one that says "loud".
    /// Keyword matching scores zero on this set by construction, which is the point.
    private static let cases: [(query: String, expect: String)] = [
        ("somewhere loud to dance late",                 "Basement Forty"),
        ("quiet enough to actually talk",                "Neel Bhavan"),
        ("something to make with our hands",             "Kiln & Wheel"),
        ("a fast cheap bite standing up",                "Khan Chacha"),
        ("outdoors, good for photographs",               "Lodhi Art District"),
        ("browse books for an hour",                     "Bahrisons Booksellers")
    ]

    /// Whether this machine can score anything at all.
    ///
    /// Attempts the **load**, not just `hasAvailableAssets`. In the iOS Simulator the
    /// flag reads `true` and `load()` then throws anyway — so a gate built on the flag
    /// alone does not skip, it runs the test and fails it. Asking the same question the
    /// ranker asks is the only version that cannot disagree with the ranker.
    ///
    /// Gating produces a **skip**, which is the honest outcome: a quality test that
    /// silently passes on a machine that measured nothing is worse than no test,
    /// because the number it reports is an empty average and it reads as green.
    static var canScore: Bool {
        guard let embedding = NLContextualEmbedding(language: .english),
              embedding.hasAvailableAssets,
              (try? embedding.load()) != nil
        else { return false }
        embedding.unload()
        return true
    }

    @Test("Ranking puts the venue that answers the query near the top",
          .enabled(if: canScore, "NLContextualEmbedding assets are not on this machine"))
    func rankingSurfacesTheRightVenue() async throws {
        let ranker = SemanticVenueRanker()
        let all = try venues()

        var hits = 0
        var scored = 0

        for (query, expected) in Self.cases {
            // Rank the whole dataset — the realistic task, not a curated shortlist.
            guard let order = await ranker.ranking(of: all, matching: query) else { continue }
            scored += 1

            let names = order.prefix(10).map { all[$0].name }
            if names.contains(expected) { hits += 1 }
        }

        try #require(scored > 0, "Embedding assets unavailable — nothing was measured")
        #expect(scored == Self.cases.count)

        // A top-10 out of ~194 is a 5% slice, so chance alone lands roughly 0.3 of
        // these. Gated well above that and well below perfect: this is a ranking
        // signal over one-line taglines, not a search engine, and pretending otherwise
        // is how a threshold ends up tuned to whatever today's number happened to be.
        #expect(hits >= 4, "\(hits)/\(Self.cases.count) queries surfaced their venue in the top 10")
    }

    @Test("An empty query ranks nothing, rather than ranking arbitrarily")
    func emptyQueryDeclinesToRank() async throws {
        let ranker = SemanticVenueRanker()
        let all = try venues()

        #expect(await ranker.ranking(of: all, matching: "") == nil)
        #expect(await ranker.ranking(of: all, matching: "   \n ") == nil)
    }

    @Test("A single candidate needs no ranking")
    func oneVenueIsNotRanked() async throws {
        let ranker = SemanticVenueRanker()
        let one = try Array(venues().prefix(1))

        #expect(await ranker.ranking(of: one, matching: "anything at all") == nil)
    }

    @Test("Ranking is a permutation — it never drops or duplicates a venue")
    func rankingIsAPermutation() async throws {
        let ranker = SemanticVenueRanker()
        let all = try venues()

        guard let order = await ranker.ranking(of: all, matching: "somewhere to eat") else { return }

        #expect(order.count == all.count)
        #expect(Set(order) == Set(all.indices), "A deck may be reordered, never thinned")
    }

    @Test("The same query twice gives the same order")
    func rankingIsReproducible() async throws {
        let ranker = SemanticVenueRanker()
        let all = try venues()
        let query = "a rooftop with a view, somewhere to celebrate"

        guard let first = await ranker.ranking(of: all, matching: query) else { return }
        let second = await ranker.ranking(of: all, matching: query)

        #expect(first == second, "Ties must break deterministically or a plan is not reproducible")
    }

    @Test("Matching text is the venue's own words, and never its area")
    func matchedTextExcludesArea() throws {
        // Area is already a hard filter upstream. Including it here would let a
        // neighbourhood named in the query outscore what the host asked to *do*.
        let khanMarket = try #require(venues().first { $0.area == "Khan Market" })
        let text = SemanticVenueRanker.text(of: khanMarket)

        #expect(text.contains(khanMarket.name))
        #expect(text.contains(khanMarket.tagline))
        #expect(!text.contains(khanMarket.area) || khanMarket.name.contains(khanMarket.area))
        #expect(!text.contains(khanMarket.category.rawValue),
                "Category is fixed by the slot, so scoring it dilutes everything else")
    }

    /// Runs everywhere, deliberately. The quality test above skips without assets, so
    /// this is the one that proves the *absent* case is handled — that a device which
    /// cannot embed still gets a deck rather than a crash or an empty list.
    @Test("Without embedding assets, ranking declines instead of failing")
    func missingAssetsDegradeToNoRanking() async throws {
        let ranker = SemanticVenueRanker()
        let all = try venues()
        let order = await ranker.ranking(of: all, matching: "somewhere quiet")

        if Self.canScore {
            #expect(order != nil)
        } else {
            #expect(order == nil, "Unavailable must mean 'no opinion', never a wrong opinion")
        }
        // Either way the caller still has every venue to build a deck from.
        #expect(!all.isEmpty)
    }

    @Test("Cosine is bounded and behaves at the edges")
    func cosineIsWellBehaved() {
        #expect(SemanticVenueRanker.cosine([1, 0], [1, 0]) == 1)
        #expect(SemanticVenueRanker.cosine([1, 0], [0, 1]) == 0)
        #expect(SemanticVenueRanker.cosine([], []) == 0)
        #expect(SemanticVenueRanker.cosine([0, 0], [1, 1]) == 0, "A zero vector cannot divide")
        #expect(SemanticVenueRanker.cosine([1, 1], [1, 1, 1]) == 0, "Mismatched dimensions score nothing")
    }
}
