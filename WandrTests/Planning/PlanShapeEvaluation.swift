//
//  PlanShapeEvaluation.swift
//  WandrTests
//
//  The golden set, rebuilt as an evaluation — data plus invariants, instead of a
//  hand-written answer per case.
//
//  ## What changed and why
//
//  `PlanShapeEvaluationTests` carries a list of `GoldenCase`s, each with an
//  `expectedBands` array someone typed. That shape has a specific failure mode, and
//  this project has lived through it: when a case fails, the cheapest way to make it
//  pass is to edit the expectation, and the second cheapest is a branch keyed to that
//  case. Both leave the suite green and the product wrong. An oracle you can read is
//  an oracle you can satisfy without fixing anything.
//
//  Invariants cannot be satisfied that way. "No block ends after a stated finish" is
//  either true of every plan or false of one, and there is no per-sentence edit that
//  makes a violation acceptable. So the dataset here carries **no expected output at
//  all** — `SampleProtocol.expected` is optional and every sample leaves it nil. New
//  phrasings are added as data; they either hold the properties or they have found a
//  real defect.
//
//  ## What it does not do yet
//
//  `subject(from:)` runs the deterministic half — payload → brief → schedule. Running
//  the *live extractor* here is possible (the Simulator does execute Foundation Models
//  against the host Mac's model) and is the obvious next step; it is left out of this
//  pass so that adopting the framework and changing what is measured do not land in
//  one change.
//

import Evaluations
import Foundation
// `containsColumn` is TabularData's, reached through `EvaluationResult.detailed`.
import TabularData
import Testing
@testable import Wandr

// MARK: - Sample

/// One host request. Carries no expected plan, deliberately.
nonisolated struct PlanRequestSample: SampleProtocol {
    /// What the host said, verbatim.
    var said: String
    /// What a faithful extraction of that sentence yields. Fields the sentence does
    /// not mention are absent.
    var stops: [String]?
    var onlyTheseStops: Bool?
    var time: String?
    var budget: String?
    var groupSize: Int?
    var area: String?
    var vibe: String?
    /// Which slice of the dataset this belongs to, so a failure can be traced to a
    /// whole *category* of request rather than to one sentence.
    var group: String

    var input: String { said }

    /// No ground truth. The properties are the truth.
    var expected: PlanOutcome? { nil }

    var payload: ChatSummaryPayload {
        var p = ChatSummaryPayload()
        p.plannedStops = said
        p.stops = stops
        p.onlyTheseStops = onlyTheseStops
        p.time = time
        p.budget = budget
        p.groupSize = groupSize
        p.area = area
        p.vibe = vibe
        return p
    }
}

/// What the pipeline produced for one sample.
///
/// Carries `failure` rather than throwing out of `subject(from:)`. A throwing subject
/// does not fail a sample — the runner marks every metric `.ignore`, and `.ignore` is
/// excluded from aggregation, so the sample leaves the denominator and the pass rate
/// goes **up** as the feature breaks for more people. The `produced` guardrail below
/// is what makes that impossible.
nonisolated struct PlanOutcome: Codable, Sendable, Equatable {
    var bands: [String] = []
    var startMinutes: [Int] = []
    var endMinutes: [Int] = []
    var requested: [String] = []
    var statedEndMinute: Int?
    var failure: String?
}

// MARK: - Evaluation

