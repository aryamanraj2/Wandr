//
//  TravelPlanningService.swift
//  Wandr
//
//  The single owner of a planning run.
//
//  Nothing else in the app mutates a `PlanningRun`. Every phase change here goes
//  through `PlanningRun.transition(to:)`, which means an illegal phase change is a
//  thrown `IllegalPlanningTransition` rather than a possibility this file has to
//  remember to prevent. That throw is treated as a programmer error — it means the
//  coordinator is wired wrong, not that the host did anything invalid.
//
//  Foundation only. This file must never learn whether a brief came from a live
//  Foundation Models session or from `FakeBriefExtractor`.
//
//  Privacy: `PlanningInput.text` reaches exactly one dependency — the extractor —
//  and is never recorded. Every event title and detail in this file is a fixed
//  string authored here, with no interpolation of input or of any service's output.
//

import Foundation

// MARK: - Storage stub

/// The no-op store this slice specifies. SwiftData is much later, and nothing in
/// the planning core may depend on it existing.
nonisolated struct NoOpPlanningRunStore: PlanningRunStoring, Sendable {
    init() {}
    func store(_ plan: WandrPlan) async throws {}
}

// MARK: - Coordinator

/// Drives one `PlanningRun` through the state table by calling six injected
/// services in a fixed order.
///
/// An `actor` because cancellation races the run even when every dependency in
/// this step is synchronous or fake.
actor TravelPlanningService {

    // MARK: Dependencies

    private let extractor: any BriefExtracting
    private let normalizer: any BriefNormalizing
    private let researcher: any VenueResearching
    private let curator: any ItineraryCurating
    private let validator: any ItineraryValidating
    private let scheduler: any ScheduleDrafting
    private let store: any PlanningRunStoring

    /// Injected so tests get a fixed clock.
    private let now: @Sendable () -> Date

    // MARK: State

    /// Runs the host has asked to stop. Checked between phases, never mid-phase.
    private var cancellationRequests: Set<PlanningRunID> = []
    /// Schedules produced by finished runs. `PlanningRun` has no schedule field —
    /// it is Step 1's and closed — so the draft is held here and fetched by ID.
    private var schedules: [PlanningRunID: ScheduleDraft] = [:]

    init(
        extractor: any BriefExtracting,
        normalizer: any BriefNormalizing = BriefNormalizer(),
        researcher: any VenueResearching,
        curator: any ItineraryCurating,
        validator: any ItineraryValidating = FeasibilityValidator(),
        scheduler: any ScheduleDrafting = ScheduleDrafter(),
        store: any PlanningRunStoring = NoOpPlanningRunStore(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.extractor = extractor
        self.normalizer = normalizer
        self.researcher = researcher
        self.curator = curator
        self.validator = validator
        self.scheduler = scheduler
        self.store = store
        self.now = now
    }

    // MARK: - Entry point

    /// Runs one plan from start to finish.
    ///
    /// - Parameters:
    ///   - input: the volatile request. Its text reaches the extractor and nothing else.
    ///   - runID: supplied by the caller so cancellation can be requested for a run
    ///     that has not returned yet.
    /// - Returns: the finished run, in `.ready`, `.failed`, or `.cancelled`.
    ///   (`.needsDetails` is also possible in principle, but no live configuration
    ///   produces it — see `BriefNormalizer`.)
    /// - Throws: `PlanningFailure(.inputEmpty)`, and *only* that. It is raised by
    ///   `PlanningInput.validated()` before a run ever leaves `.idle`, which is why
    ///   it cannot be reported as a `.failed` run: the state table has no
    ///   `idle → failed` edge. Every failure a dependency throws after that point is
    ///   caught here and attached to the returned run instead of propagating.
    @discardableResult
    func plan(
        _ input: PlanningInput,
        runID: PlanningRunID = PlanningRunID()
    ) async throws -> PlanningRun {

        // First move: validate. Not "transition, then validate".
        let validated = try input.validated()

        var run = PlanningRun(id: runID, input: validated, startedAt: now())

        do {
            return try await drive(&run, input: validated)
        } catch let failure as PlanningFailure {
            // Every dependency failure lands on the run, never past this point.
            attemptFail(&run, failure)
            return run
        } catch {
            // No dependency in this slice throws anything else. If one ever does,
            // it is a wiring bug, not a host-actionable failure.
            assertionFailure("Non-PlanningFailure escaped a dependency: \(error)")
            attemptFail(&run, PlanningFailure(.structuredOutputDecodingFailed))
            return run
        }
    }

    /// Requests cancellation of a run that may not have returned yet.
    ///
    /// Honored between phases. Nothing is interrupted mid-phase — none of this
    /// step's dependencies is long-running enough to need preemption.
    func requestCancellation(of runID: PlanningRunID) {
        cancellationRequests.insert(runID)
    }

    /// The schedule drafted for a finished run, if it reached `.ready`.
    func scheduleDraft(for runID: PlanningRunID) -> ScheduleDraft? {
        schedules[runID]
    }

    // MARK: - The run

    private func drive(_ run: inout PlanningRun, input: PlanningInput) async throws -> PlanningRun {

        // MARK: Extraction

        advance(&run, to: .extracting)
        run.record("Reading your request", at: now())

        if let cancelled = honorCancellation(&run) { return cancelled }

        // The one call that sees the host's words.
        let draft = try await extractor.extractBrief(from: input)

        // MARK: Normalization

        let outcome = try normalizer.normalize(draft)

        switch outcome {
        case .needsDetails(let partial, let missing):
            run.setBrief(partial)
            run.setMissingConstraints(missing)
            advance(&run, to: .needsDetails)
            run.record(
                "We need one more detail",
                detail: "Some constraints have no safe default.",
                severity: .limitation,
                at: now()
            )
            return run

        case .normalized(let brief):
            run.setBrief(brief)
            run.record("Understood what you're after", at: now())

            if let cancelled = honorCancellation(&run) { return cancelled }

            // MARK: Research

            advance(&run, to: .researching)
            let research = try await researcher.research(for: brief)
            for event in research.events {
                run.record(event)
            }

            if let cancelled = honorCancellation(&run) { return cancelled }

            // MARK: Curation, then validation of what curation proposed
            //
            // Order matters and is not the order of the state names. The validator
            // takes `slots:`, so curation must already have happened before the
            // `.validating` phase means anything. Getting this backwards would
            // validate Step 4's curator against evidence it was never shown.

            let slots = try await curator.curate(brief: brief, evidence: research.venues)

            advance(&run, to: .validating)
            run.record("Checking the plan holds up", at: now())

            let plan = try validator.validate(
                brief: brief,
                evidence: research.venues,
                slots: slots,
                runID: run.id,
                now: now()
            )

            if let cancelled = honorCancellation(&run) { return cancelled }

            advance(&run, to: .curating)
            run.record("Ranking your options", at: now())

            // MARK: Ready

            complete(&run, with: plan)
            run.record(
                "Your plan is ready",
                detail: plan.warnings.isEmpty ? nil : "Some details we couldn't confirm are flagged.",
                severity: plan.warnings.isEmpty ? .info : .warning,
                at: now()
            )

            // Scheduling runs only once the run has reached `.ready`.
            schedules[run.id] = try scheduler.draftSchedule(for: plan, evidence: research.venues)

            try? await store.store(plan)

            return run
        }
    }

    // MARK: - Cancellation

    /// Cancels the run if the host asked, returning the cancelled run.
    ///
    /// `PlanningRun.cancel()` already guarantees the brief and plan are discarded;
    /// this method's only job is to call it promptly and at a phase boundary.
    private func honorCancellation(_ run: inout PlanningRun) -> PlanningRun? {
        guard cancellationRequests.contains(run.id) || run.isCancellationRequested else {
            return nil
        }

        run.requestCancellation()
        do {
            try run.cancel()
        } catch {
            // `.cancelled` is reachable from every active phase, so this is a
            // wiring bug if it ever fires.
            preconditionFailure("Could not cancel from \(run.state): \(error)")
        }
        run.record("Planning stopped", at: now())
        cancellationRequests.remove(run.id)
        return run
    }

    // MARK: - Transitions
    //
    // `IllegalPlanningTransition` is a programmer error: it means this file walks
    // the state table wrongly. It is deliberately not converted into a
    // `PlanningFailure`, because there is nothing the host could do about it.

    private func advance(_ run: inout PlanningRun, to state: PlanningState) {
        do {
            try run.transition(to: state)
        } catch {
            preconditionFailure("Illegal transition \(run.state) → \(state): \(error)")
        }
    }

    private func complete(_ run: inout PlanningRun, with plan: WandrPlan) {
        do {
            try run.complete(with: plan)
        } catch {
            preconditionFailure("Could not complete from \(run.state): \(error)")
        }
    }

    /// Moves the run to `.failed`.
    ///
    /// A run that has already reached a terminal state cannot fail again — the
    /// table has no such edge — so a late failure on a cancelled run is dropped
    /// rather than crashing.
    private func attemptFail(_ run: inout PlanningRun, _ failure: PlanningFailure) {
        guard run.state.canTransition(to: .failed) else { return }
        do {
            try run.fail(failure)
            run.record(
                "We couldn't finish this plan",
                detail: "The run stopped before a plan was ready.",
                severity: .warning,
                at: now()
            )
        } catch {
            preconditionFailure("Could not fail from \(run.state): \(error)")
        }
    }
}
