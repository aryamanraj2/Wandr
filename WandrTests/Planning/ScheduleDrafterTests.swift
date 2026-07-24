//
//  ScheduleDrafterTests.swift
//  WandrTests
//
//  Every number on a block must be traceable to a disclosed assumption.
//

import Foundation
import Testing
@testable import Wandr

@Suite("Schedule drafter")
struct ScheduleDrafterTests {

    private let drafter = ScheduleDrafter()
    private let validator = FeasibilityValidator()

    /// A real plan, produced by the unchanged Step 1 validator rather than
    /// hand-built — the drafter must work on what validation actually emits.
    private func validatedPlan(
        brief: OutingBrief = Fixtures.afterWorkBrief,
        evidence: [GroundedVenue] = Fixtures.evidence,
        slots: [CurationSlot] = Fixtures.validSlots
    ) throws -> WandrPlan {
        try validator.validate(
            brief: brief,
            evidence: evidence,
            slots: slots,
            runID: Fixtures.runID,
            now: Fixtures.now
        )
    }

    // MARK: - Blocks

    @Test("One block per slot")
    func oneBlockPerSlot() throws {
        let plan = try validatedPlan()
        let draft = try drafter.draftSchedule(for: plan, evidence: Fixtures.evidence)

        #expect(draft.blocks.count == plan.slots.count)
        #expect(Set(draft.blocks.map(\.slotID)) == Set(plan.slots.map(\.slotID)))
        #expect(draft.planID == plan.id)
    }

    @Test("Every block takes the rank-1 candidate")
    func blocksUseTheLeadingCandidate() throws {
        let plan = try validatedPlan()
        let draft = try drafter.draftSchedule(for: plan, evidence: Fixtures.evidence)

        for slot in plan.slots {
            let block = try #require(draft.blocks.first { $0.slotID == slot.slotID })
            let leading = try #require(slot.candidates.first { $0.rank == 1 })
            #expect(block.venueID == leading.venueID)
        }
    }

    @Test("Every block resolves its title and category from the evidence snapshot")
    func blocksResolveAgainstEvidence() throws {
        let plan = try validatedPlan()
        let draft = try drafter.draftSchedule(for: plan, evidence: Fixtures.evidence)

        for block in draft.blocks {
            let venue = try #require(Fixtures.evidence.first { $0.venueID == block.venueID })
            #expect(block.title == venue.name)
            #expect(block.category == venue.category)
            #expect(!block.title.isEmpty)
        }
    }

    @Test("A block's category matches its slot's category")
    func blockCategoryMatchesSlot() throws {
        let plan = try validatedPlan()
        let draft = try drafter.draftSchedule(for: plan, evidence: Fixtures.evidence)

        for slot in plan.slots {
            let block = try #require(draft.blocks.first { $0.slotID == slot.slotID })
            #expect(block.category == slot.category)
        }
    }

    // MARK: - Disclosure
    //
    // The centrepiece: no silent numbers.

