//
//  TravelPlanningServiceTests.swift
//  WandrTests
//
//  The centrepiece of Step 2: the coordinator's ten required behaviors (§9),
//  exercised with the fake extractor and curator plus the *real* provider,
//  normalizer, validator, and drafter.
//
//  Nothing here touches SwiftUI, a simulator's UI, the network, or Apple
//  Intelligence. The only I/O is decoding the bundled dataset.
//

import Foundation
import Testing
@testable import Wandr

@Suite("Travel planning service")
struct TravelPlanningServiceTests {

    // MARK: - Test doubles
    //
    // These are coordinator-shaped doubles, distinct from the app's fakes: they
    // exist to observe call order and to interleave cancellation.

    /// Records whether research ever ran, so "the provider is not called before
    /// normalization" can be asserted about the coordinator's real call order.
    private final actor CallRecorder {
        private(set) var researchCalls = 0
        private(set) var curateCalls = 0
        func noteResearch() { researchCalls += 1 }
        func noteCurate() { curateCalls += 1 }
    }

    /// Wraps the real provider and reports that research happened.
    private struct ObservingProvider: VenueResearching {
        let wrapped: DistrictVenueProvider
        let recorder: CallRecorder
        /// Runs after research, before the coordinator's next cancellation check —
        /// the seam a mid-run cancellation test needs.
        let afterResearch: (@Sendable () async -> Void)?

        func research(for brief: OutingBrief) async throws -> VenueResearchResult {
            await recorder.noteResearch()
            let result = try await wrapped.research(for: brief)
            await afterResearch?()
            return result
        }
    }

    private struct ObservingCurator: ItineraryCurating {
        let wrapped: FakeItineraryCurator
        let recorder: CallRecorder

        func curate(brief: OutingBrief, evidence: [GroundedVenue]) async throws -> [CurationSlot] {
            await recorder.noteCurate()
            return try await wrapped.curate(brief: brief, evidence: evidence)
        }
    }

    // MARK: - Builders

    private func provider() throws -> DistrictVenueProvider {
        try DistrictVenueProvider(bundle: .main, retrievedAt: Fixtures.retrievedAt)
    }

    private func service(
        extractor: FakeBriefExtractor = FakeBriefExtractor(),
        curator: FakeItineraryCurator = FakeItineraryCurator(),
        researcher: (any VenueResearching)? = nil
    ) throws -> TravelPlanningService {
        TravelPlanningService(
            extractor: extractor,
            researcher: try researcher ?? provider(),
            curator: curator,
            now: { Fixtures.now }
        )
    }

    // MARK: - 1. Happy path

    @Test("A full run reaches ready with a validated plan")
    func happyPath() async throws {
        let service = try service()
        let run = try await service.plan(Fixtures.input(Fixtures.Request.afterWork))

        #expect(run.state == .ready)
        #expect(run.failure == nil)

        let plan = try #require(run.plan)
        #expect(!plan.slots.isEmpty)
        #expect(!plan.evidenceIDs.isEmpty)
        #expect(plan.runID == run.id)
        #expect(plan.evidenceSources.allSatisfy { $0.provider == "bundledDataset" })
    }

    @Test("A ready run produces a schedule draft")
    func happyPathProducesASchedule() async throws {
        let service = try service()
        let runID = PlanningRunID()
        let run = try await service.plan(Fixtures.input(Fixtures.Request.afterWork), runID: runID)

        #expect(run.state == .ready)
        let draft = try #require(await service.scheduleDraft(for: runID))
        let plan = try #require(run.plan)

        #expect(draft.planID == plan.id)
        #expect(draft.blocks.count == plan.slots.count)
        #expect(draft.assumptions.contains(.travelTimeNotVerified))
        #expect(draft.assumptions.contains(.singleDayAssumed))
    }

    @Test("Every curated venue ID is drawn from the evidence the run researched")
    func curationStaysGrounded() async throws {
        let service = try service()
        let run = try await service.plan(Fixtures.input(Fixtures.Request.afterWork))
        let plan = try #require(run.plan)

        let known = Set(try provider().venues(in: "Hauz Khas").map(\.venueID))
        for slot in plan.slots {
            for candidate in slot.candidates {
                #expect(known.contains(candidate.venueID), "\(candidate.venueID) was invented")
            }
        }
    }

