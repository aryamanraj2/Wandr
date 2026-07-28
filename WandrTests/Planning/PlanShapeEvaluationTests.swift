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
//  The **model call itself is not covered here** — but the two reasons recorded for
//  that were both checked and both were wrong:
//
//    1. "`Evaluations` is not in this SDK (`no such module`)." It is. It ships as a
//       *Developer* framework under `Platforms/*.platform/Developer/Library/
//       Frameworks`, next to XCTest, so a plain `-sdk` probe cannot see it and
//       reports exactly that error. With the developer framework search path it
//       imports and typechecks.
//    2. "The simulator does not have Apple Intelligence." It runs live inference
//       using the *host Mac's* model. `SystemLanguageModel.default.availability`
//       reports `.available` on this machine.
//
//  So the model half is coverable, and this file's design — a hand-written
//  `expectedBands` per case — is a deliberate leftover rather than a constraint.
//  Replacing it with invariant-scored samples is a separate, planned change; each
//  case already carries the host's own sentence so the dataset survives it.
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
        /// What a faithful extractor's `PlanShape.stops` would be for this sentence.
        ///
        /// Needed wherever the request names a stop by *activity* rather than by meal —
        /// "drinks", "a walk", "some shopping". Those used to resolve through a 63-word
        /// category table in Swift; that table is gone, because deciding "a brewery" is
        /// a nightlife stop is world knowledge and no list ever finishes. The model
        /// classifies them now, token-constrained to this vocabulary, so a faithful
        /// extraction carries them here.
        bands: [SlotBand] = [],
        onlyTheseStops: Bool = false,
        time: String? = nil,
        budget: String? = nil,
        groupSize: Int? = nil,
        vibe: String? = nil,
        area: String? = nil
    ) -> ChatSummaryPayload {
        var p = ChatSummaryPayload()
        p.plannedStops = stops
        p.stops = bands.isEmpty ? nil : bands.map(\.rawValue)
        // Set wherever the host's own sentence rules the other stops out ("we *just*
        // want lunch"). The word lives in `said`, which a summary does not carry, so a
        // faithful extractor is the thing that would report it — and does, via
        // `PlanShape.onlyTheseStops`. Without it these cases would be asserting that
        // Wandr can read a word it was never given.
        p.onlyTheseStops = onlyTheseStops ? true : nil
        p.time = time
        p.budget = budget
        p.groupSize = groupSize
        p.vibe = vibe
        p.area = area
        return p
    }

    /// Phrasings chosen to cover every shape the app has to support — one named stop,
    /// an exclusive one, two stops, a whole day, and nothing stated — plus every report.
    ///
    /// ## The shape rule these encode
    ///
    /// **Whatever the host named is the plan.** Naming nothing is the only case in
    /// which Wandr proposes stops of its own.
    ///
    /// This set previously encoded a third rule between those two: one named stop was a
    /// *seed*, grown outward to a four-stop arc, so "dinner at Saket" was expected to
    /// return afternoon → something new → dinner → late. Eight cases below asserted
    /// that, and the expectations have changed with the rule.
    ///
    /// Changing an oracle deserves saying out loud why it is not simply moving the
    /// goalposts to meet the code. Growth was removed because it performs inference on
    /// top of an explicit request, and the report that killed it is one of these
    /// sentences: "12.00 to 5:00 pm outing with lunch and snacks" recognised a single
    /// stop, took the growth branch, and planned through to an 8 pm dinner — three
    /// hours past a stated finish. No expectation here was edited to make a failing
    /// case pass; a rule was deleted, and these are the cases that described it.
    ///
    /// The replacement for "one word should still produce an evening" is not growth but
    /// interludes — the gaps *between* two named stops, bounded on both sides by
    /// something the host actually said. A single named stop has no such gap, so
    /// `[.dinner]` is this case's answer under that design too, not a placeholder.
    static let golden: [GoldenCase] = [
        // — The report: a named stop is the request, not a seed for a day —
        GoldenCase(said: "dinner at saket for 2 people, around 2000",
                   payload: payload(stops: "dinner", budget: "around 2000",
                                    groupSize: 2, area: "Saket"),
                   expectedBands: [.dinner],
                   expectedCeilingPerHead: 1_000),

        // The same sentence with the word that changes everything.
        GoldenCase(said: "just dinner at saket",
                   payload: payload(stops: "dinner", onlyTheseStops: true, area: "Saket"),
                   expectedBands: [.dinner], expectedCeilingPerHead: nil),

        // — The earlier report: "lunch" must never reach a 10 pm bar —
        GoldenCase(said: "we just want lunch",
                   payload: payload(stops: "lunch", onlyTheseStops: true),
                   expectedBands: [.lunch], expectedCeilingPerHead: nil),

        GoldenCase(said: "lunch for 2, ₹2000",
                   payload: payload(stops: "lunch", budget: "₹2000", groupSize: 2),
                   expectedBands: [.lunch],
                   expectedCeilingPerHead: 1_000),

        GoldenCase(said: "outing, 12:30 to 2, lunch, in CP",
                   payload: payload(stops: "lunch", time: "from 12:30 to 2:00 pm", area: "CP"),
                   expectedBands: [.lunch], expectedCeilingPerHead: nil),

        GoldenCase(said: "we've only got 3 hours",
                   payload: payload(time: "only 3 hours"),
                   expectedBands: [.dinner, .late], expectedCeilingPerHead: nil),

        // — Breakfast, which had no band at all until recently —
        //
        // Breakfast in Khan Market came back as breakfast, lunch and an activity, which
        // is a day nobody asked for. That needed a per-band exemption while growth
        // existed; it is now just the general rule applied to breakfast.
        GoldenCase(said: "breakfast tomorrow around 9",
                   payload: payload(stops: "breakfast", time: "around 9 am"),
                   expectedBands: [.breakfast],
                   expectedCeilingPerHead: nil),

        GoldenCase(said: "breakfast in khan market",
                   payload: payload(stops: "breakfast", area: "Khan Market"),
                   expectedBands: [.breakfast], expectedCeilingPerHead: nil),

        // Two named stops mean both — and the morning between them, because they
        // bracketed it themselves.
        GoldenCase(said: "breakfast and then some shopping",
                   payload: payload(stops: "breakfast and then some shopping", bands: [.breakfast, .somethingNew]),
                   expectedBands: [.breakfast, .midMorning, .afternoon, .somethingNew],
                   expectedCeilingPerHead: nil),

        // — Two meals, the reported sentence —
        //
        // The afternoon and the evening activity are *between* what they named, so
        // they cost nothing that was asked for. This is the shape the request was
        // always describing: two meals with a day around them, not two meals alone.
        GoldenCase(said: "dinner and lunch for 2 near saket, around 2000 each",
                   payload: payload(stops: "dinner and lunch", budget: "around 2000 each",
                                    groupSize: 2, area: "Saket"),
                   expectedBands: [.lunch, .afternoon, .somethingNew, .dinner],
                   expectedCeilingPerHead: 2_000),

        // — Two stops, and the phrase that stops anything landing between them —
        //
        // `onlyTheseStops` is set because "nothing else" is in the sentence and not in
        // the payload: `plannedStops` carries the stops, not the qualifier. Without it
        // this case asserted that Wandr reads a word it was never given, and passed
        // only for as long as nothing was ever placed between two named stops.
        GoldenCase(said: "lunch and then dinner, nothing else",
                   payload: payload(stops: "lunch and dinner", onlyTheseStops: true),
                   expectedBands: [.lunch, .dinner], expectedCeilingPerHead: nil),

        // "Drinks" is a category word, and the stop it names is not covered by
        // "dinner" — so it survives, and this is a two-stop request rather than a
        // one-stop one.
        GoldenCase(said: "dinner then drinks",
                   payload: payload(stops: "dinner then drinks", bands: [.dinner, .late]),
                   expectedBands: [.dinner, .late], expectedCeilingPerHead: nil),

        // — One stop, various kinds —
        GoldenCase(said: "just drinks somewhere",
                   payload: payload(stops: "drinks", bands: [.late], onlyTheseStops: true),
                   expectedBands: [.late], expectedCeilingPerHead: nil),

        // An evening word is an evening stop. It used to reach backwards two bands and
        // invent most of a day in front of itself.
        GoldenCase(said: "drinks tonight",
                   payload: payload(stops: "drinks", bands: [.late]),
                   expectedBands: [.late],
                   expectedCeilingPerHead: nil),

        GoldenCase(said: "a walk somewhere green",
                   payload: payload(stops: "a walk", bands: [.afternoon], vibe: "green"),
                   expectedBands: [.afternoon],
                   expectedCeilingPerHead: nil),

        GoldenCase(said: "some shopping",
                   payload: payload(stops: "shopping", bands: [.somethingNew]),
                   expectedBands: [.somethingNew],
                   expectedCeilingPerHead: nil),

        // — Budget basis, both readings —
        GoldenCase(said: "dinner, 1500 each",
                   payload: payload(stops: "dinner", budget: "1500 each", groupSize: 4),
                   expectedBands: [.dinner],
                   expectedCeilingPerHead: 1_500),

        GoldenCase(said: "dinner, 4k for all of us",
                   payload: payload(stops: "dinner", budget: "4k for all of us", groupSize: 4),
                   expectedBands: [.dinner],
                   expectedCeilingPerHead: 1_000),

        GoldenCase(said: "drinks, 2k pp",
                   payload: payload(stops: "drinks", bands: [.late], budget: "2k pp", groupSize: 3),
                   expectedBands: [.late],
                   expectedCeilingPerHead: 2_000),

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
        let schedule = brief.schedule
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

        let slots = brief.schedule.slots

        for (earlier, later) in zip(slots, slots.dropFirst()) {
            #expect(earlier.endMinute <= later.startMinute,
                    "\(golden.said): \(earlier.title) runs into \(later.title)")
        }
    }
}