@available(iOS 27.0, macOS 27.0, *)
nonisolated struct PlanShapeEvaluation: Evaluation {

    // Declared once as properties: a `Metric` is a name token, and an inline
    // `Metric("…")` cannot be referenced from `aggregateMetrics`.
    let produced = Metric("Produced")
    let withinStatedEnd = Metric("WithinStatedEnd")
    let withinRequestSpan = Metric("WithinRequestSpan")
    let noOverlap = Metric("NoOverlap")
    let namedStopsPresent = Metric("NamedStopsPresent")
    let stopCount = Metric("StopCount")

    var dataset: ArrayLoader<PlanRequestSample> { ArrayLoader(samples: Self.samples) }

    func subject(from sample: PlanRequestSample) async throws -> ModelSubject<PlanOutcome> {
        // Bare `catch`, not `catch let e as SomeError`: a typed catch rethrows the
        // very cases most worth trapping, and a rethrow here silently deletes the
        // sample from the aggregate.
        do {
            let draft = ChatSummaryBriefMapper().draft(from: sample.payload)
            guard case .normalized(let brief) = try BriefNormalizer().normalize(draft) else {
                return ModelSubject(value: PlanOutcome(failure: "briefNeededDetails"))
            }
            let schedule = brief.schedule
            return ModelSubject(value: PlanOutcome(
                bands: schedule.slots.map(\.band.rawValue),
                startMinutes: schedule.slots.map(\.startMinute),
                endMinutes: schedule.slots.map(\.endMinute),
                requested: brief.requestedStops.map(\.rawValue).sorted(),
                statedEndMinute: brief.timeWindow.value.latestEndMinute
            ))
        } catch {
            return ModelSubject(value: PlanOutcome(failure: "\(error)"))
        }
    }

    // Spelling the concrete types rather than the `Evaluators` typealias: the alias
    // compiles in isolation and then fails with "unsupported recursion for reference
    // to type alias 'Evaluators'" the moment anything touches `inputColumn`.
    @EvaluatorsBuilder<PlanRequestSample, ModelSubject<PlanOutcome>>
    var evaluators: [any EvaluatorProtocol<PlanRequestSample, ModelSubject<PlanOutcome>>] {
        // Guardrail. Without it, a sample the pipeline cannot handle simply vanishes.
        Evaluator { _, subject in
            subject.value.failure.map { produced.failing(rationale: $0) } ?? produced.passing()
        }

        // Invariant 1 — nothing runs past a finish the host gave.
        Evaluator { _, subject in
            guard let end = subject.value.statedEndMinute else {
                return withinStatedEnd.ignore(rationale: "no finish stated")
            }
            let over = subject.value.endMinutes.filter { $0 > end }
            return over.isEmpty
                ? withinStatedEnd.passing()
                : withinStatedEnd.failing(rationale: "ends \(over) past \(end)")
        }

        // Invariant 2 — the plan stays inside the span the host named.
        Evaluator { _, subject in
            let order = SlotBand.allCases.map(\.rawValue)
            let named = subject.value.requested.compactMap(order.firstIndex(of:))
            guard let first = named.min(), let last = named.max() else {
                return withinRequestSpan.ignore(rationale: "nothing named")
            }
            // An unsatisfiable request — "lunch, but we're only free 8 to 9" — is
            // dropped by the schedule and disclosed. The fallback plan lies wholly
            // outside the span, legitimately, so there is no span to test.
            guard subject.value.bands.contains(where: subject.value.requested.contains) else {
                return withinRequestSpan.ignore(rationale: "request was unsatisfiable")
            }
            let outside = subject.value.bands
                .compactMap(order.firstIndex(of:))
                .filter { $0 < first || $0 > last }
            return outside.isEmpty
                ? withinRequestSpan.passing()
                : withinRequestSpan.failing(rationale: "\(outside.count) stop(s) outside the request")
        }

        // Invariant 3 — consecutive stops never overlap.
        Evaluator { _, subject in
            let pairs = zip(subject.value.endMinutes, subject.value.startMinutes.dropFirst())
            let bad = pairs.filter { $0 > $1 }
            return bad.isEmpty ? noOverlap.passing() : noOverlap.failing(rationale: "\(bad.count) overlap(s)")
        }

        // Invariant 4 — every stop the host named survives, unless their own window
        // made it impossible. A stop dropped for want of time is disclosed elsewhere;
        // a stop dropped silently is the bug this whole effort started from.
        Evaluator { _, subject in
            let value = subject.value
            guard !value.requested.isEmpty else {
                return namedStopsPresent.ignore(rationale: "nothing named")
            }
            guard value.statedEndMinute == nil else {
                return namedStopsPresent.ignore(rationale: "window may legitimately drop a stop")
            }
            let missing = Set(value.requested).subtracting(value.bands)
            return missing.isEmpty
                ? namedStopsPresent.passing()
                : namedStopsPresent.failing(rationale: "lost \(missing.sorted())")
        }

        // A distribution beside the pass/fail checks. All-green range checks are
        // satisfiable degenerately — a pipeline that returned one stop every time
        // would pass every invariant above and be useless.
        Evaluator { _, subject in stopCount.scoring(Double(subject.value.bands.count)) }
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: produced)
        aggregator.computeMean(of: withinStatedEnd)
        aggregator.computeMean(of: withinRequestSpan)
        aggregator.computeMean(of: noOverlap)
        aggregator.computeMean(of: namedStopsPresent)
        aggregator.group("Stop count") { group in
            group.computeMean(of: stopCount)
            group.computeStandardDeviation(of: stopCount)
            group.computeMinimum(of: stopCount)
        }
    }
}

