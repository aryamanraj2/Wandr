//
//  MapKitVenueEnricherTests.swift
//  WandrTests
//
//  §13.1 deterministic tier for the enricher, exercised entirely through the
//  injectable geocoding seam — no live MapKit, so this suite is green on any Mac.
//  It asserts the enricher's whole contract: attach on a clean match, leave nil on
//  ambiguity/failure, emit exactly one limitation event when degraded, never touch
//  a venue's facts, never change a terminal state, and never re-geocode a cached ID.
//

import Foundation
import Testing
@testable import Wandr

@Suite("MapKit venue enricher")
struct MapKitVenueEnricherTests {

    // MARK: - Test doubles

    /// A `VenueResearching` base with fixed venues and one event.
    private struct StubResearcher: VenueResearching {
        let venues: [GroundedVenue]
        func research(for brief: OutingBrief) async throws -> VenueResearchResult {
            VenueResearchResult(
                venues: venues,
                events: [PlanningEvent(timestamp: Fixtures.retrievedAt, phase: .researching, title: "base event")]
            )
        }
    }

    /// A geocoder whose behaviour each test dials in, counting its calls so the
    /// cache can be proven.
    private final class StubGeocoder: VenueGeocoding, @unchecked Sendable {
        enum Behaviour: Sendable { case coordinate(VenueCoordinate?), throwsError }
        let behaviour: Behaviour
        private let lock = NSLock()
        private(set) var callCount = 0
        private(set) var seenIDs: [String] = []

        init(_ behaviour: Behaviour) { self.behaviour = behaviour }

        func coordinate(for venue: GroundedVenue) async throws -> VenueCoordinate? {
            lock.lock(); callCount += 1; seenIDs.append(venue.venueID.rawValue); lock.unlock()
            switch behaviour {
            case .coordinate(let c): return c
            case .throwsError: throw StubError.boom
            }
        }
    }

    private enum StubError: Error { case boom }

    private static let delhi = VenueCoordinate(latitude: 28.55, longitude: 77.19)

    private func venues(_ ids: [String]) -> [GroundedVenue] {
        ids.map { Fixtures.venue($0, category: .food, perHead: 900) }
    }

    // MARK: - Clean match

    @Test("An unambiguous match attaches the coordinate and adds no limitation event")
    func attachesOnMatch() async {
        let enricher = MapKitVenueEnricher(
            base: StubResearcher(venues: venues(["food-1", "food-2"])),
            geocoder: StubGeocoder(.coordinate(Self.delhi)),
            now: { Fixtures.now }
        )

        let result = try! await enricher.research(for: Fixtures.afterWorkBrief)

        #expect(result.venues.allSatisfy { $0.coordinate == Self.delhi })
        // Only the base event — no degradation.
        #expect(result.events.count == 1)
        #expect(!result.events.contains { $0.severity == .limitation })
    }

    // MARK: - Ambiguous / no match

    @Test("A nil (ambiguous) match leaves the coordinate nil and does not degrade")
    func nilOnAmbiguity() async {
        let enricher = MapKitVenueEnricher(
            base: StubResearcher(venues: venues(["food-1"])),
            geocoder: StubGeocoder(.coordinate(nil)),
            now: { Fixtures.now }
        )
        let result = try! await enricher.research(for: Fixtures.afterWorkBrief)

        #expect(result.venues.allSatisfy { $0.coordinate == nil })
        // A clean "no match" is normal, not a failure — no limitation event.
        #expect(!result.events.contains { $0.severity == .limitation })
    }

    // MARK: - Failure

    @Test("A geocoder error yields exactly one limitation event, venues passing through unenriched")
    func oneLimitationOnFailure() async {
        let enricher = MapKitVenueEnricher(
            base: StubResearcher(venues: venues(["food-1", "food-2", "food-3"])),
            geocoder: StubGeocoder(.throwsError),
            now: { Fixtures.now }
        )
        let result = try! await enricher.research(for: Fixtures.afterWorkBrief)

        #expect(result.venues.allSatisfy { $0.coordinate == nil })
        let limitations = result.events.filter { $0.severity == .limitation }
        #expect(limitations.count == 1)
        // Fixed string, no venue text.
        #expect(limitations.first?.title == MapKitVenueEnricher.limitationTitle)
        // Bind before asserting. Written inline as
        // `#expect(!(limitations.first?.detail ?? "").contains("food-1"))` the prefix
        // `!` binds across the parenthesized `??` in a way the macro reports as
        // "<not evaluated>", and the expectation fails even though the detail plainly
        // contains no venue text. Keep the subject in a local.
        let detail = limitations.first?.detail ?? ""
        #expect(detail == MapKitVenueEnricher.limitationDetail)
        // The rule that matters: the fixed sentence names no venue.
        #expect(detail.contains("food-1") == false)
    }

    @Test("A MapKit failure never becomes a PlanningFailure")
    func failureIsNeverThrown() async {
        let enricher = MapKitVenueEnricher(
            base: StubResearcher(venues: venues(["food-1"])),
            geocoder: StubGeocoder(.throwsError),
            now: { Fixtures.now }
        )
        // Must not throw.
        let result = try? await enricher.research(for: Fixtures.afterWorkBrief)
        #expect(result != nil)
    }

    // MARK: - Facts untouched

    @Test("Enrichment changes only the coordinate — every other venue fact is identical")
    func factsUntouched() async {
        let original = venues(["food-1"])
        let enricher = MapKitVenueEnricher(
            base: StubResearcher(venues: original),
            geocoder: StubGeocoder(.coordinate(Self.delhi)),
            now: { Fixtures.now }
        )
        let enriched = try! await enricher.research(for: Fixtures.afterWorkBrief).venues.first!
        let before = original.first!

        #expect(enriched.withCoordinate(nil) == before) // strip the one added field → identical
        #expect(enriched.name == before.name)
        #expect(enriched.cost == before.cost)
        #expect(enriched.dietaryTags == before.dietaryTags)
    }

    // MARK: - Cache

    @Test("A repeated venue ID is geocoded once — the per-session cache serves the rest")
    func cacheAvoidsRegeocode() async {
        let geocoder = StubGeocoder(.coordinate(Self.delhi))
        let enricher = MapKitVenueEnricher(
            base: StubResearcher(venues: venues(["food-1", "food-2"])),
            geocoder: geocoder,
            now: { Fixtures.now }
        )

        _ = try! await enricher.research(for: Fixtures.afterWorkBrief)
        let afterFirst = geocoder.callCount
        #expect(afterFirst == 2)

        // A replan over the same IDs re-geocodes nothing.
        _ = try! await enricher.research(for: Fixtures.afterWorkBrief)
        #expect(geocoder.callCount == afterFirst)
    }

    // MARK: - Terminal state indifference

    @Test("Whether or not a coordinate is present, the validator produces the same plan")
    func validatorIndifferentToCoordinate() throws {
        let plain = Fixtures.evidence
        let pinned = plain.map { $0.withCoordinate(Self.delhi) }

        let validator = FeasibilityValidator()
        let a = try validator.validate(brief: Fixtures.afterWorkBrief, evidence: plain, slots: Fixtures.validSlots, runID: Fixtures.runID, now: Fixtures.now)
        let b = try validator.validate(brief: Fixtures.afterWorkBrief, evidence: pinned, slots: Fixtures.validSlots, runID: Fixtures.runID, now: Fixtures.now)

        #expect(a.warnings == b.warnings)
        #expect(a.slots == b.slots)
        #expect(a.evidenceIDs == b.evidenceIDs)
    }
}
