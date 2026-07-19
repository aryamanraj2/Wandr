//
//  CuratorEligibilityTests.swift
//  WandrTests
//
//  Deterministic (§13.1) coverage for the real curator's hard-constraint filter.
//
//  Why this suite exists: the birthday fixture regressed from `.ready` to `.failed`
//  on the first live device-gated run. `FoundationModelsItineraryCurator` was
//  *instructing* the model to respect hard constraints instead of *enforcing* it, so
//  the model picked a venue the dataset surveyed as non-vegetarian and the validator
//  rightly rejected the plan. The fix filters the tool's corpus; this suite pins that
//  fix in the fast tier so a regression is caught in seconds rather than only by a
//  slow run against a live model.
//
//  The rule under test is deliberately asymmetric: surveyed-and-contradicted is
//  excluded, never-surveyed is KEPT (it becomes a validator warning). Tightening it
//  to also drop unknowns would hide the gap and break the baseline's warning rows.
//

import Foundation
import Testing
@testable import Wandr

@Suite("Curator hard-constraint eligibility")
struct CuratorEligibilityTests {

    private typealias Curator = FoundationModelsItineraryCurator

    private let vegetarianBrief = OutingBrief(
        groupSize: .host(GroupSize(clamping: 8)),
        dietary: .required([.vegetarian])
    )

    // MARK: - Dietary

    @Test("A venue surveyed as non-vegetarian is excluded under a vegetarian brief")
    func surveyedContradictionExcluded() {
        // `.known([])` means "we surveyed this venue and it has no vegetarian tag" —
        // a real contradiction, not an unknown. This is the shape of `hk-disc-1`,
        // the venue that broke the birthday fixture live.
        let contradicted = Fixtures.venue("disc-1", category: .discover, dietary: .known([]))
        #expect(Curator.isEligible(contradicted, for: vegetarianBrief) == false)
    }

    @Test("A venue surveyed AS vegetarian is included")
    func surveyedCompliantIncluded() {
        let compliant = Fixtures.venue("food-1", category: .food, dietary: .known([.vegetarian]))
        #expect(Curator.isEligible(compliant, for: vegetarianBrief))
    }

    @Test("A never-surveyed venue is KEPT, so it can become a warning")
    func unsurveyedKept() {
        // The baseline's birthday row depends on this: unsurveyed venues survive
        // curation and the validator turns them into `unverifiedDietary` warnings.
        // Dropping them here would silently shrink the deck and hide the gap.
        let unsurveyed = Fixtures.venue("food-2", category: .food, dietary: .unknown)
        #expect(Curator.isEligible(unsurveyed, for: vegetarianBrief))
    }

    // MARK: - Accessibility

    @Test("Accessibility follows the same surveyed-vs-unknown asymmetry")
    func accessibilityAsymmetry() {
        let brief = OutingBrief(accessibility: .required([.stepFreeEntry]))

        let contradicted = Fixtures.venue("a", category: .food, accessibility: .known([]))
        let compliant = Fixtures.venue("b", category: .food, accessibility: .known([.stepFreeEntry]))
        let unsurveyed = Fixtures.venue("c", category: .food, accessibility: .unknown)

        #expect(Curator.isEligible(contradicted, for: brief) == false)
        #expect(Curator.isEligible(compliant, for: brief))
        #expect(Curator.isEligible(unsurveyed, for: brief))
    }

    // MARK: - Setting

    @Test("An explicit setting preference excludes only a contradicted venue")
    func settingAsymmetry() {
        let brief = OutingBrief(setting: .outdoor)

        #expect(Curator.isEligible(Fixtures.venue("a", category: .food, setting: .indoor), for: brief) == false)
        #expect(Curator.isEligible(Fixtures.venue("b", category: .food, setting: .outdoor), for: brief))
        #expect(Curator.isEligible(Fixtures.venue("c", category: .food, setting: .mixed), for: brief))
        // Never established — unverified, not contradicted.
        #expect(Curator.isEligible(Fixtures.venue("d", category: .food, setting: .unknown), for: brief))
    }

    @Test("A soft setting preference excludes nothing")
    func softSettingExcludesNothing() {
        // `.noPreference` and `.mixed` are not hard constraints, so they must not
        // narrow the corpus the model gets to search.
        for preference in [SettingPreference.noPreference, .mixed] {
            let brief = OutingBrief(setting: preference)
            for venueSetting in [VenueSetting.indoor, .outdoor, .mixed, .unknown] {
                let venue = Fixtures.venue("v", category: .food, setting: venueSetting)
                #expect(Curator.isEligible(venue, for: brief), "\(preference) must not exclude \(venueSetting)")
            }
        }
    }

    // MARK: - No constraints

    @Test("A brief with no hard constraints keeps the whole snapshot")
    func unconstrainedKeepsEverything() {
        let brief = OutingBrief()
        for venue in Fixtures.evidence {
            #expect(Curator.isEligible(venue, for: brief))
        }
    }

    // MARK: - Parity with the fake

    @Test("Everything the fake curator emits is eligible under the real curator's filter")
    func agreesWithFake() async throws {
        // The fake is the no-model double `TravelPlanningServiceTests` runs on, so if
        // the two curators disagree about what a hard constraint excludes, the
        // coordinator suite stops predicting live behaviour and the baseline stops
        // meaning anything. That drift is exactly what let the birthday regression
        // through. Asserted via the fake's PUBLIC `curate` — §7 keeps the fakes
        // unmodified, so its own `isEligible` stays private.
        let briefs = [
            vegetarianBrief,
            OutingBrief(accessibility: .required([.stepFreeEntry])),
            OutingBrief(setting: .outdoor),
            OutingBrief()
        ]

        let venues = Fixtures.evidence + [
            Fixtures.venue("mixed", category: .food, dietary: .unknown, accessibility: .unknown, setting: .unknown),
            Fixtures.venue("veg", category: .food, dietary: .known([.vegetarian])),
            Fixtures.venue("outdoor", category: .sights, setting: .outdoor)
        ]

        let fake = FakeItineraryCurator()

        for brief in briefs {
            let slots = try await fake.curate(brief: brief, evidence: venues)
            let emitted = Set(slots.flatMap(\.candidateVenueIDs))
            let eligible = Set(venues.filter { Curator.isEligible($0, for: brief) }.map(\.venueID))

            // The real filter must not exclude anything the fake was willing to emit.
            #expect(
                emitted.isSubset(of: eligible),
                "Fake emitted venues the real curator's filter would exclude: \(emitted.subtracting(eligible).map(\.rawValue).sorted())"
            )
        }
    }
}
