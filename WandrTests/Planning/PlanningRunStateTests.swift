//
//  PlanningRunStateTests.swift
//  WandrTests
//
//  The state machine from `nonuistuff/plan.md` §6, and the privacy property that
//  makes the run safe to keep around.
//

import Foundation
import Testing
@testable import Wandr

@Suite("PlanningRun state machine")
struct PlanningRunStateTests {

    /// The transition table, transcribed straight from the plan document.
    /// If the doc and the code disagree, this test is the thing that says so.
    static let table: [PlanningState: Set<PlanningState>] = [
        .idle:         [.extracting],
        .extracting:   [.needsDetails, .researching, .failed, .cancelled],
        .needsDetails: [.researching, .cancelled],
        .researching:  [.validating, .failed, .cancelled],
        .validating:   [.curating, .needsDetails, .failed, .cancelled],
        .curating:     [.ready, .failed, .cancelled],
        .ready:        [.idle, .researching],
        .failed:       [.idle, .extracting, .researching],
        .cancelled:    [.idle]
    ]

    private func makeRun(at state: PlanningState) throws -> PlanningRun {
        var run = PlanningRun(input: Fixtures.input(Fixtures.Request.afterWork), startedAt: Fixtures.now)
        for step in try Self.path(to: state) {
            try run.transition(to: step)
        }
        return run
    }

    /// A shortest legal route from `.idle` to each state, so tests can start anywhere.
    private static func path(to state: PlanningState) throws -> [PlanningState] {
        switch state {
        case .idle:         return []
        case .extracting:   return [.extracting]
        case .needsDetails: return [.extracting, .needsDetails]
        case .researching:  return [.extracting, .researching]
        case .validating:   return [.extracting, .researching, .validating]
        case .curating:     return [.extracting, .researching, .validating, .curating]
        case .ready:        return [.extracting, .researching, .validating, .curating, .ready]
        case .failed:       return [.extracting, .failed]
        case .cancelled:    return [.extracting, .cancelled]
        }
    }

    // MARK: - The table

    @Test("Legal next states match the plan document exactly", arguments: PlanningState.allCases)
    func legalNextStatesMatchTheDocument(state: PlanningState) throws {
        let expected = try #require(Self.table[state])
        #expect(state.legalNextStates == expected)
    }

