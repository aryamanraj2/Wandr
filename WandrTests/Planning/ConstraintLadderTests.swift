//
//  ConstraintLadderTests.swift
//  WandrTests
//
//  The rule that replaced "the run dies".
//
//  Two things are pinned here and neither is negotiable: constraints are given up
//  in ascending order of how much the host cared about them, and dietary and
//  accessibility are never given up at all.
//

import Foundation
import Testing
@testable import Wandr

@Suite("Constraint ladder")
struct ConstraintLadderTests {

    // MARK: - Ordering

    @Test("A constraint the host never set is not on the ladder")
    func unsetConstraintsAreAbsent() {
        let rungs = ConstraintLadder.rungs(for: Fixtures.sparseBrief)
        #expect(rungs.isEmpty, "Nothing was stated, so there is nothing to give up")
    }

    @Test("Only the constraints that actually bind appear")
    func onlyBindingConstraintsAppear() {
        let brief = OutingBrief(
            timeWindow: .host(OutingTimeWindow(latestEndMinute: 21 * 60)),
            groupSize: .host(GroupSize(clamping: 4)),
            budget: .host(.total(rupees: 4_000))
        )

        #expect(Set(ConstraintLadder.rungs(for: brief)) == [.budget, .timeWindow])
    }

    /// The whole point of using `Sourced` as the weight: a number Wandr invented is
    /// cheaper to give up than an hour the host actually said out loud, even though
    /// budget outranks time on the product ordering.
    @Test("A Wandr-defaulted value gives way before anything the host stated")
    func provenanceOutranksProductOrder() {
        let brief = OutingBrief(
            timeWindow: .host(OutingTimeWindow(latestEndMinute: 21 * 60)),
            groupSize: .host(GroupSize(clamping: 4)),
            budget: .safeDefault(.total(rupees: 4_000))
        )

        #expect(ConstraintLadder.rungs(for: brief) == [.budget, .timeWindow])
    }

    @Test("Between two host-stated constraints, the product ordering decides")
    func productOrderBreaksTies() {
        let brief = OutingBrief(
            timeWindow: .host(OutingTimeWindow(latestEndMinute: 21 * 60)),
            groupSize: .host(GroupSize(clamping: 4)),
            budget: .host(.total(rupees: 4_000)),
            setting: .outdoor,
            requestedStops: [.lunch]
        )

        // Setting is the softest thing on the list; the stop they named is the last
        // thing to go.
        #expect(ConstraintLadder.rungs(for: brief) == [.setting, .budget, .timeWindow, .requestedStops])
    }

    /// Vibe tags have never filtered a venue, only ranked one. A rung for them would
    /// claim a compromise the host never actually made.
    @Test("Vibe is not a rung, because giving it up removes nothing")
    func vibeIsNotRelaxable() {
        #expect(!RelaxableConstraint.allCases.contains { $0.rawValue == "vibe" })
    }
}

@Suite("Evidence resolver")
struct EvidenceResolverTests {

    private let resolver = EvidenceResolver()

    /// A ₹50-a-head ceiling against a dataset whose cheapest restaurant is dearer.
    ///
    /// The figure has to stay under the dataset's cheapest food venue or this stops
    /// testing relaxation. It was ₹200 until street-food entries at ₹100 landed.
    /// Before the ladder this ended the run; the host got a Try again button that
    /// could only ever produce the same dead end.
    @Test("An unmeetable budget is given up, and the giving-up is disclosed")
    func unmeetableBudgetIsRelaxedAndDisclosed() throws {
        let resolution = resolver.resolve(
            brief: Fixtures.impossibleBudgetBrief,
            evidence: Fixtures.evidence
        )

        #expect(!resolution.eligible.isEmpty)
        #expect(resolution.eligible.contains { $0.category == .food })

        let given = try #require(resolution.relaxations.first { $0.constraint == .budget })
        #expect(given.disclosure.contains("₹50"))
    }