    @Test("The run walks the phases in order")
    func phasesAreRecordedInOrder() async throws {
        let service = try service()
        let run = try await service.plan(Fixtures.input(Fixtures.Request.afterWork))

        let phases = run.events.map(\.phase)
        #expect(phases.first == .extracting)
        #expect(phases.contains(.researching))
        #expect(phases.contains(.validating))
        #expect(run.state == .ready)
    }

    // MARK: - 2. Empty input never starts a run

    @Test("Blank input throws before a run leaves idle")
    func blankInputNeverStartsARun() async throws {
        let service = try service()

        await #expect(throws: PlanningFailure(.inputEmpty)) {
            _ = try await service.plan(Fixtures.input(Fixtures.Request.blank))
        }
    }

    @Test("Blank input never reaches the provider")
    func blankInputNeverResearches() async throws {
        let recorder = CallRecorder()
        let service = try service(
            researcher: ObservingProvider(wrapped: try provider(), recorder: recorder, afterResearch: nil)
        )

        _ = try? await service.plan(Fixtures.input(Fixtures.Request.blank))
        #expect(await recorder.researchCalls == 0)
    }

    // MARK: - 3. Extraction failure

    @Test("An extractor failure lands the run in failed with the category preserved")
    func extractionFailurePropagatesCategory() async throws {
        let service = try service(
            extractor: FakeBriefExtractor(failure: PlanningFailure(.guardrailRefusal))
        )
        let run = try await service.plan(Fixtures.input(Fixtures.Request.afterWork))

        #expect(run.state == .failed)
        #expect(run.failure == PlanningFailure(.guardrailRefusal))
        #expect(run.failure?.retryAction == .editRequest)
    }

    @Test("An extractor failure never reaches the provider or the curator")
    func extractionFailureShortCircuits() async throws {
        let recorder = CallRecorder()
        let service = try service(
            extractor: FakeBriefExtractor(failure: PlanningFailure(.modelAssetsNotReady)),
            researcher: ObservingProvider(wrapped: try provider(), recorder: recorder, afterResearch: nil)
        )

        let run = try await service.plan(Fixtures.input(Fixtures.Request.afterWork))
        #expect(run.state == .failed)
        #expect(await recorder.researchCalls == 0)
        #expect(await recorder.curateCalls == 0)
    }

    /// The coordinator's actual call order, not just the type-level guard.
    @Test("Research never runs before a brief exists")
    func researchRequiresABriefFirst() async throws {
        let recorder = CallRecorder()
        let service = try service(
            extractor: FakeBriefExtractor(failure: PlanningFailure(.contextTooLarge)),
            researcher: ObservingProvider(wrapped: try provider(), recorder: recorder, afterResearch: nil)
        )

        let run = try await service.plan(Fixtures.input(Fixtures.Request.sparse))
        #expect(run.brief == nil, "No brief was ever produced")
        #expect(await recorder.researchCalls == 0, "Yet research ran anyway")
    }

    // MARK: - 4. Insufficient evidence
    //
    // Sourced from the real provider's real, thin result set — not a fake.

    @Test("A thin area fails with insufficientEvidence from the real dataset")
    func thinAreaProducesInsufficientEvidence() async throws {
        // Lodhi is genuinely thin: the dataset gives it two food venues, below the
        // validator's floor of three.
        let service = try service()
        let run = try await service.plan(Fixtures.input("A quiet afternoon in Lodhi"))

        #expect(run.state == .failed)
        let failure = try #require(run.failure)

        guard case .insufficientEvidence(let details) = failure.category else {
            Issue.record("Expected .insufficientEvidence, got \(failure.category)")
            return
        }
        #expect(!details.isEmpty)
        #expect(details.allSatisfy { $0.found < $0.required })
        #expect(failure.retryAction == .editRequest)
    }

    @Test("The thin-area failure names the category that came up short")
    func insufficientEvidenceNamesTheCategory() async throws {
        let service = try service()
        let run = try await service.plan(Fixtures.input("A quiet afternoon in Lodhi"))

        guard case .insufficientEvidence(let details) = run.failure?.category else {
            Issue.record("Expected .insufficientEvidence")
            return
        }
        #expect(details.contains { $0.category == .food })
    }

    // MARK: - 5. Validation failure

    @Test("An invented venue ID is caught by the validator through the coordinator")
    func inventedVenueFailsValidation() async throws {
        let service = try service(curator: FakeItineraryCurator(misbehavior: .inventVenue))
        let run = try await service.plan(Fixtures.input(Fixtures.Request.afterWork))

        #expect(run.state == .failed)
        guard case .validationFailed(let violations) = run.failure?.category else {
            Issue.record("Expected .validationFailed, got \(String(describing: run.failure?.category))")
            return
        }
        #expect(violations.contains { violation in
            if case .unknownVenue = violation { return true }
            return false
        })
        #expect(run.plan == nil, "A rejected curation must not produce a plan")
    }

    @Test("A duplicated venue inside one deck fails validation")
    func duplicateWithinSlotFailsValidation() async throws {
        let service = try service(curator: FakeItineraryCurator(misbehavior: .duplicateWithinSlot))
        let run = try await service.plan(Fixtures.input(Fixtures.Request.afterWork))

        #expect(run.state == .failed)
        guard case .validationFailed(let violations) = run.failure?.category else {
            Issue.record("Expected .validationFailed")
            return
        }
        #expect(violations.contains { violation in
            if case .duplicateWithinSlot = violation { return true }
            return false
        })
    }

    @Test("One venue filling two decks fails validation")
    func duplicateAcrossSlotsFailsValidation() async throws {
        let service = try service(curator: FakeItineraryCurator(misbehavior: .duplicateAcrossSlots))
        let run = try await service.plan(Fixtures.input(Fixtures.Request.afterWork))

        #expect(run.state == .failed)
        guard case .validationFailed(let violations) = run.failure?.category else {
            Issue.record("Expected .validationFailed")
            return
        }
        #expect(violations.contains { violation in
            if case .duplicateAcrossSlots = violation { return true }
            return false
        })
    }

    @Test("An empty curation fails validation rather than producing an empty plan")
    func emptyCurationFails() async throws {
        let service = try service(curator: FakeItineraryCurator(misbehavior: .returnNothing))
        let run = try await service.plan(Fixtures.input(Fixtures.Request.afterWork))

        #expect(run.state == .failed)
        guard case .validationFailed(let violations) = run.failure?.category else {
            Issue.record("Expected .validationFailed")
            return
        }
        #expect(violations.contains(.emptyCuration))
    }

    /// §13.4's split: with a *deep* real evidence snapshot, a thin deck is the
    /// curator's fault, not research's — and must report as such.
    @Test("A deliberately under-picking curator reports insufficientCandidates, not insufficientEvidence")
    func underPickingBlamesCurationNotEvidence() async throws {
        let service = try service(curator: FakeItineraryCurator(misbehavior: .underPick))
        let run = try await service.plan(Fixtures.input(Fixtures.Request.afterWork))

        #expect(run.state == .failed)
        guard case .validationFailed(let violations) = run.failure?.category else {
            Issue.record("Expected .validationFailed, got \(String(describing: run.failure?.category))")
            return
        }
        #expect(violations.contains { violation in
            if case .insufficientCandidates = violation { return true }
            return false
        })
    }

    @Test("An over-budget pick fails validation with the named ceiling")
    func overBudgetFailsValidation() async throws {
        // The impossible-budget request: ₹200 a head against a real dataset.
        let service = try service()
        let run = try await service.plan(Fixtures.input(Fixtures.Request.impossibleBudget))

        #expect(run.state == .failed)
        guard case .validationFailed(let violations) = run.failure?.category else {
            Issue.record("Expected .validationFailed, got \(String(describing: run.failure?.category))")
            return
        }
        #expect(violations.contains { violation in
            if case .overBudget = violation { return true }
            return false
        })
        #expect(run.failure?.retryAction == .retrySameRequest)
    }

    // MARK: - 6. Cancellation before research

    @Test("Cancellation requested up front is honored before the provider runs")
    func cancellationBeforeResearch() async throws {
        let recorder = CallRecorder()
        let runID = PlanningRunID()
        let service = try service(
            researcher: ObservingProvider(wrapped: try provider(), recorder: recorder, afterResearch: nil)
        )

        await service.requestCancellation(of: runID)
        let run = try await service.plan(Fixtures.input(Fixtures.Request.afterWork), runID: runID)

        #expect(run.state == .cancelled)
        #expect(await recorder.researchCalls == 0, "Cancelled runs must not do wasted work")
        #expect(run.plan == nil)
    }

    // MARK: - 7. Cancellation mid-run

    @Test("Cancellation after research but before curation still lands in cancelled")
    func cancellationMidRun() async throws {
        let recorder = CallRecorder()
        let runID = PlanningRunID()

        // Built in two stages so the provider can call back into the service.
        let box = ServiceBox()
        let researcher = ObservingProvider(
            wrapped: try provider(),
            recorder: recorder,
            afterResearch: { await box.requestCancellation(of: runID) }
        )
        let service = try service(
            curator: FakeItineraryCurator(),
            researcher: researcher
        )
        await box.set(service)

        let run = try await service.plan(Fixtures.input(Fixtures.Request.afterWork), runID: runID)

        #expect(run.state == .cancelled)
        #expect(await recorder.researchCalls == 1, "Research should have run before cancelling")
        #expect(await recorder.curateCalls == 0, "Curation must not run after cancellation")

        // `PlanningRun.cancel()`'s existing guarantee, now proven through the coordinator.
        #expect(run.brief == nil)
        #expect(run.plan == nil)
        #expect(run.failure == PlanningFailure(.cancelled))
    }

    /// Lets the provider double reach the service that owns it.
    private final actor ServiceBox {
        private var service: TravelPlanningService?
        func set(_ service: TravelPlanningService) { self.service = service }
        func requestCancellation(of runID: PlanningRunID) async {
            await service?.requestCancellation(of: runID)
        }
    }

    // MARK: - 8. Retry clears the prior failure

    @Test("Resubmitting after a failure produces a clean run")
    func retryClearsThePriorFailure() async throws {
        let failing = try service(
            extractor: FakeBriefExtractor(failure: PlanningFailure(.structuredOutputDecodingFailed))
        )
        let failed = try await failing.plan(Fixtures.input(Fixtures.Request.afterWork))
        #expect(failed.state == .failed)
        #expect(failed.failure != nil)

        // A fresh submission on a healthy service.
        let healthy = try service()
        let retried = try await healthy.plan(Fixtures.input(Fixtures.Request.afterWork))

        #expect(retried.state == .ready)
        #expect(retried.failure == nil, "A retry must not carry the old failure")
        #expect(retried.id != failed.id, "A retry is a fresh run")
    }

    @Test("A cancelled run does not poison the next one")
    func cancellationDoesNotPoisonTheNextRun() async throws {
        let service = try service()
        let cancelledID = PlanningRunID()
        await service.requestCancellation(of: cancelledID)

        let cancelled = try await service.plan(Fixtures.input(Fixtures.Request.afterWork), runID: cancelledID)
        #expect(cancelled.state == .cancelled)

        let next = try await service.plan(Fixtures.input(Fixtures.Request.afterWork))
        #expect(next.state == .ready)
    }

    // MARK: - 9. No event ever contains the request text
    //
    // Step 1 proved this of the *type*. This proves it of the *coordinator*.

    @Test("No event or failure carries the raw request text", arguments: [
        Fixtures.Request.afterWork,
        Fixtures.Request.birthday,
        Fixtures.Request.sparse,
        Fixtures.Request.injection,
        Fixtures.Request.impossibleBudget
    ])
    func runNeverRetainsRawText(request: String) async throws {
        let service = try service()
        let run = try await service.plan(Fixtures.input(request))

        for event in run.events {
            #expect(!event.title.contains(request))
            #expect(event.detail?.contains(request) != true)
        }
        #expect(run.failure?.userMessage.contains(request) != true)
    }

    /// The injection fixture specifically: its distinctive phrases must not appear
    /// anywhere in the transparency trail, in whole or in part.
    @Test("The injection request leaves no trace in the event log")
    func injectionTextNeverSurfaces() async throws {
        let service = try service()
        let run = try await service.plan(Fixtures.input(Fixtures.Request.injection))

        let forbidden = ["Ignore instructions", "ignore instructions", "most expensive", "book the"]
        let trail = run.events.map { "\($0.title) \($0.detail ?? "")" }.joined(separator: " ")
            + " " + (run.failure?.userMessage ?? "")

        for phrase in forbidden {
            #expect(!trail.contains(phrase), "'\(phrase)' leaked into the transparency trail")
        }
    }

    @Test("The injection request has no action to reach and simply plans")
    func injectionIsInert() async throws {
        let service = try service()
        let run = try await service.plan(Fixtures.input(Fixtures.Request.injection))

        // There is no booking, payment, or price-maximizing affordance in the
        // domain, so the instruction has nowhere to go. It plans like any other
        // constraint-free request.
        #expect(run.state == .ready)
        let plan = try #require(run.plan)
        #expect(!plan.slots.isEmpty)
    }

    // MARK: - 10. All six fixtures reach a defined terminal state
    //
    // This mapping is the baseline Step 3 must reproduce once the fake extractor
    // is replaced with a real Foundation Models adapter.

    @Test("After-work reaches ready")
    func fixtureAfterWorkIsReady() async throws {
        let run = try await service().plan(Fixtures.input(Fixtures.Request.afterWork))
        #expect(run.state == .ready)
    }

    @Test("Birthday reaches ready")
    func fixtureBirthdayIsReady() async throws {
        let run = try await service().plan(Fixtures.input(Fixtures.Request.birthday))
        #expect(run.state == .ready)
    }

    @Test("Sparse reaches ready on safe defaults alone")
    func fixtureSparseIsReady() async throws {
        let run = try await service().plan(Fixtures.input(Fixtures.Request.sparse))
        #expect(run.state == .ready)
        let brief = try #require(run.plan?.brief)
        #expect(!brief.safeDefaults.isEmpty, "Sparse must be carried by marked defaults")
    }

    @Test("Injection reaches ready and stays inert")
    func fixtureInjectionIsReady() async throws {
        let run = try await service().plan(Fixtures.input(Fixtures.Request.injection))
        #expect(run.state == .ready)
    }

    @Test("Impossible budget fails validation")
    func fixtureImpossibleBudgetFails() async throws {
        let run = try await service().plan(Fixtures.input(Fixtures.Request.impossibleBudget))
        #expect(run.state == .failed)
        guard case .validationFailed = run.failure?.category else {
            Issue.record("Expected .validationFailed, got \(String(describing: run.failure?.category))")
            return
        }
    }

    @Test("Blank never leaves idle")
    func fixtureBlankNeverStarts() async throws {
        await #expect(throws: PlanningFailure(.inputEmpty)) {
            _ = try await service().plan(Fixtures.input(Fixtures.Request.blank))
        }
    }

    /// Every fixture ends somewhere defined — nothing hangs in an active phase.
    @Test("Every fixture request reaches a defined terminal state")
    func everyFixtureTerminates() async throws {
        let requests = [
            Fixtures.Request.afterWork,
            Fixtures.Request.birthday,
            Fixtures.Request.sparse,
            Fixtures.Request.injection,
            Fixtures.Request.impossibleBudget
        ]

        for request in requests {
            let run = try await service().plan(Fixtures.input(request))
            #expect(run.state.isTerminal, "\(run.state) is not terminal")
            #expect(!run.state.isActive)
        }
    }

    // MARK: - Determinism

    @Test("The same request twice produces the same plan shape")
    func runsAreDeterministic() async throws {
        let first = try await service().plan(Fixtures.input(Fixtures.Request.afterWork))
        let second = try await service().plan(Fixtures.input(Fixtures.Request.afterWork))

        #expect(first.state == second.state)
        #expect(first.plan?.evidenceIDs == second.plan?.evidenceIDs)
        #expect(first.plan?.slots.map(\.candidateVenueIDs) == second.plan?.slots.map(\.candidateVenueIDs))
        #expect(first.events.map(\.title) == second.events.map(\.title))
    }

    // MARK: - Hard constraints end to end

    @Test("A vegetarian request never selects a venue surveyed as not vegetarian")
    func hardDietaryConstraintHoldsEndToEnd() async throws {
        let service = try service()
        let run = try await service.plan(Fixtures.input(Fixtures.Request.birthday))

        #expect(run.state == .ready)
        let plan = try #require(run.plan)
        let evidence = try provider().allVenues
        let byID = Dictionary(uniqueKeysWithValues: evidence.map { ($0.venueID, $0) })

        for slot in plan.slots {
            for candidate in slot.candidates {
                let venue = try #require(byID[candidate.venueID])
                if let missing = venue.dietaryTags.unsatisfied(by: [.vegetarian]) {
                    #expect(missing.isEmpty, "\(venue.venueID) was surveyed as not vegetarian")
                }
            }
        }
    }

    @Test("Unsurveyed constraints warn rather than silently passing")
    func unsurveyedConstraintsWarn() async throws {
        let service = try service()
        let run = try await service.plan(Fixtures.input(Fixtures.Request.birthday))
        let plan = try #require(run.plan)

        // Sights and discover venues in the dataset largely never state dietary
        // tags, so a vegetarian request must produce unverified-dietary warnings.
        #expect(plan.warnings.contains { warning in
            if case .unverifiedDietary = warning.kind { return true }
            return false
        })
    }
}
