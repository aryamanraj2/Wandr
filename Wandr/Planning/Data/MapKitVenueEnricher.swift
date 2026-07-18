//
//  MapKitVenueEnricher.swift
//  Wandr
//
//  A `VenueResearching` DECORATOR that best-effort attaches real coordinates to
//  dataset venues via MapKit. The only file in the app that may `import MapKit`.
//
//  The contract (§11) is "helpful when it works, invisible when it doesn't":
//  - It wraps `DistrictVenueProvider`, calls it, then attaches coordinates. The
//    dataset still decides which venues exist; MapKit may only attach a lat/long.
//  - Resolution is conservative: an ambiguous or failed match leaves `coordinate`
//    nil rather than guessing. Nothing but the coordinate is ever copied from
//    MapKit — no hours, no rating, no POI category (§5.5).
//  - Bounded parallelism under an overall time budget. On timeout it returns what
//    resolved so far; the pipeline feels the same speed with MapKit misbehaving.
//  - On ANY failure (error, no network, rate limit, timeout) the venues pass
//    through with whatever resolved, plus exactly ONE fixed-string limitation
//    event. Never a `PlanningFailure`, never a changed terminal state.
//  - Per-session in-memory cache by `VenueID`, so replans don't re-geocode.
//  - The geocoding is behind an injectable seam so the logic is testable without
//    live MapKit.
//
//  This is the designated cut line (§15): drop it and the pipeline ships without
//  coordinates and loses nothing but the map flourish — which is exactly why it is
//  a decorator and not a provider rewrite.
//

import Foundation
import MapKit

// MARK: - Geocoding seam

/// Resolves a single venue's coordinate, or `nil` when the match is ambiguous or
/// absent. Foundation-only in signature so the deterministic tier can stub it.
nonisolated protocol VenueGeocoding: Sendable {
    func coordinate(for venue: GroundedVenue) async throws -> VenueCoordinate?
}

// MARK: - Enricher

/// The decorator. A `Sendable` struct; its only mutable state is an actor-isolated
/// per-session cache.
nonisolated struct MapKitVenueEnricher: VenueResearching, Sendable {

    private let base: any VenueResearching
    private let geocoder: any VenueGeocoding
    private let timeBudget: Duration
    private let maxConcurrency: Int
    private let cache: CoordinateCache
    private let now: @Sendable () -> Date

    /// The single, fixed limitation sentence. No venue text, no error text.
    static let limitationTitle = "Map locations couldn't all be verified"
    static let limitationDetail = "Some places on this plan don't have a confirmed map location."

    init(
        base: any VenueResearching,
        geocoder: any VenueGeocoding = MapKitGeocoder(),
        timeBudget: Duration = .seconds(3),
        maxConcurrency: Int = 4,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.base = base
        self.geocoder = geocoder
        self.timeBudget = timeBudget
        self.maxConcurrency = max(1, maxConcurrency)
        self.cache = CoordinateCache()
        self.now = now
    }

    func research(for brief: OutingBrief) async throws -> VenueResearchResult {
        // The dataset call is the source of truth. If it throws, that's a real
        // research failure — we do not swallow it.
        let researched = try await base.research(for: brief)

        // Enrichment is best-effort and never throws.
        let (venues, degraded) = await enrich(researched.venues)

        var events = researched.events
        if degraded {
            events.append(
                PlanningEvent(
                    timestamp: now(),
                    phase: .researching,
                    title: Self.limitationTitle,
                    detail: Self.limitationDetail,
                    severity: .limitation
                )
            )
        }

        return VenueResearchResult(venues: venues, events: events)
    }

    // MARK: - Enrichment

    /// Attaches coordinates best-effort. Returns the (possibly partly) enriched
    /// venues and whether anything degraded (an error or the time budget expiring),
    /// which is what earns the single limitation event.
    func enrich(_ venues: [GroundedVenue]) async -> (venues: [GroundedVenue], degraded: Bool) {
        guard !venues.isEmpty else { return (venues, false) }

        let deadline = ContinuousClock.now.advanced(by: timeBudget)
        var resolved: [VenueID: VenueCoordinate?] = [:]
        var degraded = false

        // Cache first — a replan pays nothing.
        for venue in venues {
            if let cached = await cache.lookup(venue.venueID) {
                resolved[venue.venueID] = cached
            }
        }

        let pending = venues.filter { resolved[$0.venueID] == nil && $0.coordinate == nil }

        var index = 0
        while index < pending.count {
            if ContinuousClock.now >= deadline {
                // Ran out of budget before finishing — that's a degradation, and the
                // unprocessed venues stay nil.
                degraded = true
                break
            }

            let end = min(index + maxConcurrency, pending.count)
            let chunk = Array(pending[index..<end])

            let outcomes = await withTaskGroup(
                of: (VenueID, VenueCoordinate?, Bool).self
            ) { group -> [(VenueID, VenueCoordinate?, Bool)] in
                for venue in chunk {
                    group.addTask {
                        do {
                            return (venue.venueID, try await self.geocoder.coordinate(for: venue), false)
                        } catch {
                            // Any per-venue error is a degradation, not a crash.
                            return (venue.venueID, nil, true)
                        }
                    }
                }
                var collected: [(VenueID, VenueCoordinate?, Bool)] = []
                for await outcome in group { collected.append(outcome) }
                return collected
            }

            for (id, coordinate, failed) in outcomes {
                resolved[id] = coordinate
                await cache.store(id, coordinate)
                if failed { degraded = true }
            }

            index = end
        }

        let enriched = venues.map { venue -> GroundedVenue in
            if case let .some(.some(coordinate)) = resolved[venue.venueID] {
                return venue.withCoordinate(coordinate)
            }
            return venue
        }

        return (enriched, degraded)
    }
}