// MARK: - The dataset

@available(iOS 27.0, macOS 27.0, *)
extension PlanShapeEvaluation {

    /// Real phrasings, as JSON.
    ///
    /// A document rather than a Swift array of structs, because that is the difference
    /// the whole change is about: adding a phrasing is adding an object here, and the
    /// only thing it can do is pass or expose a defect. It cannot bring an expectation
    /// with it, because there is nowhere to put one.
    ///
    /// `group` splits the set into slices that are gated separately. A 95% average that
    /// is 100% on ordinary requests and 40% on time-bounded ones is not a 95% pipeline;
    /// it is a broken use case hidden by an average.
    static let samplesJSON = """
    [
      {"said":"dinner at saket for 2 people, around 2000","stops":["dinner"],"budget":"around 2000","groupSize":2,"area":"Saket","group":"named"},
      {"said":"just dinner at saket","stops":["dinner"],"onlyTheseStops":true,"area":"Saket","group":"exclusive"},
      {"said":"we just want lunch","stops":["lunch"],"onlyTheseStops":true,"group":"exclusive"},
      {"said":"lunch for 2, 2000 rupees","stops":["lunch"],"budget":"₹2000","groupSize":2,"group":"named"},
      {"said":"i need lunch","stops":["lunch"],"group":"named"},
      {"said":"breakfast tomorrow around 9","stops":["breakfast"],"time":"around 9 am","group":"named"},
      {"said":"breakfast in khan market","stops":["breakfast"],"area":"Khan Market","group":"named"},
      {"said":"dinner and lunch for 2 near saket, around 2000 each","stops":["lunch","dinner"],"budget":"around 2000 each","groupSize":2,"area":"Saket","group":"twoStops"},
      {"said":"lunch and then dinner, nothing else","stops":["lunch","dinner"],"onlyTheseStops":true,"group":"exclusive"},
      {"said":"breakfast and then some shopping","stops":["breakfast","somethingNew"],"group":"twoStops"},
      {"said":"dinner then drinks","stops":["dinner","late"],"group":"twoStops"},
      {"said":"just drinks somewhere","stops":["late"],"onlyTheseStops":true,"group":"exclusive"},
      {"said":"drinks tonight","stops":["late"],"group":"named"},
      {"said":"a walk somewhere green","stops":["afternoon"],"vibe":"green","group":"named"},
      {"said":"some shopping","stops":["somethingNew"],"group":"named"},
      {"said":"dinner, 1500 each","stops":["dinner"],"budget":"1500 each","groupSize":4,"group":"named"},
      {"said":"dinner, 4k for all of us","stops":["dinner"],"budget":"4k for all of us","groupSize":4,"group":"named"},
      {"said":"drinks, 2k pp","stops":["late"],"budget":"2k pp","groupSize":3,"group":"named"},
      {"said":"i need 12.00 to 5:00 pm outing with lunch and snacks","stops":["lunch","afternoon"],"time":"12.00 to 5:00 pm","group":"bounded"},
      {"said":"outing, 12:30 to 2, lunch, in CP","stops":["lunch"],"time":"from 12:30 to 2:00 pm","area":"CP","group":"bounded"},
      {"said":"lunch, but we're only free 8 to 9","stops":["lunch"],"time":"free only 8-9pm","group":"bounded"},
      {"said":"we've only got 3 hours","time":"only 3 hours","group":"bounded"},
      {"said":"half day from 2pm to 8pm in cyberhub","time":"from 2pm to 8pm","area":"Cyberhub","group":"bounded"},
      {"said":"we're free all day, make a day of it","time":"the whole day, about 8 hours","group":"open"},
      {"said":"let's go out","group":"open"},
      {"said":"somewhere in saket","area":"Saket","group":"open"}
    ]
    """

