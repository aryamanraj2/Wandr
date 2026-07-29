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
        if let key = matchedKey(tokens: tokens) {
            return covered.contains(key) ? .covered(key) : .notCovered
        }

        if cityWide.contains(where: { matches($0, tokens: tokens) }) {
            return .everywhere
        }

        return .notCovered
    }

    /// The area a sentence names, in the host's own words, or `nil` when it names none.
    ///
    /// This exists because `area` is the one high-consequence field with nothing but
    /// the model reading it. When a request's area is dropped — swept into
    /// `otherNotes`, most often — the brief falls back to `OutingBrief.defaultArea`,
    /// which is city-wide, so a host who named one neighbourhood silently gets a slate
    /// drawn from all sixteen. The failure is invisible: there is no error, just the
    /// wrong city.
    ///
    /// A neighbourhood is the one thing here Swift can read *better* than the model,
    /// because the set of answers is closed and this file already owns it. Scanning is
    /// the same rule `ChatSummaryBriefMapper.groupSize(inText:)` and
    /// `bandsNamed(inText:)` run under: a fact the host stated plainly must not depend
    /// on which fields a particular generation happened to get right.
    ///
    /// No new vocabulary — it reuses `aliases` and the same whole-token matching as
    /// `coverage(of:in:)`, so an area added to the dataset becomes scannable without
    /// anything here changing. The host's own spelling is returned when it can be
    /// recovered, so Host Review shows them their word rather than our key.
    static func areaNamed(inText raw: String) -> String? {
        let tokens = normalize(raw).split(separator: " ").map(String.init)
        guard !tokens.isEmpty, let key = matchedKey(tokens: tokens) else { return nil }

        // The alias as they wrote it, so "Hauz Khas Village" is not flattened to
        // "hauz khas". Falls back to the canonical key when the original spelling
        // cannot be located — normalization folds punctuation and repeated spaces,
        // and either answer resolves to the same area.
        guard let match = aliasesByLength.first(where: { $0.key == key && matches($0.alias, tokens: tokens) }),
              let range = raw.range(of: match.alias, options: [.caseInsensitive, .diacriticInsensitive])
        else { return key }

        return String(raw[range])
    }

    /// The area whose alias the tokens contain, longest alias first.
    ///
    /// Longest-first *globally* rather than within one area. Grouping by area and
    /// walking the groups in key order meant a two-letter alias of an alphabetically
    /// earlier neighbourhood beat a full name later in the table: "khan market, near
    /// cp" resolved to Connaught Place, because `connaught place` sorts before
    /// `khan market` and `cp` was tried before `khan market` was reached.
    private static func matchedKey(tokens: [String]) -> String? {
        aliasesByLength.first { matches($0.alias, tokens: tokens) }?.key
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
        "nizamuddin":      ["hazrat nizamuddin", "basti nizamuddin", "nizamuddin", "nizam"],
        "vasant kunj":     ["vasant kunj", "vasantkunj", "vk"],
        "greater kailash": ["greater kailash", "greater kailash 1", "greater kailash 2",
                            "gk 1", "gk 2", "gk1", "gk2", "gk"],
        "dwarka":          ["dwarka", "dwaraka", "new dwarka"],
        "noida":           ["greater noida", "noida"],
        "chandni chowk":   ["chandni chowk", "chandni", "old delhi", "purani dilli"],
        "karol bagh":      ["karol bagh", "karolbagh", "kb"],
        "shahpur jat":     ["shahpur jat", "shahpurjat", "sj"],
        "chattarpur":      ["chattarpur", "chhatarpur"]
    ]

    /// Every alias paired with its area, longest-first across the whole table, so a
    /// longer and more specific spelling always wins — "hauz khas village" before
    /// "hauz khas", and "khan market" before another area's "cp".
    ///
    /// Flat rather than grouped by area: see `matchedKey(tokens:)`. Ties break on the
    /// alias then the key so the order is total, and repeated calls cannot disagree.
    private static let aliasesByLength: [(alias: String, key: String)] = aliases
        .flatMap { key, spellings in spellings.map { (alias: $0, key: key) } }
        .sorted {
            ($0.alias.count, $0.alias, $0.key) > ($1.alias.count, $1.alias, $1.key)
        }

    // MARK: Ranking

    /// Deterministic total order: in-budget before over-budget, then cheaper first,
    /// unknown-cost last within its group, and `venueID` as the final tiebreak so
    /// repeated calls with the same brief never reorder.
    private func rank(_ venue: GroundedVenue, for brief: OutingBrief) -> RankKey {
        let perHead = venue.cost.knownPerHeadRupees
        let overBudget: Bool = {
            guard let ceiling = brief.budget.value.ceilingPerHead(for: brief.groupSize.value),
                  let perHead else { return false }
            return perHead > ceiling
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