    @Test("A budget everything already meets is never reported as given up")
    func metBudgetIsNotRelaxed() {
        let resolution = resolver.resolve(
            brief: Fixtures.afterWorkBrief,
            evidence: Fixtures.evidence
        )

        #expect(resolution.relaxations.isEmpty)
        // And it still filtered: nothing over the ceiling survives when it didn't
        // have to.
        let ceiling = Fixtures.afterWorkBrief.budget.value
            .ceilingPerHead(for: Fixtures.afterWorkBrief.groupSize.value)
        #expect(resolution.eligible.allSatisfy { venue in
            guard let ceiling, let perHead = venue.cost.knownPerHeadRupees else { return true }
            return perHead <= ceiling
        })
    }

    /// The line that must never move. Relaxing these is not a degraded plan — it is
    /// sending someone to a restaurant they cannot eat at or a door they cannot use.
    @Test("Dietary and accessibility are never given up, even when nothing is left")
    func hardConstraintsAreNeverRelaxed() {
        let brief = OutingBrief(
            groupSize: .host(GroupSize(clamping: 4)),
            budget: .host(.perHead(rupees: 100)),
            dietary: .required([.vegan]),
            accessibility: .required([.stepFreeEntry])
        )
        // Evidence that provably fails both.
        let evidence = [
            Fixtures.venue("meat-only", category: .food, perHead: 200,
                           dietary: .known([]), accessibility: .known([]))
        ]

        let resolution = resolver.resolve(brief: brief, evidence: evidence)

        #expect(resolution.eligible.isEmpty, "No ladder rung may put these back")
        #expect(!resolution.relaxations.contains { $0.constraint == .budget },
                "A rung that changed nothing is not a compromise worth claiming")
    }

    @Test("Two stops of one category never draw the same venue")
    func sameCategoryStopsDoNotShareAVenue() async throws {
        // "lunch and snacks" in a neighbourhood with a handful of restaurants. Both
        // stops are `.food`, so both decks are built from the identical pool — and
        // nothing used to stop the same place landing in both. Rule 3 then failed the
        // whole run with "The same place was picked for two different stops", which
        // is Wandr's own bug reported as if the model had misbehaved.
        let brief = OutingBrief(
            groupSize: .host(GroupSize(clamping: 5)),
            budget: .host(.perHead(rupees: 1_500)),
            requestedStops: [.lunch, .dinner]
        )
        let evidence = (1...4).map {
            Fixtures.venue("food-\($0)", category: .food, perHead: 500 + $0 * 100)
        }

        let slots = try await FakeItineraryCurator().curate(brief: brief, evidence: evidence)
        #expect(slots.count == 2, "Lunch and dinner are both asked for")

        let used = slots.flatMap(\.candidateVenueIDs)
        #expect(Set(used).count == used.count, "No venue may appear in both stops")

        // And the run survives the validator that reported this to the host.
        _ = try FeasibilityValidator().validate(
            brief: brief,
            evidence: evidence,
            slots: slots,
            runID: Fixtures.runID,
            now: Fixtures.now
        )
    }

    @Test("Relaxation stops as soon as the plan is possible")
    func relaxationIsMinimal() {
        // Outdoor-only *and* a tight budget. Dropping the setting alone is enough,
        // so the budget must survive.
        let brief = OutingBrief(
            groupSize: .host(GroupSize(clamping: 2)),
            budget: .host(.total(rupees: 4_000)),
            setting: .outdoor
        )
        let evidence = SlotCategory.allCases.flatMap { category in
            [Fixtures.venue("\(category.rawValue)-indoor", category: category,
                            perHead: 500, setting: .indoor)]
        }

        let resolution = resolver.resolve(brief: brief, evidence: evidence)

        #expect(resolution.relaxations.map(\.constraint) == [.setting])
        #expect(!resolution.eligible.isEmpty)
    }
}
