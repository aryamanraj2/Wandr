//
//  PlanShapeEvaluationTests.swift
//  WandrTests
//
//  A golden set: real phrasings a host would actually use, each scored on what the
//  plan came back as.
//
//  ## Why this is not fifteen more unit tests
//
//  Unit tests pin one rule each, and every fix so far has passed its own test while
//  breaking something two files away — "3 hours" got fixed and lunch broke, lunch
//  got fixed and the budget broke. What that pattern needs is a *dataset* and an
//  aggregate: a fixed set of realistic inputs, re-run whole after every change, with
//  a pass rate that has to hold. That is the discipline this file implements.
//
//  ## What it does and does not cover
//
//  Everything from the summary to the plan shape — budget basis, stop selection,
//  window handling, invented-constraint detection — is deterministic and runs here.
//
//  The **model call itself is not covered**, and cannot be: extraction needs Apple
//  Intelligence, which the simulator does not have. Apple's `Evaluations` framework
//  (iOS 27) is the right home for scoring the model half — model-as-judge, tool-call
//  trajectories, calibrated metrics — but it is not present in this Xcode beta's
//  SDK (`no such module 'Evaluations'`), so it cannot be adopted yet. Each case
//  below carries the host's own sentence so the same dataset can be replayed against
//  a real extractor the day that lands.
//
//  Until then the contract this file checks is: *given a faithful extraction, does
//  Wandr build the right plan?*
//

import Foundation
import Testing
@testable import Wandr

@Suite("Plan shape evaluation")
struct PlanShapeEvaluationTests {

    // MARK: - The dataset

    /// One host request, and what the plan is required to look like.
    struct GoldenCase: Sendable, CustomStringConvertible {
        /// What the host actually said. Carried so the set can be replayed against a
        /// real extractor once one can run.
        let said: String
        /// What a faithful extractor would return for it.
        let payload: ChatSummaryPayload
        /// The stops the plan must contain, in time order.
        let expectedBands: [SlotBand]
        /// The ceiling per head the brief must work out to, if any.
        let expectedCeilingPerHead: Int?

        var description: String { said }
    }

    private static func payload(
        stops: String? = nil,
        time: String? = nil,
        budget: String? = nil,
        groupSize: Int? = nil,
        vibe: String? = nil,
        area: String? = nil
    ) -> ChatSummaryPayload {
        var p = ChatSummaryPayload()
        p.plannedStops = stops
        p.time = time
        p.budget = budget
        p.groupSize = groupSize
        p.vibe = vibe
        p.area = area
        return p
    }

    /// Fifteen phrasings, chosen to cover the four shapes the app has to support —
    /// one stop, two stops, a whole day, and nothing stated — plus every reported bug.
    static let golden: [GoldenCase] = [
        // — The reports —
        GoldenCase(said: "we just want lunch",
                   payload: payload(stops: "lunch"),
                   expectedBands: [.lunch], expectedCeilingPerHead: nil),

        GoldenCase(said: "lunch for 2, ₹2000",
                   payload: payload(stops: "lunch", budget: "₹2000", groupSize: 2),
                   expectedBands: [.lunch], expectedCeilingPerHead: 1_000),

        GoldenCase(said: "outing, 12:30 to 2, lunch, in CP",
                   payload: payload(stops: "lunch", time: "from 12:30 to 2:00 pm", area: "CP"),
                   expectedBands: [.lunch], expectedCeilingPerHead: nil),

        GoldenCase(said: "we've only got 3 hours",
                   payload: payload(time: "only 3 hours"),
                   expectedBands: [.dinner, .late], expectedCeilingPerHead: nil),

        // — Two stops, nothing in between —
        GoldenCase(said: "lunch and then dinner, nothing else",
                   payload: payload(stops: "lunch and dinner"),
                   expectedBands: [.lunch, .dinner], expectedCeilingPerHead: nil),

        GoldenCase(said: "dinner then drinks",
                   payload: payload(stops: "dinner then drinks"),
                   expectedBands: [.dinner, .late], expectedCeilingPerHead: nil),

        // — One stop, various kinds —
        GoldenCase(said: "just drinks somewhere",
                   payload: payload(stops: "drinks"),
                   expectedBands: [.late], expectedCeilingPerHead: nil),

        GoldenCase(said: "a walk somewhere green",
                   payload: payload(stops: "a walk", vibe: "green"),
                   expectedBands: [.afternoon], expectedCeilingPerHead: nil),

        GoldenCase(said: "some shopping",
                   payload: payload(stops: "shopping"),
                   expectedBands: [.somethingNew], expectedCeilingPerHead: nil),

        // — Budget basis, both readings —
        GoldenCase(said: "dinner, 1500 each",
                   payload: payload(stops: "dinner", budget: "1500 each", groupSize: 4),
                   expectedBands: [.dinner], expectedCeilingPerHead: 1_500),

        GoldenCase(said: "dinner, 4k for all of us",
                   payload: payload(stops: "dinner", budget: "4k for all of us", groupSize: 4),
                   expectedBands: [.dinner], expectedCeilingPerHead: 1_000),

        GoldenCase(said: "drinks, 2k pp",
                   payload: payload(stops: "drinks", budget: "2k pp", groupSize: 3),
                   expectedBands: [.late], expectedCeilingPerHead: 2_000),

        // — A whole day, and nothing stated —
        // Eight hours from the top of the day reaches the 8 pm dinner band but has
        // no room left inside it, so the day ends after the evening activity.
        GoldenCase(said: "we're free all day, make a day of it",
                   payload: payload(time: "the whole day, about 8 hours"),
                   expectedBands: [.lunch, .afternoon, .somethingNew],
                   expectedCeilingPerHead: nil),

        // Nothing named and nothing constrained: one stop per category, each at its
        // latest band — so `food` is dinner, not lunch.
        GoldenCase(said: "let's go out",
                   payload: payload(),
                   expectedBands: [.afternoon, .somethingNew, .dinner, .late],
                   expectedCeilingPerHead: nil),

        // — A window that contradicts the stop —
        GoldenCase(said: "lunch, but we're only free 8 to 9",
                   payload: payload(stops: "lunch", time: "free only 8-9pm"),
                   expectedBands: [.dinner], expectedCeilingPerHead: nil)
    ]