    @Test("Every transition the table forbids is rejected", arguments: PlanningState.allCases)
    func illegalTransitionsAreRejected(from: PlanningState) throws {
        let legal = from.legalNextStates

        for to in PlanningState.allCases where !legal.contains(to) {
            var run = try makeRun(at: from)

            #expect(throws: IllegalPlanningTransition(from: from, to: to)) {
                try run.transition(to: to)
            }

            // A rejected transition leaves the run exactly where it was.
            #expect(run.state == from)
        }
    }

    @Test("A state can never transition to itself", arguments: PlanningState.allCases)
    func selfTransitionsAreIllegal(state: PlanningState) {
        #expect(state.canTransition(to: state) == false)
    }

    @Test("Capture can never jump straight to a result")
    func captureCannotJumpToCuration() throws {
        var run = PlanningRun(input: Fixtures.input(Fixtures.Request.afterWork), startedAt: Fixtures.now)

        // Having text is not the same as having a plan.
        #expect(throws: IllegalPlanningTransition(from: .idle, to: .curating)) {
            try run.transition(to: .curating)
        }
        #expect(throws: IllegalPlanningTransition(from: .idle, to: .ready)) {
            try run.transition(to: .ready)
        }
        #expect(throws: IllegalPlanningTransition(from: .idle, to: .researching)) {
            try run.transition(to: .researching)
        }
        #expect(run.state == .idle)
    }

    @Test("No research happens before extraction and normalization")
    func researchRequiresExtractionFirst() throws {
        var run = PlanningRun(input: Fixtures.input(Fixtures.Request.sparse), startedAt: Fixtures.now)

        // `.researching` is reachable only via `.extracting` or `.needsDetails`.
        #expect(PlanningState.idle.canTransition(to: .researching) == false)
        #expect(PlanningState.extracting.canTransition(to: .researching))
        #expect(PlanningState.needsDetails.canTransition(to: .researching))

        try run.transition(to: .extracting)
        try run.transition(to: .researching)
        #expect(run.state == .researching)
    }

    // MARK: - The happy path

    @Test("The full happy path is legal end to end")
    func happyPathIsLegal() throws {
        var run = PlanningRun(input: Fixtures.input(Fixtures.Request.afterWork), startedAt: Fixtures.now)
        #expect(run.state == .idle)

        try run.transition(to: .extracting)
        run.setBrief(Fixtures.afterWorkBrief)
        try run.transition(to: .researching)
        try run.transition(to: .validating)
        try run.transition(to: .curating)

        let plan = try FeasibilityValidator().validate(
            brief: Fixtures.afterWorkBrief,
            evidence: Fixtures.evidence,
            slots: Fixtures.validSlots,
            runID: run.id,
            now: Fixtures.now
        )
        try run.complete(with: plan)

        #expect(run.state == .ready)
        #expect(run.plan == plan)
        #expect(run.failure == nil)
        #expect(run.brief == Fixtures.afterWorkBrief)
    }

    @Test("Needing details detours through the host and rejoins research")
    func needsDetailsRejoinsResearch() throws {
        var run = PlanningRun(input: Fixtures.input(Fixtures.Request.sparse), startedAt: Fixtures.now)

        try run.transition(to: .extracting)
        try run.transition(to: .needsDetails)
        run.setMissingConstraints([.area, .budgetPerHead])
        #expect(run.missingConstraints == [.area, .budgetPerHead])

        try run.transition(to: .researching)
        #expect(run.state == .researching)
    }

    // MARK: - Failure and cancellation

    @Test("Failing attaches a structured reason and keeps a retry path")
    func failureRetainsSafeStructuredState() throws {
        var run = PlanningRun(input: Fixtures.input(Fixtures.Request.impossibleBudget), startedAt: Fixtures.now)
        try run.transition(to: .extracting)
        try run.transition(to: .researching)

        let failure = PlanningFailure.insufficientEvidence([
            .init(category: .food, required: 3, found: 1)
        ])
        try run.fail(failure)

        #expect(run.state == .failed)
        #expect(run.failure == failure)
        #expect(run.failure?.isRecoverable == true)
        #expect(run.failure?.retryAction == .editRequest)

        // Retrying clears the stale failure so it can't render beside a fresh phase.
        try run.transition(to: .researching)
        #expect(run.failure == nil)
    }

    @Test("Cancellation stops the run and discards everything but provenance")
    func cancellationDiscardsWork() throws {
        var run = PlanningRun(input: Fixtures.input(Fixtures.Request.afterWork), startedAt: Fixtures.now)
        try run.transition(to: .extracting)
        run.setBrief(Fixtures.afterWorkBrief)
        try run.transition(to: .researching)

        run.requestCancellation()
        #expect(run.isCancellationRequested)

        try run.cancel()

        #expect(run.state == .cancelled)
        #expect(run.brief == nil)
        #expect(run.plan == nil)
        #expect(run.failure?.category == .cancelled)

        // Provenance survives, because it is metadata rather than content.
        #expect(run.source == .directCapture)

        // A cancelled run only goes home.
        #expect(run.state.legalNextStates == [.idle])
    }

    @Test("Returning to idle clears the brief and the result")
    func idleClearsEverything() throws {
        var run = PlanningRun(input: Fixtures.input(Fixtures.Request.afterWork), startedAt: Fixtures.now)
        try run.transition(to: .extracting)
        run.setBrief(Fixtures.afterWorkBrief)
        try run.transition(to: .researching)
        try run.transition(to: .validating)
        try run.transition(to: .curating)

        let plan = try FeasibilityValidator().validate(
            brief: Fixtures.afterWorkBrief,
            evidence: Fixtures.evidence,
            slots: Fixtures.validSlots,
            runID: run.id,
            now: Fixtures.now
        )
        try run.complete(with: plan)
        try run.transition(to: .idle)

        #expect(run.brief == nil)
        #expect(run.plan == nil)
        #expect(run.failure == nil)
    }

    // MARK: - Phase classification

    @Test("Active and terminal phases are classified for the UI")
    func phaseClassification() {
        #expect(PlanningState.extracting.isActive)
        #expect(PlanningState.researching.isActive)
        #expect(PlanningState.validating.isActive)
        #expect(PlanningState.curating.isActive)

        #expect(PlanningState.idle.isActive == false)
        #expect(PlanningState.needsDetails.isActive == false)

        #expect(PlanningState.ready.isTerminal)
        #expect(PlanningState.failed.isTerminal)
        #expect(PlanningState.cancelled.isTerminal)
        #expect(PlanningState.extracting.isTerminal == false)
    }
}

// MARK: - Volatility

@Suite("Volatile input handling")
struct PlanningInputVolatilityTests {

