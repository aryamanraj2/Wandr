//
//  DistrictVenueProvider.swift
//  Wandr
//
//  The only evidence source in this slice: a bundled Delhi NCR dataset.
//
//  Foundation only. Reading the bundled resource is the single piece of I/O the
//  planning core permits, and it is local and synchronous.
//
//  Two rules this file exists to enforce:
//
//  1. `source` and `retrievedAt` are assigned *here*, at load time. They are never
//     read from the JSON, so a stale or hand-edited dataset cannot claim a false
//     retrieval time.
//  2. A field the JSON never mentions decodes to the domain's "unknown" state, not
//     to an empty-but-known one. `EvidenceTags.known([])` means "we surveyed this
//     venue and it has no such tags" — a real, failing state. `.unknown` merely
//     warns. Collapsing the two would silently downgrade every hard-constraint
//     violation in the app to a warning.
//

import Foundation

// MARK: - Decoding

/// The on-disk shape. Deliberately separate from `GroundedVenue` so the domain
/// type never gains a `Decodable` conformance that could be pointed at untrusted
/// data, and so provenance stays un-decodable by construction.
nonisolated private struct VenueDatasetFile: Decodable {
    let version: String
    let venues: [VenueRecord]
}

nonisolated private struct VenueRecord: Decodable {
    let id: String
    let name: String
    let area: String
    let category: SlotCategory
    let tagline: String?

    let perHead: Int?
    let listPrice: Int?
    let offer: String?
    let offerWindow: String?

    let openWindow: String?
    let dietaryTags: [String]?
    let accessibilityTags: [String]?
    let indoorOutdoor: VenueSetting?
    let vibeTags: [String]?
    let availability: String?
    let unavailableReason: String?
    let limitations: [String]?
    let imageSeed: Int?

    /// Builds the domain snapshot, stamping provenance from the caller rather
    /// than from the file.
    func groundedVenue(source: EvidenceSource, retrievedAt: Date) -> GroundedVenue {
        GroundedVenue(
            venueID: VenueID(id),
            name: name,
            category: category,
            area: area,
            tagline: tagline ?? "",
            cost: Self.cost(perHead: perHead, listPrice: listPrice),
            offer: offer,
            offerWindow: offerWindow,
            dietaryTags: Self.tags(dietaryTags),
            accessibilityTags: Self.tags(accessibilityTags),
            setting: indoorOutdoor ?? .unknown,
            vibeTags: vibeTags ?? [],
            openWindow: openWindow.map { .known(label: $0) } ?? .unknown,
            availability: Self.resolvedAvailability(availability, reason: unavailableReason),
            limitations: limitations ?? [],
            source: source,
            retrievedAt: retrievedAt,
            imageSeed: imageSeed ?? 0
        )
    }

    /// An absent price is `.unknown`, never a guessed number. A list price without
    /// a per-head price is meaningless on its own and is dropped.
    private static func cost(perHead: Int?, listPrice: Int?) -> VenueCost {
        guard let perHead else { return .unknown }
        return .known(perHeadRupees: perHead, listPriceRupees: listPrice)
    }

    /// **Absent → `.unknown`. Present (even empty) → `.known`.** The distinction is
    /// the whole point of `EvidenceTags`; see this file's header.
    private static func tags<Tag: RawRepresentable & Hashable & Comparable & Sendable>(
        _ raw: [String]?
    ) -> EvidenceTags<Tag> where Tag.RawValue == String {
        guard let raw else { return .unknown }
        return .known(Set(raw.compactMap(Tag.init(rawValue:))))
    }

    private static func resolvedAvailability(_ raw: String?, reason: String?) -> EvidenceAvailability {
        switch raw {
        case "available": return .available
        case "unavailable": return .unavailable(reason: reason ?? "The provider lists this place as unavailable.")
        default: return .unknown
        }
    }
}

extension SlotCategory: Decodable {}
extension VenueSetting: Decodable {}

// MARK: - Errors

/// A dataset that cannot be read is a build/packaging fault, not a planning
/// failure the host can act on — so it is deliberately not a `PlanningFailure`.
nonisolated enum VenueDatasetError: Error, CustomStringConvertible {
    case resourceMissing(name: String)
    case undecodable(underlying: String)

    var description: String {
        switch self {
        case .resourceMissing(let name):
            return "Bundled venue dataset '\(name).json' is missing from the app bundle."
        case .undecodable(let underlying):
            return "Bundled venue dataset could not be decoded: \(underlying)"
        }
    }
}

// MARK: - Provider