    // MARK: - Scoring

    /// The plan shape one golden case produces, through the whole deterministic chain.
    private func shape(of golden: GoldenCase) throws -> (bands: [SlotBand], ceiling: Int?) {
        let draft = ChatSummaryBriefMapper().draft(from: golden.payload)
        guard case .normalized(let brief) = try BriefNormalizer().normalize(draft) else {
            throw EvaluationGap.briefNeededDetails
        }
        let schedule = SlotSchedule.compute(
            for: brief.timeWindow.value,
            requesting: brief.requestedStops
        )
        return (
            schedule.slots.map(\.band),
            brief.budget.value.ceilingPerHead(for: brief.groupSize.value)
        )
    }

    private enum EvaluationGap: Error { case briefNeededDetails }

    // MARK: - Per-case

    @Test("Every golden request produces the plan it asked for", arguments: golden)
    func goldenCaseProducesTheRightShape(golden: GoldenCase) throws {
        let result = try shape(of: golden)

        #expect(result.bands == golden.expectedBands, "\(golden.said)")
        #expect(result.ceiling == golden.expectedCeilingPerHead, "\(golden.said)")
    }

    // MARK: - Aggregate
    //
    // The number that catches what per-case assertions miss. A change that fixes one
    // phrasing and quietly breaks two others still shows three green ticks and one
    // red; the rate shows the trade.

    @Test("The golden set passes as a whole, not just case by case")
    func aggregatePassRateHolds() throws {
        var passed = 0
        var failures: [String] = []

        for golden in Self.golden {
            let result = try shape(of: golden)
            if result.bands == golden.expectedBands,
               result.ceiling == golden.expectedCeilingPerHead {
                passed += 1
            } else {
                failures.append("\(golden.said) → \(result.bands.map(\.rawValue))")
            }
        }

        #expect(
            passed == Self.golden.count,
            "\(passed)/\(Self.golden.count) golden cases passed. Regressed: \(failures)"
        )
    }

    // MARK: - Guardrails
    //
    // Properties that must hold for *every* case, whatever the plan turns out to be.
    // These are the ones that caught real bugs: a plan is not allowed to be empty, a
    // constraint is not allowed to be invented, and stops may not overlap.

    @Test("No golden request ever produces an empty plan", arguments: golden)
    func noRequestPlansNothing(golden: GoldenCase) throws {
        #expect(!(try shape(of: golden).bands.isEmpty), "\(golden.said) planned nothing at all")
    }

    @Test("No golden request invents a constraint the host did not state", arguments: golden)
    func nothingIsInvented(golden: GoldenCase) throws {
        let draft = ChatSummaryBriefMapper().draft(from: golden.payload)

        if golden.payload.budget == nil {
            #expect(draft.budget == nil, "\(golden.said) invented a budget")
        }
        // Neither of these is ever stated in the set, and both were invented for real
        // hosts by an earlier version of the extractor's prompt.
        #expect(draft.dietary == .unknown, "\(golden.said) invented a dietary need")
        #expect(draft.accessibility == .unknown, "\(golden.said) invented an accessibility need")
    }

    @Test("Stops never overlap, in any golden plan", arguments: golden)
    func stopsNeverOverlap(golden: GoldenCase) throws {
        let draft = ChatSummaryBriefMapper().draft(from: golden.payload)
        guard case .normalized(let brief) = try BriefNormalizer().normalize(draft) else { return }

        let slots = SlotSchedule.compute(
            for: brief.timeWindow.value,
            requesting: brief.requestedStops
        ).slots

        for (earlier, later) in zip(slots, slots.dropFirst()) {
            #expect(earlier.endMinute <= later.startMinute,
                    "\(golden.said): \(earlier.title) runs into \(later.title)")
        }
    }
}