    @Test("Whitespace-only input never starts extraction")
    func blankInputIsRejected() {
        let blank = Fixtures.input(Fixtures.Request.blank)

        #expect(blank.text.isEmpty)
        #expect(blank.isPlannable == false)
        #expect(throws: PlanningFailure(.inputEmpty)) {
            _ = try blank.validated()
        }
        #expect(PlanningFailure(.inputEmpty).retryAction == .editRequest)
    }

    @Test("Input text is trimmed on the way in")
    func inputIsTrimmed() throws {
        let padded = Fixtures.input("  \n Dinner in Hauz Khas \n ")

        #expect(padded.text == "Dinner in Hauz Khas")
        #expect(try padded.validated().text == "Dinner in Hauz Khas")
    }

    @Test("A run keeps the input's provenance and none of its content")
    func runNeverRetainsRawText() throws {
        let input = Fixtures.input(Fixtures.Request.injection)
        var run = PlanningRun(input: input, startedAt: Fixtures.now)

        try run.transition(to: .extracting)
        run.record("Reading your request", at: Fixtures.now)
        try run.transition(to: .researching)
        run.record("Searching local venues", detail: "4 categories", at: Fixtures.now)

        // Provenance is kept.
        #expect(run.inputID == input.id)
        #expect(run.source == input.source)

        // Content is not. No event carries the host's words.
        for event in run.events {
            #expect(!event.title.contains("Ignore instructions"))
            #expect(event.detail.map { !$0.contains("Ignore instructions") } ?? true)
        }
        #expect(run.events.count == 2)
        #expect(run.events.map(\.phase) == [.extracting, .researching])
    }

    @Test("A failure payload never carries the request text")
    func failurePayloadsAreContentFree() {
        let failures: [PlanningFailure] = [
            PlanningFailure(.inputEmpty),
            PlanningFailure(.deviceIneligible),
            PlanningFailure(.intelligenceDisabled),
            PlanningFailure(.modelAssetsNotReady),
            PlanningFailure(.guardrailRefusal),
            PlanningFailure(.contextTooLarge),
            PlanningFailure(.structuredOutputDecodingFailed),
            PlanningFailure(.cancelled),
            PlanningFailure.insufficientEvidence([.init(category: .food, required: 3, found: 0)]),
            PlanningFailure.validationFailed([
                .unknownVenue(slotID: SlotID("dinner"), venueID: VenueID("food-1"))
            ])
        ]

        for failure in failures {
            #expect(!failure.userMessage.isEmpty)
            #expect(!failure.userMessage.contains(Fixtures.Request.injection))
            #expect(!failure.userMessage.contains("Ignore instructions"))
        }
    }

    @Test("Every failure category has a user-readable message and a way forward")
    func everyFailureHasAWayForward() {
        // Only an ineligible device is a genuine dead end, and it says so plainly.
        #expect(PlanningFailure(.deviceIneligible).isRecoverable == false)
        #expect(PlanningFailure(.intelligenceDisabled).retryAction == .openSettings)
        #expect(PlanningFailure(.modelAssetsNotReady).retryAction == .waitAndRetry)
        #expect(PlanningFailure(.cancelled).retryAction == .startOver)
        #expect(PlanningFailure(.guardrailRefusal).retryAction == .editRequest)
    }

    @Test("Describing an input redacts its text")
    func descriptionRedactsText() {
        let input = Fixtures.input(Fixtures.Request.injection)
        let described = "\(input)"

        #expect(!described.contains("Ignore instructions"))
        #expect(described.contains("directCapture"))
        #expect(described.contains("characters:"))
    }

    @Test("The injection request has no action, booking, or price-maximizing path to reach")
    func injectionRequestHasNowhereToGo() throws {
        // The request is data. It becomes a brief with safe defaults and notes —
        // never an instruction, because the domain models no executable action.
        let brief = Fixtures.injectionBrief
        #expect(brief.budgetPerHead.value == .unspecified)
        #expect(brief.safeDefaults.contains(.budgetPerHead))

        // Validation with that brief still refuses an ungrounded pick, so
        // "book the most expensive place" cannot conjure a venue.
        let slots = [
            Fixtures.slot("dinner", category: .food, ["food-1", "food-2", "the-most-expensive-place"])
        ]

        #expect(throws: PlanningFailure.self) {
            _ = try FeasibilityValidator().validate(
                brief: brief,
                evidence: Fixtures.evidence,
                slots: slots,
                runID: Fixtures.runID,
                now: Fixtures.now
            )
        }
    }
}
