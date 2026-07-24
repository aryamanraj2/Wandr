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

        // A named area this dataset has never heard of is reported, not absorbed.
        // Widening to the whole city here is what produced the worst failure this
        // provider had: a host who asked for one neighbourhood got a slate drawn
        // from every *other* neighbourhood, ranked by price, with nothing anywhere
        // in the app saying the area had been dropped.
        let coverage = Self.coverage(of: brief.area.value, in: coveredAreaKeys)
        guard coverage != .notCovered else {
            throw PlanningFailure(.areaNotCovered(covered: coveredAreaNames))
        }

        let matched = venues(for: coverage)
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

    /// What an area string means to *this* dataset.
    nonisolated enum AreaCoverage: Sendable, Equatable {
        /// No area was named, or the one named covers the whole city.
        case everywhere
        /// A neighbourhood the dataset holds, as its canonical key.
        case covered(String)
        /// A real place the dataset has nothing for.
        case notCovered
    }

    /// The canonical key of every area the dataset actually holds.
    var coveredAreaKeys: Set<String> {
        Set(allVenues.map { Self.normalize($0.area) })
    }

    /// Those areas as the host would read them, alphabetically. Dataset-owned text,
    /// so it is safe to put in a failure message.
    var coveredAreaNames: [String] {
        Set(allVenues.map(\.area)).sorted()
    }

    /// Venues in the named area, or everything when the area covers the whole city.
    ///
    /// Empty for an area the dataset does not hold. `research(for:)` turns that into
    /// a named failure — callers that use this directly get the honest empty answer
    /// rather than a silent city-wide substitution.
    func venues(in area: String) -> [GroundedVenue] {
        venues(for: Self.coverage(of: area, in: coveredAreaKeys))
    }

    private func venues(for coverage: AreaCoverage) -> [GroundedVenue] {
        switch coverage {
        case .everywhere:
            return allVenues
        case .covered(let key):
            return allVenues.filter { Self.normalize($0.area) == key }
        case .notCovered:
            return []
        }
    }

    /// Resolves a host-written area onto the dataset.
    ///
    /// Matching is by *token run*, not whole-string equality. The extractor rarely
    /// returns a bare "CP" — it returns what the host said, so "Connaught Place, New
    /// Delhi" and "the CP area" have to land on the same key. Whole-string equality
    /// missed every one of those and fell through to the city-wide branch.
    static func coverage(of raw: String, in covered: Set<String>) -> AreaCoverage {
        let normalized = normalize(raw)
        guard !normalized.isEmpty else { return .everywhere }

        let tokens = normalized.split(separator: " ").map(String.init)

        // Specific neighbourhoods win over city-wide words, so "Khan Market, New
        // Delhi" is Khan Market rather than all of Delhi.
        for (key, aliases) in aliasesByLength {
            for alias in aliases where matches(alias, tokens: tokens) {
                return covered.contains(key) ? .covered(key) : .notCovered
            }
        }

        if cityWide.contains(where: { matches($0, tokens: tokens) }) {
            return .everywhere
        }

        return .notCovered
    }

    /// Whether `alias` appears as a contiguous run of whole tokens.
    ///
    /// Whole tokens, never substrings — "cp" must not match inside "campus". A short
    /// alias is additionally rejected when a number sits in front of it, because that
    /// is the one way these collide with something else the host might mean: "km" is
    /// Khan Market on its own and kilometres in "5 km from CP".
    private static func matches(_ alias: String, tokens: [String]) -> Bool {
        let aliasTokens = alias.split(separator: " ").map(String.init)
        guard !aliasTokens.isEmpty, aliasTokens.count <= tokens.count else { return false }

        for start in 0...(tokens.count - aliasTokens.count)
        where Array(tokens[start..<(start + aliasTokens.count)]) == aliasTokens {
            let usedAsAUnit = alias.count <= 2
                && start > 0
                && tokens[start - 1].allSatisfy(\.isNumber)
            if !usedAsAUnit { return true }
        }
        return false
    }

    /// Lowercased, unaccented, punctuation-free, single-spaced.
    private static func normalize(_ raw: String) -> String {
        raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { result, character in
                if character == " ", result.last == " " || result.isEmpty { return }
                result.append(character)
            }
            .trimmingCharacters(in: .whitespaces)
    }

    /// Words that name the whole coverage area rather than a neighbourhood in it.
    private static let cityWide: [String] = [
        "delhi ncr", "delhi", "new delhi", "ncr", "national capital region",
        "anywhere", "any area", "no preference", "flexible"
    ]

    /// Spellings that fold onto one dataset area. The key is the normalized form of
    /// the `area` string in the JSON, so adding a neighbourhood to the dataset only
    /// needs an entry here if the host might spell it differently.
    private static let aliases: [String: [String]] = [
        "connaught place": ["connaught place", "cannaught place", "canaught place",
                            "connaught", "rajiv chowk", "cp"],
        "hauz khas":       ["hauz khas village", "hauz khas", "hauz khaz", "hauzkhas", "hkv"],
        "khan market":     ["khan market", "khan mkt", "khan", "km"],
        "lodhi":           ["lodhi art district", "lodhi colony", "lodhi road",
                            "lodhi", "lodi colony", "lodi"],
        "cyberhub":        ["dlf cyber hub", "cyber hub", "cyberhub", "cyber city",
                            "cybercity", "gurugram", "gurgaon"],
        "saket":           ["select citywalk", "select city walk", "saket"],
        "aerocity":        ["aerocity", "aero city", "worldmark"],
        "nizamuddin":      ["hazrat nizamuddin", "basti nizamuddin", "nizamuddin", "nizam"]
    ]

    /// Aliases longest-first inside each area, so "hauz khas village" is tried before
    /// "hauz khas" and a longer, more specific spelling always wins.
    private static let aliasesByLength: [(String, [String])] = aliases
        .map { ($0.key, $0.value.sorted { $0.count > $1.count }) }
        .sorted { $0.0 < $1.0 }

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
