//
//  GroundedVenue.swift
//  Wandr
//
//  Grounded evidence. The model does not own any of this.
//
//  An option may reach the curation UI only if it carries a stable ID, a source,
//  a retrieval timestamp, a category, a known-or-explicitly-unknown cost, and an
//  availability state. Everything here is an immutable snapshot.
//

import Foundation

// MARK: - Identity

/// A dataset-owned venue identifier. Never a model-created name.
nonisolated struct VenueID: Sendable, Equatable, Hashable, Comparable, CustomStringConvertible {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var description: String { rawValue }
}

/// The slots the current curation UI understands.
nonisolated enum SlotCategory: String, Sendable, Equatable, Hashable, CaseIterable {
    case food
    case sights
    case nightlife
    case discover
}

// MARK: - Provenance

/// Which provider produced a piece of evidence, and at what version.
nonisolated struct EvidenceSource: Sendable, Equatable, Hashable {
    let provider: String
    let version: String

    init(provider: String, version: String) {
        self.provider = provider
        self.version = version
    }

    /// The first and only provider in this slice.
    static func bundledDataset(version: String) -> EvidenceSource {
        EvidenceSource(provider: "bundledDataset", version: version)
    }

    // MapKit, live hours, and route providers are added here later. None of them
    // may block the local demo path.
}

/// Whether the venue can actually be used. Unknown stays unknown through the final UI.
nonisolated enum EvidenceAvailability: Sendable, Equatable, Hashable {
    case available
    case unknown
    case unavailable(reason: String)
}

// MARK: - Cost

/// Venue cost. Either it is known, or it is explicitly not — never guessed.
nonisolated enum VenueCost: Sendable, Equatable, Hashable {
    case unknown
    case known(perHeadRupees: Int, listPriceRupees: Int?)

    var knownPerHeadRupees: Int? {
        switch self {
        case .unknown: return nil
        case .known(let perHead, _): return perHead
        }
    }

    var listPriceRupees: Int? {
        switch self {
        case .unknown: return nil
        case .known(_, let listPrice): return listPrice
        }
    }

    /// "Paisa Vasool" — pure arithmetic, `max(listPrice - perHead, 0)`.
    ///
    /// `nil` when either number is unknown. The model never calculates this.
    var savingsRupees: Int? {
        guard case .known(let perHead, let listPrice) = self, let listPrice else { return nil }
        return max(listPrice - perHead, 0)
    }
}

// MARK: - Tags

/// A tag set the provider either established or didn't.
///
/// The distinction matters: an *absent* vegetarian tag on a venue we surveyed is
/// a contradiction, while an unsurveyed venue is merely unverified. One fails,
/// the other warns.
nonisolated enum EvidenceTags<Tag: Sendable & Hashable & Comparable>: Sendable, Equatable {
    /// The provider never established these tags for this venue.
    case unknown
    /// The provider surveyed these tags. Anything not listed is genuinely absent.
    case known(Set<Tag>)

    /// Sorted for deterministic violation messages.
    var tags: [Tag] {
        switch self {
        case .unknown: return []
        case .known(let set): return set.sorted()
        }
    }

    /// Requirements this venue fails to satisfy, or `nil` when we simply don't know.
    func unsatisfied(by required: [Tag]) -> [Tag]? {
        switch self {
        case .unknown:
            return nil
        case .known(let set):
            return required.filter { !set.contains($0) }.sorted()
        }
    }
}

/// Whether a venue is indoors, outdoors, both, or unsurveyed.
nonisolated enum VenueSetting: String, Sendable, Equatable, Hashable, CaseIterable {
    case indoor
    case outdoor
    case mixed
    case unknown

    /// Whether this venue satisfies an explicit host preference.
    ///
    /// Returns `nil` when the venue's setting was never established — unverified,
    /// not contradicted.
    func satisfies(_ preference: SettingPreference) -> Bool? {
        guard preference.isHardConstraint else { return true }
        switch self {
        case .unknown: return nil
        case .mixed: return true
        case .indoor: return preference == .indoor
        case .outdoor: return preference == .outdoor
        }
    }
}

/// Opening hours as the dataset states them. Live checks are a deferred rule.
nonisolated enum OpeningHours: Sendable, Equatable, Hashable {
    case unknown
    case known(label: String)

    var label: String? {
        if case .known(let label) = self { return label }
        return nil
    }
}

// MARK: - Coordinate