    @Test("Every block's start and duration is explainable by a disclosed assumption")
    func everyNumberIsDisclosed() throws {
        let plan = try validatedPlan()
        let draft = try drafter.draftSchedule(for: plan, evidence: Fixtures.evidence)

        for block in draft.blocks {
            #expect(
                draft.discloses(block),
                "Start \(block.startMinute) / duration \(block.durationMinutes) for \(block.slotID) is not disclosed"
            )
        }
    }

    @Test("travelTimeNotVerified and singleDayAssumed ride on every draft")
    func standingAssumptionsArePresent() throws {
        let plan = try validatedPlan()
        let draft = try drafter.draftSchedule(for: plan, evidence: Fixtures.evidence)

        #expect(draft.assumptions.contains(.travelTimeNotVerified))
        #expect(draft.assumptions.contains(.singleDayAssumed))
    }

    @Test("The standing assumptions survive even a single-slot plan")
    func standingAssumptionsSurviveThinPlans() throws {
        let slots = [Fixtures.slot("dinner", category: .food, ["food-1", "food-2", "food-3"])]
        let plan = try validatedPlan(slots: slots)
        let draft = try drafter.draftSchedule(for: plan, evidence: Fixtures.evidence)

        #expect(draft.blocks.count == 1)
        #expect(draft.assumptions.contains(.travelTimeNotVerified))
        #expect(draft.assumptions.contains(.singleDayAssumed))
    }

    // MARK: - The template

    @Test("Categories land on their disclosed template slots")
    func templateStartsAreApplied() throws {
        let slots = [
            Fixtures.slot("dinner", category: .food, ["food-1", "food-2", "food-3"]),
            Fixtures.slot("late", category: .nightlife, ["night-1", "night-2", "night-3"]),
            Fixtures.slot("day", category: .sights, ["sight-1", "sight-2", "sight-3"])
        ]
        let plan = try validatedPlan(slots: slots)
        let draft = try drafter.draftSchedule(for: plan, evidence: Fixtures.evidence)

        func start(_ slotID: String) throws -> Int {
            try #require(draft.blocks.first { $0.slotID == SlotID(slotID) }).startMinute
        }

        #expect(try start("day") == 12 * 60 + 30)
        #expect(try start("dinner") == 20 * 60)
        #expect(try start("late") == 22 * 60)
    }

    @Test("Blocks come back in chronological order")
    func blocksAreChronological() throws {
        let slots = [
            Fixtures.slot("late", category: .nightlife, ["night-1", "night-2", "night-3"]),
            Fixtures.slot("day", category: .sights, ["sight-1", "sight-2", "sight-3"]),
            Fixtures.slot("dinner", category: .food, ["food-1", "food-2", "food-3"])
        ]
        let plan = try validatedPlan(slots: slots)
        let draft = try drafter.draftSchedule(for: plan, evidence: Fixtures.evidence)

        let starts = draft.blocks.map(\.startMinute)
        #expect(starts == starts.sorted(), "Blocks must not depend on curation order")
    }

    @Test("Two slots of one category do not collide, and both starts are disclosed")
    func sameCategorySlotsAreSpread() throws {
        let slots = [
            Fixtures.slot("dinner", category: .food, ["food-1", "food-2", "food-3"]),
            Fixtures.slot("supper", category: .food, ["food-4", "food-2", "food-3"])
        ]
        // Reuse across slots is what this test is not about, so allow it.
        let plan = try FeasibilityValidator(
            rules: FeasibilityRules(allowsVenueReuseAcrossSlots: true)
        ).validate(
            brief: Fixtures.afterWorkBrief,
            evidence: Fixtures.evidence,
            slots: slots,
            runID: Fixtures.runID,
            now: Fixtures.now
        )
        let draft = try drafter.draftSchedule(for: plan, evidence: Fixtures.evidence)

        let starts = draft.blocks.map(\.startMinute)
        #expect(Set(starts).count == starts.count, "Two stops must not start at the same minute")
        for block in draft.blocks {
            #expect(draft.discloses(block))
        }
    }

    @Test("Drafting is deterministic")
    func draftingIsDeterministic() throws {
        let plan = try validatedPlan()
        let first = try drafter.draftSchedule(for: plan, evidence: Fixtures.evidence)
        let second = try drafter.draftSchedule(for: plan, evidence: Fixtures.evidence)
        #expect(first == second)
    }

    // MARK: - Warnings

    @Test("Every plan warning is carried forward unchanged")
    func warningsAreCarriedForward() throws {
        // An unknown cost and unknown hours both produce warnings on the plan.
        let evidence = [
            Fixtures.venue("food-1", category: .food, perHead: nil),
            Fixtures.venue("food-2", category: .food, hours: .unknown),
            Fixtures.venue("food-3", category: .food, availability: .unknown)
        ]
        let slots = [Fixtures.slot("dinner", category: .food, ["food-1", "food-2", "food-3"])]
        let plan = try validatedPlan(evidence: evidence, slots: slots)
        let draft = try drafter.draftSchedule(for: plan, evidence: evidence)

        #expect(!plan.warnings.isEmpty, "This fixture is meant to produce warnings")
        #expect(draft.warnings == plan.warnings, "Warnings must survive drafting unchanged")
    }

    @Test("The drafter adds no warnings of its own in this step")
    func drafterAddsNoWarnings() throws {
        let plan = try validatedPlan()
        let draft = try drafter.draftSchedule(for: plan, evidence: Fixtures.evidence)
        #expect(draft.warnings.count == plan.warnings.count)
    }

    // MARK: - Evidence gaps

    @Test("A candidate missing from the evidence snapshot is named, not dropped")
    func missingEvidenceIsReported() throws {
        let plan = try validatedPlan()
        // Hand the drafter a snapshot that cannot resolve the picks.
        #expect(throws: PlanningFailure.self) {
            _ = try drafter.draftSchedule(for: plan, evidence: [])
        }
    }

    // MARK: - Span

    @Test("The draft reports a span covering every block")
    func spanCoversAllBlocks() throws {
        let plan = try validatedPlan()
        let draft = try drafter.draftSchedule(for: plan, evidence: Fixtures.evidence)

        let start = try #require(draft.startMinute)
        let end = try #require(draft.endMinute)
        #expect(start == draft.blocks.map(\.startMinute).min())
        #expect(end == draft.blocks.map(\.endMinute).max())
        #expect(end > start)
    }
}

// MARK: - Disclosure helper

private extension ScheduleDraft {

    /// Whether both of `block`'s numbers are accounted for by some assumption.
    ///
    /// The drafter discloses a stop two different ways depending on where its
    /// numbers came from: `.defaultStartMinute` + `.defaultDuration` for a template
    /// default, or a single `.windowConstrained` when the host's own time window
    /// decided them. Both are disclosures — the rule these tests defend is "no
    /// silent numbers", not "one particular assumption case".
    func discloses(_ block: ScheduleDraftBlock) -> Bool {
        let windowConstrained = assumptions.contains(
            .windowConstrained(
                startMinute: block.startMinute,
                durationMinutes: block.durationMinutes,
                slotID: block.slotID
            )
        )
        guard !windowConstrained else { return true }

        return assumptions.contains(.defaultStartMinute(block.startMinute))
            && assumptions.contains(
                .defaultDuration(minutes: block.durationMinutes, slotID: block.slotID)
            )
    }
}