// MARK: - Per-session cache

/// In-memory, per-app-session coordinate cache keyed by `VenueID`. A resolved entry
/// (present, even when its value is `nil`) is a "we already looked" marker, so a
/// known no-match isn't re-geocoded either.
private actor CoordinateCache {
    private var store: [VenueID: VenueCoordinate?] = [:]

    /// Outer optional = "have we looked?"; inner = the coordinate, if any.
    func lookup(_ id: VenueID) -> VenueCoordinate?? { store[id] }

    func store(_ id: VenueID, _ coordinate: VenueCoordinate?) { store[id] = coordinate }
}

// MARK: - Live MapKit geocoder

/// The production seam: an `MKLocalSearch` per venue, region-biased to Delhi NCR,
/// accepting only a plausible top-result match. Not unit-tested (that's the stub's
/// job); its live behaviour is verified by hand on the demo device.
nonisolated struct MapKitGeocoder: VenueGeocoding {

    /// Delhi NCR bias, so a common venue name resolves near the demo's city rather
    /// than a namesake elsewhere.
    static let region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 28.6139, longitude: 77.2090),
        span: MKCoordinateSpan(latitudeDelta: 1.6, longitudeDelta: 1.6)
    )

    func coordinate(for venue: GroundedVenue) async throws -> VenueCoordinate? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "\(venue.name), \(venue.area), Delhi"
        request.region = Self.region

        let response = try await MKLocalSearch(request: request).start()

        guard let match = response.mapItems.first, Self.isPlausible(match, for: venue) else {
            return nil
        }

        let coordinate = match.placemark.coordinate
        // A zero coordinate is MapKit's "no location", not the Gulf of Guinea.
        guard CLLocationCoordinate2DIsValid(coordinate),
              !(coordinate.latitude == 0 && coordinate.longitude == 0) else {
            return nil
        }

        return VenueCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    /// Conservative name check: the match's name must share meaningful overlap with
    /// the venue's. When in doubt, reject — a nil coordinate is honest, a wrong pin
    /// is not.
    private static func isPlausible(_ item: MKMapItem, for venue: GroundedVenue) -> Bool {
        guard let matchName = item.name?.lowercased() else { return false }
        let venueName = venue.name.lowercased()
        if matchName.contains(venueName) || venueName.contains(matchName) { return true }

        // Otherwise require a shared significant word (length > 3), so "Social" alone
        // doesn't match "Social Media Cafe" across town.
        let significant: (String) -> Set<String> = { name in
            Set(name.split { !$0.isLetter }.map(String.init).filter { $0.count > 3 })
        }
        return !significant(matchName).isDisjoint(with: significant(venueName))
    }
}