/// A framework-free latitude/longitude pair.
///
/// Deliberately not `CLLocationCoordinate2D`: `Domain/` stays Foundation-only, so
/// the MapKit enricher converts at its own boundary. A coordinate is optional
/// evidence — present means "geocoded", absent means "not established" — and it is
/// the *only* thing MapKit may attach. No hours, no rating, no POI category rides
/// along with it (§5.5).
nonisolated struct VenueCoordinate: Sendable, Equatable, Hashable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

// MARK: - Evidence

/// One immutable venue evidence snapshot.
///
/// Nothing in here is generated by a model. Names, costs, offers, hours, and tags
/// all come from the provider, and the curator may only reference these by `venueID`.
nonisolated struct GroundedVenue: Sendable, Equatable, Identifiable {
    var id: VenueID { venueID }

    let venueID: VenueID
    let name: String
    let category: SlotCategory
    let area: String
    let tagline: String

    let cost: VenueCost

    /// Provider-stated offer text, e.g. "2-for-1 on cocktails". Never model prose,
    /// and never a claim the dataset didn't make. `nil` means no offer was stated.
    let offer: String?
    /// When the offer applies, as the provider labels it. A label only — never
    /// parsed into a `Date`, and never validated against the schedule in this step.
    let offerWindow: String?

    let dietaryTags: EvidenceTags<DietaryRequirement>
    let accessibilityTags: EvidenceTags<AccessibilityRequirement>
    let setting: VenueSetting
    let vibeTags: [String]

    let openWindow: OpeningHours
    let availability: EvidenceAvailability
    /// Provider-stated caveats. These survive into the plan's warnings.
    let limitations: [String]

    let source: EvidenceSource
    let retrievedAt: Date

    /// Deterministic backdrop seed, standing in for venue photography.
    let imageSeed: Int

    /// Best-effort coordinate from the MapKit enricher. `nil` means "not geocoded"
    /// — never a guess. Its presence is the coordinate's own provenance; the venue's
    /// `source` stays `bundledDataset` because the *facts* are still the dataset's.
    let coordinate: VenueCoordinate?

    init(
        venueID: VenueID,
        name: String,
        category: SlotCategory,
        area: String,
        tagline: String = "",
        cost: VenueCost = .unknown,
        offer: String? = nil,
        offerWindow: String? = nil,
        dietaryTags: EvidenceTags<DietaryRequirement> = .unknown,
        accessibilityTags: EvidenceTags<AccessibilityRequirement> = .unknown,
        setting: VenueSetting = .unknown,
        vibeTags: [String] = [],
        openWindow: OpeningHours = .unknown,
        availability: EvidenceAvailability = .unknown,
        limitations: [String] = [],
        source: EvidenceSource,
        retrievedAt: Date,
        imageSeed: Int = 0,
        coordinate: VenueCoordinate? = nil
    ) {
        self.venueID = venueID
        self.name = name
        self.category = category
        self.area = area
        self.tagline = tagline
        self.cost = cost
        self.offer = offer
        self.offerWindow = offerWindow
        self.dietaryTags = dietaryTags
        self.accessibilityTags = accessibilityTags
        self.setting = setting
        self.vibeTags = vibeTags
        self.openWindow = openWindow
        self.availability = availability
        self.limitations = limitations
        self.source = source
        self.retrievedAt = retrievedAt
        self.imageSeed = imageSeed
        self.coordinate = coordinate
    }

    /// Returns a copy with a coordinate attached — the enricher's one mutation.
    /// Every other field is copied verbatim, so the snapshot's facts provably can't
    /// change on the way through MapKit.
    func withCoordinate(_ coordinate: VenueCoordinate?) -> GroundedVenue {
        GroundedVenue(
            venueID: venueID, name: name, category: category, area: area, tagline: tagline,
            cost: cost, offer: offer, offerWindow: offerWindow,
            dietaryTags: dietaryTags, accessibilityTags: accessibilityTags, setting: setting,
            vibeTags: vibeTags, openWindow: openWindow, availability: availability,
            limitations: limitations, source: source, retrievedAt: retrievedAt,
            imageSeed: imageSeed, coordinate: coordinate
        )
    }
}

// MARK: - Reserved evidence contracts

// `RouteEvidence` and `ForecastEvidence` are deliberately absent from this slice.
// MapKit routes and WeatherKit forecasts are deferred rules; defining empty shells
// now would invite faking live data. Their warnings already have a home in
// `PlanWarning`, which is the seam that matters.
