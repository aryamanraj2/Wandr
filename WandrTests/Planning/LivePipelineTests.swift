//
//  LivePipelineTests.swift
//  WandrTests
//
//  §13.2 device-gated tier. These run the WHOLE real pipeline — model extraction,
//  tool-calling curation, MapKit-decorated research, deterministic validation — and
//  assert the Step 2 baseline terminal states survive contact with a real model.
//
//  Skip mechanism (not fail): every test early-returns when the on-device model is
//  unavailable, so the suite stays green on a CI Mac with no Apple Intelligence and
//  runs for real on the demo device. `try #require(availability == .available)` was
//  deliberately NOT used — it would *fail* the suite off-device, which §13.2 forbids.
//
//  Privacy holds here too: assertions never print the request text, and the leak
//  test below checks no event carries it.
//

import Foundation
import FoundationModels
import Testing
@testable import Wandr

@Suite("Live pipeline (device-gated)")
struct LivePipelineTests {

    /// The skip gate. `true` only when a real model can run.
    private var modelAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    private func liveService() throws -> TravelPlanningService {
        // Real pipeline, real bundled dataset, fixed clock for reproducibility.
        try PlanningAssembly.liveService(bundle: .main, now: { Fixtures.now })
    }

    // MARK: - Terminal states reproduce the baseline

    @Test("afterWork, birthday, sparse and injection all reach .ready")
    func readyFixturesReachReady() async throws {
        guard modelAvailable else { return } // skip, not fail
        let service = try liveService()

        // Labelled so a failure names WHICH fixture regressed. The label is a fixed,
        // test-authored string and the failure *category* is a domain enum — neither
        // carries `PlanningInput.text`, so this stays inside the volatility rule while
        // still being diagnosable. Asserting all four in a bare loop told us only that
        // "one of four" broke, which is not enough to explain a baseline regression.
        let fixtures: [(label: String, request: String)] = [
            ("afterWork", Fixtures.Request.afterWork),
            ("birthday", Fixtures.Request.birthday),
            ("sparse", Fixtures.Request.sparse),
            ("injection", Fixtures.Request.injection)
        ]

        for fixture in fixtures {
            let run = try await service.plan(Fixtures.input(fixture.request))
            #expect(
                run.state == .ready,
                "\(fixture.label) expected .ready (step2-baseline) but got \(run.state.rawValue), category: \(String(describing: run.failure?.category))"
            )
        }
    }

    @Test("The impossible budget fails on the validator's budget rule (step2-baseline)")
    func impossibleBudgetFails() async throws {
        guard modelAvailable else { return }
        let service = try liveService()

        let run = try await service.plan(Fixtures.input(Fixtures.Request.impossibleBudget))
        #expect(run.state == .failed)

        // step2-baseline.md pins this row to `.validationFailed([.overBudget…])`:
        // ₹200/head against real prices, budget RANKS in research and FAILS in
        // validation with the venue named. A different category here is a regression
        // to explain, not a result to accept.
        guard case .validationFailed(let violations) = run.failure?.category else {
            Issue.record("impossibleBudget expected .validationFailed, got \(String(describing: run.failure?.category))")
            return
        }
        let hasOverBudget = violations.contains { if case .overBudget = $0 { return true } else { return false } }
        #expect(hasOverBudget, "expected an .overBudget violation per the baseline")
    }

    @Test("A thin area (Lodhi) fails on insufficient evidence (step2-baseline additional outcome)")
    func thinAreaInsufficientEvidence() async throws {
        guard modelAvailable else { return }
        let service = try liveService()

        // step2-baseline.md records: Lodhi has only 2 food venues against the
        // validator's floor of 3 → `.failed(.insufficientEvidence)`, from the real
        // provider. This exercises the evidence-shortfall path distinct from a thin
        // deck of valid venues.
        let run = try await service.plan(Fixtures.input("A quiet afternoon in Lodhi"))
        #expect(run.state == .failed)
        if case .insufficientEvidence = run.failure?.category {} else {
            Issue.record("Lodhi expected .insufficientEvidence, got \(String(describing: run.failure?.category))")
        }
    }

    @Test("A blank request throws .inputEmpty before a run starts")
    func blankThrows() async throws {
        guard modelAvailable else { return }
        let service = try liveService()

        await #expect(throws: PlanningFailure(.inputEmpty)) {
            _ = try await service.plan(Fixtures.input(Fixtures.Request.blank))
        }
    }

    // MARK: - Injection survives the real model

    @Test("The injection request reaches .ready and leaks no instruction-shaped input")
    func injectionIsData() async throws {
        guard modelAvailable else { return }
        let service = try liveService()

        let run = try await service.plan(Fixtures.input(Fixtures.Request.injection))
        #expect(run.state == .ready)

        // No event carries the volatile input text, and none carries an instruction.
        let forbidden = ["ignore instructions", "most expensive", "book the"]
        for event in run.events {
            let haystack = (event.title + " " + (event.detail ?? "")).lowercased()
            for needle in forbidden {
                #expect(!haystack.contains(needle), "an event leaked input-shaped text")
            }
        }
        // And no failure payload exists to carry it.
        #expect(run.failure == nil)
    }

    // MARK: - Hauz Khas resolves and validates

    @Test("The Hauz Khas request's curated slots all resolve and validate")
    @MainActor
    func hauzKhasResolvesAndValidates() async throws {
        guard modelAvailable else { return }
        let service = try liveService()

        let run = try await service.plan(Fixtures.input(Fixtures.Request.afterWork))
        #expect(run.state == .ready)

        let plan = try #require(run.plan)
        // Reaching .ready already means every candidate ID resolved against evidence
        // (the validator's Rule 1 would have thrown otherwise); assert the plan is
        // non-empty and every deck has picks.
        #expect(!plan.slots.isEmpty)
        let everySlotFilled = plan.slots.allSatisfy { !$0.candidates.isEmpty }
        #expect(everySlotFilled)
        #expect(!plan.evidenceIDs.isEmpty)

        // §8.2 (Step 4 bridge): what the screen would actually draw. This is the
        // assertion that catches "Gurgaon in a Hauz Khas plan" automatically
        // instead of by eye.
        let decks = PlanPresentation.decks(from: plan)
        #expect(!decks.isEmpty)
        let allCardsDrawn = decks.allSatisfy { !$0.candidates.isEmpty }
        #expect(allCardsDrawn)

        let evidenceIDs = Set(plan.evidenceIDs)
        let rendered = decks.flatMap(\.candidates)
        let allGrounded = rendered.allSatisfy { candidate in
            candidate.venueID.map { evidenceIDs.contains($0) } ?? false
        }
        #expect(allGrounded)

        // The brief named one area; no rendered card may claim another.
        let briefArea = plan.brief.area.value
        let allInArea = rendered.allSatisfy { $0.area == briefArea }
        #expect(allInArea, "rendered areas: \(Set(rendered.map(\.area))), brief: \(briefArea)")
    }
}