/// Reads the bundled Delhi NCR dataset once and answers briefs from it.
///
/// Loading is eager and synchronous in `init` — the file is small, local, and the
/// alternative (lazy loading behind an actor) would buy nothing but complexity.
nonisolated struct DistrictVenueProvider: VenueResearching, Sendable {

    static let resourceName = "district-venues-delhi"

    /// Every venue in the dataset, already stamped with provenance and sorted by
    /// `venueID` so the unfiltered snapshot is itself deterministic.
    let allVenues: [GroundedVenue]
    let source: EvidenceSource

    /// - Parameter retrievedAt: when this snapshot was taken. Injected so tests
    ///   get a fixed clock; production passes the current date.
    init(
        bundle: Bundle = .main,
        resourceName: String = DistrictVenueProvider.resourceName,
        retrievedAt: Date = Date()
    ) throws {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw VenueDatasetError.resourceMissing(name: resourceName)
        }

        let file: VenueDatasetFile
        do {
            file = try JSONDecoder().decode(VenueDatasetFile.self, from: Data(contentsOf: url))
        } catch {
            throw VenueDatasetError.undecodable(underlying: String(describing: error))
        }

        let source = EvidenceSource.bundledDataset(version: file.version)
        self.source = source
        self.allVenues = file.venues
            .map { $0.groundedVenue(source: source, retrievedAt: retrievedAt) }
            .sorted { $0.venueID < $1.venueID }
    }

    // MARK: Research

    /// Returns the venues worth considering for this brief.
    ///
    /// Area is a *filter* — a host who named a neighbourhood gets that neighbourhood,
    /// and a thin one legitimately produces thin evidence for the validator to reject.
    /// Budget is only a *sort*: nothing is ever dropped for price, because the
    /// validator is the one component allowed to rule a venue out, and it says so
    /// with a named violation rather than a silent omission.
    func research(for brief: OutingBrief) async throws -> VenueResearchResult {
        let matched = venues(in: brief.area.value)
        let ranked = matched.sorted { rank($0, for: brief) < rank($1, for: brief) }

        var events: [PlanningEvent] = [
            PlanningEvent(
                timestamp: allVenues.first?.retrievedAt ?? Date(),
                phase: .researching,
                title: "Searched the bundled Delhi NCR dataset",
                // Counts and category names only. The brief's area is host-derived
                // text, so it deliberately does not appear in an event.
                detail: "\(ranked.count) grounded option\(ranked.count == 1 ? "" : "s") found.",
                severity: .info
            )
        ]

        // Naming a thin category here — before the validator runs — is what makes
        // the eventual failure message specific rather than "something went wrong".
        let thin = SlotCategory.allCases
            .filter { category in ranked.count { $0.category == category } < 3 }
            .map(\.rawValue)

        if !thin.isEmpty {
            events.append(
                PlanningEvent(
                    timestamp: allVenues.first?.retrievedAt ?? Date(),
                    phase: .researching,
                    title: "Some categories are thin here",
                    detail: "Fewer than three options for: \(thin.joined(separator: ", ")).",
                    severity: .limitation
                )
            )
        }

        return VenueResearchResult(venues: ranked, events: events)
    }

    // MARK: Area matching

    /// Venues in the named area, or everything when the area is the catch-all
    /// default or a place this dataset has never heard of.
    ///
    /// Falling back to the whole dataset for an unrecognised area is deliberate:
    /// an unknown neighbourhood should widen the search, not silently return
    /// nothing and masquerade as "we found no venues".
    func venues(in area: String) -> [GroundedVenue] {
        let normalized = Self.canonicalArea(area)

        guard normalized != Self.everywhere else { return allVenues }

        let matches = allVenues.filter { Self.canonicalArea($0.area) == normalized }
        return matches.isEmpty ? allVenues : matches
    }

    private static let everywhere = "delhi ncr"

    /// Folds the handful of spellings the demo script actually uses onto one key.
    private static func canonicalArea(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case "cp", "connaught place", "cannaught place": return "connaught place"
        case "hauz khas", "hauz khaz", "hkv": return "hauz khas"
        case "lodhi", "lodi", "lodhi colony", "lodhi road": return "lodhi"
        case "cyberhub", "cyber hub", "gurgaon", "gurugram": return "cyberhub"
        case "saket": return "saket"
        case "aerocity", "aero city": return "aerocity"
        case "nizamuddin", "hazrat nizamuddin", "nizam": return "nizamuddin"
        default: return trimmed
        }
    }

    // MARK: Ranking

    /// Deterministic total order: in-budget before over-budget, then cheaper first,
    /// unknown-cost last within its group, and `venueID` as the final tiebreak so
    /// repeated calls with the same brief never reorder.
    private func rank(_ venue: GroundedVenue, for brief: OutingBrief) -> RankKey {
        let perHead = venue.cost.knownPerHeadRupees
        let overBudget: Bool = {
            guard let limit = brief.budgetPerHead.value.limitRupees, let perHead else { return false }
            return perHead > limit
        }()

        return RankKey(
            overBudget: overBudget,
            costUnknown: perHead == nil,
            perHead: perHead ?? Int.max,
            venueID: venue.venueID.rawValue
        )
    }

    private struct RankKey: Comparable {
        let overBudget: Bool
        let costUnknown: Bool
        let perHead: Int
        let venueID: String

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.overBudget != rhs.overBudget { return !lhs.overBudget }
            if lhs.costUnknown != rhs.costUnknown { return !lhs.costUnknown }
            if lhs.perHead != rhs.perHead { return lhs.perHead < rhs.perHead }
            return lhs.venueID < rhs.venueID
        }
    }
}
