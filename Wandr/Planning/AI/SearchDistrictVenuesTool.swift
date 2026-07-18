//
//  SearchDistrictVenuesTool.swift
//  Wandr
//
//  The bundled Delhi dataset exposed as a Foundation Models `Tool`. The only tool
//  any session in this step receives.
//
//  Everything a tool must be here, it is: read-only, deterministic (it delegates to
//  `DistrictVenueProvider`'s existing stable search/order), and bounded — at most
//  eight venues per call, each a compact single line. It never fabricates a venue,
//  never reorders nondeterministically, and never returns an ID the dataset didn't
//  own. Tool output is for the *model* to choose from; the UI never renders it, so
//  the record carries only what a choice needs — no taglines, limitations, or
//  timestamps (§10.3).
//
//  Grounding is structural: the model may only ever name a `VenueID` it saw here,
//  and the curator resolves those IDs back against the same snapshot before any
//  slot is built. A hallucinated ID cannot survive that resolution, and Rule 1 of
//  the validator would reject it even if it did.
//

import Foundation
import FoundationModels

/// A read-only, bounded, deterministic search over the bundled dataset.
///
/// `class` rather than `struct` only because `Tool` is a reference-friendly
/// protocol and the provider snapshot is captured once; it holds no mutable state.
nonisolated final class SearchDistrictVenuesTool: Tool {

    let name = "searchDistrictVenues"
    let description = "Search the bundled Delhi NCR venue dataset for real places to build an outing from. Returns grounded venues by ID. Only use IDs this tool returns."

    /// The hard ceiling on how many venues one call may return (§10.3).
    static let maxResults = 8

    /// The evidence snapshot this tool searches. Captured once, never mutated.
    private let venues: [GroundedVenue]

    init(venues: [GroundedVenue]) {
        self.venues = venues
    }

    // MARK: - Arguments

    @Generable
    nonisolated struct Arguments: Equatable {
        @Guide(description: "The neighbourhood or area to search, e.g. 'Hauz Khas'. Empty to search everywhere.")
        var area: String

        @Guide(description: "Which kind of venue to return. Exactly one of: food, sights, nightlife, discover.")
        var category: String

        @Guide(description: "How many venues to return, at most eight.", .range(1...8))
        var limit: Int
    }

    // MARK: - Call

    /// Returns compact, dataset-owned records. In 27 a `Tool` returns its `Output`
    /// directly — there is no `ToolOutput` wrapper — so this hands back a `String`.
    func call(arguments: Arguments) async throws -> String {
        let results = matches(for: arguments)

        guard !results.isEmpty else {
            return "No venues found for that search."
        }

        return results.map(Self.compactLine).joined(separator: "\n")
    }

    // MARK: - Deterministic search

    /// Delegates ordering to the provider's own deterministic search where possible,
    /// then filters by the requested category and bounds the count. Same arguments
    /// in → same records out, always, which is what makes the Evaluations tier's
    /// tool-trajectory assertions assertable.
    func matches(for arguments: Arguments) -> [GroundedVenue] {
        let bound = min(max(arguments.limit, 1), Self.maxResults)

        let byCategory: [GroundedVenue]
        if let category = SlotCategory(rawValue: arguments.category.trimmingCharacters(in: .whitespacesAndNewlines)) {
            byCategory = venues.filter { $0.category == category }
        } else {
            // An unrecognised category is not a crash and not a fabrication — it just
            // narrows nothing. The model still only sees real venues.
            byCategory = venues
        }

        let area = arguments.area.trimmingCharacters(in: .whitespacesAndNewlines)
        let inArea = area.isEmpty ? byCategory : byCategory.filter {
            Self.areaMatches($0.area, query: area)
        }

        // Fall back to the category set if the area filter emptied it — a thin area
        // should widen, not masquerade as "no venues", mirroring the provider's rule.
        let scoped = inArea.isEmpty ? byCategory : inArea

        // `venues` is already sorted by `venueID` at load time, so this order is
        // stable and reproducible without any further sort.
        return Array(scoped.prefix(bound))
    }

    private static func areaMatches(_ venueArea: String, query: String) -> Bool {
        let a = venueArea.lowercased()
        let q = query.lowercased()
        return a == q || a.contains(q) || q.contains(a)
    }

    // MARK: - Compact record

    /// One venue as ONE line the model can choose from (§10.3):
    /// `id | name | category | area | cost band | vibe tags | offer`.
    /// No tagline, no limitations, no timestamp — the UI never renders this.
    static func compactLine(_ venue: GroundedVenue) -> String {
        var fields: [String] = [
            venue.venueID.rawValue,
            venue.name,
            venue.category.rawValue,
            venue.area,
            costBand(venue.cost)
        ]

        let vibes = venue.vibeTags.prefix(3)
        if !vibes.isEmpty {
            fields.append(vibes.joined(separator: "/"))
        }

        if let offer = venue.offer, !offer.isEmpty {
            fields.append("offer: \(offer)")
        }

        return fields.joined(separator: " | ")
    }

    /// A coarse cost band, never a precise number the model could quote as fact, and
    /// "unknown" when the dataset has no price. Bands are the model's ranking aid only.
    static func costBand(_ cost: VenueCost) -> String {
        guard let perHead = cost.knownPerHeadRupees else { return "unknown" }
        switch perHead {
        case ..<500:      return "budget (<₹500)"
        case 500..<1_200: return "moderate (₹500-1200)"
        case 1_200..<2_500: return "premium (₹1200-2500)"
        default:          return "splurge (₹2500+)"
        }
    }
}
