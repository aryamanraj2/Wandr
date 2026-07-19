//
//  ScheduleWindowTests.swift
//  WandrTests
//
//  Two seams the time window touches downstream: the schedule drafter clamping a
//  block into the group's hour, and the grounded→UI mapping that carries the
//  model's rationale and the validator's caveats onto the card.
//

import Foundation
import Testing
@testable import Wandr

@Suite("Time window: schedule + display")
struct ScheduleWindowTests {

    private let validator = FeasibilityValidator()
    private let drafter = ScheduleDrafter()
    private let dinnerSlot = Fixtures.slot("dinner", category: .food, title: "Dinner", ["food-1", "food-2", "food-3"])

    private func brief(window: OutingTimeWindow?) -> OutingBrief {
        OutingBrief(
            timeWindow: window.map { .host($0) } ?? .safeDefault(.unknown),
            area: .host("Test Area"),
            groupSize: .host(GroupSize(clamping: 4))
        )
    }

    // MARK: - Drafter clamps to the window

    @Test("An 8–9 pm window clamps the dinner block to 60 minutes and discloses it")
    func windowClampsBlock() throws {
        let window = OutingTimeWindow(earliestStartMinute: 20 * 60, latestEndMinute: 21 * 60)
        let plan = try validator.validate(
            brief: brief(window: window),
            evidence: Fixtures.evidence,
            slots: [dinnerSlot],
            runID: Fixtures.runID,
            now: Fixtures.now
        )

        let draft = try drafter.draftSchedule(for: plan, evidence: Fixtures.evidence)

        let block = try #require(draft.blocks.first)
        #expect(block.startMinute == 20 * 60)
        #expect(block.durationMinutes == 60)
        #expect(block.endMinute == 21 * 60)
        #expect(draft.assumptions.contains(
            .windowConstrained(startMinute: 20 * 60, durationMinutes: 60, slotID: SlotID("dinner"))
        ))
    }

    @Test("An open plan falls back to the template default, not a clamp")
    func openPlanUsesTemplate() throws {
        let plan = try validator.validate(
            brief: brief(window: nil),
            evidence: Fixtures.evidence,
            slots: [dinnerSlot],
            runID: Fixtures.runID,
            now: Fixtures.now
        )

        let draft = try drafter.draftSchedule(for: plan, evidence: Fixtures.evidence)

        let block = try #require(draft.blocks.first)
        #expect(block.startMinute == 20 * 60)   // food template start
        #expect(block.durationMinutes == 90)
        #expect(draft.assumptions.contains(.defaultDuration(minutes: 90, slotID: SlotID("dinner"))))
        #expect(!draft.assumptions.contains {
            if case .windowConstrained = $0 { return true } else { return false }
        })
    }

    // MARK: - Grounded → UI mapping

    @Test("Mapping resolves venues, carries rationale, and flags unknown cost honestly")
    func mappingCarriesRationaleAndCaveats() throws {
        let venues = [
            Fixtures.venue("food-x", category: .food, perHead: nil),   // unknown cost
            Fixtures.venue("food-y", category: .food, perHead: 800),
            Fixtures.venue("food-z", category: .food, perHead: 900)
        ]
        let slot = CurationSlot(
            slotID: SlotID("dinner"),
            category: .food,
            title: "Dinner",
            candidates: [CuratedCandidate(venueID: VenueID("food-x"), rank: 1, rationale: "Great for a big group.")]
        )
        let plan = WandrPlan(
            runID: Fixtures.runID,
            brief: Fixtures.sparseBrief,
            slots: [slot],
            warnings: [PlanWarning(.unknownCost(VenueID("food-x")), slotID: SlotID("dinner"))],
            evidenceIDs: [VenueID("food-x")],
            evidenceSources: [],
            generatedAt: Fixtures.now
        )

        let output = GroundedPlanMapper.map(plan: plan, evidence: venues)

        #expect(output.decks.count == 1)
        #expect(output.banner == nil)   // sparse brief has no window

        let card = try #require(output.decks.first?.candidates.first)
        #expect(card.name == "Venue food-x")
        #expect(card.costUnknown)
        #expect(card.rationale == "Great for a big group.")
        #expect(card.warnings.contains { $0.localizedCaseInsensitiveContains("price") })
    }

    @Test("A pick whose venue isn't in evidence is dropped, never invented")
    func unknownVenueIsDropped() {
        let slot = CurationSlot(
            slotID: SlotID("dinner"),
            category: .food,
            title: "Dinner",
            candidates: [CuratedCandidate(venueID: VenueID("ghost"), rank: 1)]
        )
        let plan = WandrPlan(
            runID: Fixtures.runID,
            brief: Fixtures.sparseBrief,
            slots: [slot],
            warnings: [],
            evidenceIDs: [],
            evidenceSources: [],
            generatedAt: Fixtures.now
        )

        let output = GroundedPlanMapper.map(plan: plan, evidence: Fixtures.evidence)
        #expect(output.decks.isEmpty)   // no resolvable candidate ⇒ no deck
    }
}