    static let samples: [PlanRequestSample] = {
        // A malformed dataset must be loud. `JSONLoader` logs and skips bad entries,
        // which would silently shrink the set and inflate every rate computed from it.
        do { return try JSONDecoder().decode([PlanRequestSample].self, from: Data(samplesJSON.utf8)) }
        catch { fatalError("plan-shape sample set is malformed: \(error)") }
    }()
}

// MARK: - The gate

@Suite("Plan shape invariants")
struct PlanShapeInvariantTests {

    @available(iOS 27.0, macOS 27.0, *)
    @Test("Every request in the set holds every plan-shape invariant",
          .evaluates(PlanShapeEvaluation(), info: ["dataset": "plan-shape-v1"]))
    func planShapeHoldsItsInvariants() async throws {
        let evaluation = PlanShapeEvaluation()
        let result = EvaluationContext.current.result

        // Wiring first, and this ordering is not cosmetic. Both failures below are
        // *recorded* by the runner rather than thrown, and a recorded failure leaves a
        // metric column that looks present and healthy while aggregating over an empty
        // set. Asserting the numbers first would mean reading them off a phantom
        // denominator.
        #expect(!result.detailed.containsColumn("SubjectInferenceError", SubjectInferenceError.self),
                "A sample produced no output at all")
        #expect(!result.detailed.containsColumn("EvaluatorErrors", [EvaluatorError].self),
                "An evaluator threw; its metric is silently all-ignore")

        // Guardrails. 100% is their required state, not a suspicious one.
        #expect(result.aggregateValue(.mean(of: evaluation.produced)) == 1.0,
                "Every request must produce a plan")
        #expect(result.aggregateValue(.mean(of: evaluation.withinStatedEnd)) == 1.0,
                "No block may end after a stated finish")
        #expect(result.aggregateValue(.mean(of: evaluation.withinRequestSpan)) == 1.0,
                "No plan may reach outside the stops the host named")
        #expect(result.aggregateValue(.mean(of: evaluation.noOverlap)) == 1.0,
                "Stops may not overlap")
        #expect(result.aggregateValue(.mean(of: evaluation.namedStopsPresent)) == 1.0,
                "A stop the host named may not vanish")

        // The distribution beside the pass/fail checks. A pipeline that returned one
        // stop for every request would satisfy every invariant above and be useless;
        // a non-zero spread is what rules that out.
        #expect(result.aggregateValue(.minimum(of: evaluation.stopCount)) >= 1,
                "Every request deserves at least one stop")
        #expect(result.aggregateValue(.standardDeviation(of: evaluation.stopCount)) > 0.3,
                "Plans of a constant length would pass every invariant and mean nothing")
    }

    @Test("The sample set is loaded whole, and carries no expected answers")
    func datasetIsIntact() throws {
        guard #available(iOS 27.0, macOS 27.0, *) else { return }
        let samples = PlanShapeEvaluation.samples

        #expect(samples.count >= 20, "Apple's floor for a first golden set is 10–20")
        #expect(Set(samples.map(\.said)).count == samples.count, "A duplicated phrasing counts twice")
        #expect(samples.allSatisfy { $0.expected == nil },
                "An expected value here would reintroduce exactly the oracle this replaced")

        // Every slice has to be represented, or the aggregate is silent about it.
        let groups = Set(samples.map(\.group))
        #expect(groups == ["named", "exclusive", "twoStops", "bounded", "open"])
        for group in groups {
            #expect(samples.count { $0.group == group } >= 3, "\(group) is too thin to gate on")
        }
    }
}
