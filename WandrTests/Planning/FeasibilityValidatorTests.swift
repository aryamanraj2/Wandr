//
//  FeasibilityValidatorTests.swift
//  WandrTests
//
//  The deterministic rules from `nonuistuff/plan.md` §10, one test per rule.
//
//  None of these tests touch a model, the network, the file system, or a UI
//  framework — which is the point. If this file ever needs a simulator to be
//  meaningful, the validator has grown a dependency it shouldn't have.
//

import Foundation
import Testing
@testable import Wandr

@Suite("FeasibilityValidator")
struct FeasibilityValidatorTests {

    let validator = FeasibilityValidator()

    // MARK: - Helpers

    /// Runs validation and returns the failure, or `nil` if it passed.
    private func validationFailure(
        brief: OutingBrief,
        evidence: [GroundedVenue] = Fixtures.evidence,
        slots: [CurationSlot],
        rules: FeasibilityRules = .default
    ) -> PlanningFailure? {
        do {
            _ = try FeasibilityValidator(rules: rules).validate(
                brief: brief,
                evidence: evidence,
                slots: slots,
                runID: Fixtures.runID,
                now: Fixtures.now
            )
            return nil
        } catch let failure as PlanningFailure {
            return failure
        } catch {
            return nil
        }
    }

    private func violations(
        brief: OutingBrief,
        evidence: [GroundedVenue] = Fixtures.evidence,
        slots: [CurationSlot],
        rules: FeasibilityRules = .default
    ) -> [FeasibilityViolation] {
        guard
            let failure = validationFailure(brief: brief, evidence: evidence, slots: slots, rules: rules),
            case .validationFailed(let violations) = failure.category
        else { return [] }
        return violations
    }

    private func validatedPlan(
        brief: OutingBrief,
        evidence: [GroundedVenue] = Fixtures.evidence,
        slots: [CurationSlot]
    ) throws -> WandrPlan {
        try validator.validate(
            brief: brief,
            evidence: evidence,
            slots: slots,
            runID: Fixtures.runID,
            now: Fixtures.now
        )
    }

    // MARK: - Rule 1: every selected ID exists

    @Test("A valid, distinct, in-budget selection passes")
    func validSelectionPasses() throws {
        let plan = try validatedPlan(brief: Fixtures.afterWorkBrief, slots: Fixtures.validSlots)

        #expect(plan.runID == Fixtures.runID)
        #expect(plan.slots.count == 2)
        #expect(plan.generatedAt == Fixtures.now)
        #expect(plan.revision.revision == 1)

        // Fully surveyed, available, priced evidence produces nothing to warn about.
        #expect(plan.warnings.isEmpty)

        // Evidence IDs are the selected venues, deduplicated and sorted.
        #expect(plan.evidenceIDs == [
            VenueID("food-1"), VenueID("food-2"), VenueID("food-3"),
            VenueID("night-1"), VenueID("night-2"), VenueID("night-3")
        ])
        #expect(plan.evidenceSources == [Fixtures.source])
    }

    @Test("A venue ID absent from the evidence snapshot fails")
    func nonexistentVenueIDFails() {
        let slots = [
            Fixtures.slot("dinner", category: .food, ["food-1", "food-2", "not-a-real-venue"]),
            Fixtures.slot("late", category: .nightlife, ["night-1", "night-2", "night-3"])
        ]

        let found = violations(brief: Fixtures.afterWorkBrief, slots: slots)

        #expect(found.contains(.unknownVenue(slotID: SlotID("dinner"), venueID: VenueID("not-a-real-venue"))))
    }

    @Test("A model-invented venue never reaches a plan, even when everything else is valid")
    func inventedVenueBlocksThePlan() {
        let slots = [
            Fixtures.slot("dinner", category: .food, ["food-1", "food-2", "Some Lovely Rooftop"]),
            Fixtures.slot("late", category: .nightlife, ["night-1", "night-2", "night-3"])
        ]

        #expect(validationFailure(brief: Fixtures.afterWorkBrief, slots: slots) != nil)
    }

    // MARK: - Rule 2 & 3: duplicates

    @Test("A duplicate venue inside one deck fails")
    func duplicateWithinSlotFails() {
        let slots = [
            Fixtures.slot("dinner", category: .food, ["food-1", "food-2", "food-1"]),
            Fixtures.slot("late", category: .nightlife, ["night-1", "night-2", "night-3"])
        ]

        let found = violations(brief: Fixtures.afterWorkBrief, slots: slots)

        #expect(found.contains(.duplicateWithinSlot(slotID: SlotID("dinner"), venueID: VenueID("food-1"))))
    }

    @Test("The same venue filling two slots fails")
    func duplicateAcrossSlotsFails() {
        let slots = [
            Fixtures.slot("dinner", category: .food, ["food-1", "food-2", "food-3"]),
            Fixtures.slot("late", category: .nightlife, ["food-1", "night-2", "night-3"])
        ]

        let found = violations(brief: Fixtures.afterWorkBrief, slots: slots)

        #expect(found.contains(
            .duplicateAcrossSlots(venueID: VenueID("food-1"), slotIDs: [SlotID("dinner"), SlotID("late")])
        ))
    }

    @Test("Venue reuse across slots passes when the rules permit it")
    func duplicateAcrossSlotsAllowedByRule() {
        let slots = [
            Fixtures.slot("dinner", category: .food, ["food-1", "food-2", "food-3"]),
            Fixtures.slot("late", category: .nightlife, ["food-1", "night-2", "night-3"])
        ]

        let permissive = FeasibilityRules(minimumCandidatesPerSlot: 3, allowsVenueReuseAcrossSlots: true)

        #expect(validationFailure(brief: Fixtures.afterWorkBrief, slots: slots, rules: permissive) == nil)
    }

    // MARK: - Rule 4: budget

    @Test("A known per-head price over the confirmed ceiling fails")
    func overBudgetChoiceFails() {
        let evidence = Fixtures.evidence + [
            Fixtures.venue("food-lux", category: .food, perHead: 4_000)
        ]
        let slots = [
            Fixtures.slot("dinner", category: .food, ["food-1", "food-2", "food-lux"]),
            Fixtures.slot("late", category: .nightlife, ["night-1", "night-2", "night-3"])
        ]

        let found = violations(brief: Fixtures.afterWorkBrief, evidence: evidence, slots: slots)

        #expect(found.contains(
            .overBudget(
                slotID: SlotID("dinner"),
                venueID: VenueID("food-lux"),
                perHeadRupees: 4_000,
                limitRupees: 1_500
            )
        ))
    }

    @Test("A price exactly at the ceiling passes")
    func priceAtTheLimitPasses() {
        let evidence = Fixtures.evidence + [
            Fixtures.venue("food-edge", category: .food, perHead: 1_500)
        ]
        let slots = [
            Fixtures.slot("dinner", category: .food, ["food-1", "food-2", "food-edge"]),
            Fixtures.slot("late", category: .nightlife, ["night-1", "night-2", "night-3"])
        ]

        #expect(validationFailure(brief: Fixtures.afterWorkBrief, evidence: evidence, slots: slots) == nil)
    }

    @Test("An unknown cost warns rather than failing, and is never guessed")
    func unknownCostWarnsInsteadOfFailing() throws {
        let evidence = Fixtures.evidence + [
            Fixtures.venue("food-unpriced", category: .food, perHead: nil)
        ]
        let slots = [
            Fixtures.slot("dinner", category: .food, ["food-1", "food-2", "food-unpriced"]),
            Fixtures.slot("late", category: .nightlife, ["night-1", "night-2", "night-3"])
        ]

        let plan = try validatedPlan(brief: Fixtures.afterWorkBrief, evidence: evidence, slots: slots)

        #expect(plan.warnings.contains(
            PlanWarning(.unknownCost(VenueID("food-unpriced")), slotID: SlotID("dinner"))
        ))

        // The unknown stayed unknown — no number was invented for it.
        let unpriced = try #require(evidence.first { $0.venueID == VenueID("food-unpriced") })
        #expect(unpriced.cost == .unknown)
        #expect(unpriced.cost.knownPerHeadRupees == nil)
        #expect(unpriced.cost.savingsRupees == nil)
    }

    // MARK: - Rule 5: hard constraints

    @Test("A surveyed venue that misses a hard dietary requirement fails")
    func unmetDietaryConstraintFails() {
        let evidence = [
            Fixtures.venue("food-1", category: .food, dietary: .known([.vegetarian])),
            Fixtures.venue("food-2", category: .food, dietary: .known([.vegetarian])),
            // Surveyed, and vegetarian is genuinely absent.
            Fixtures.venue("food-meat", category: .food, dietary: .known([.halal]))
        ]
        let slots = [Fixtures.slot("dinner", category: .food, ["food-1", "food-2", "food-meat"])]

        let found = violations(brief: Fixtures.birthdayBrief, evidence: evidence, slots: slots)

        #expect(found.contains(
            .unmetDietaryRequirement(
                slotID: SlotID("dinner"),
                venueID: VenueID("food-meat"),
                missing: [.vegetarian]
            )
        ))
    }

    @Test("An unsurveyed venue warns rather than failing a dietary requirement")
    func unverifiedDietaryWarns() throws {
        let evidence = [
            Fixtures.venue("food-1", category: .food, dietary: .known([.vegetarian])),
            Fixtures.venue("food-2", category: .food, dietary: .known([.vegetarian])),
            // Never surveyed — unverified, not contradicted.
            Fixtures.venue("food-unknown", category: .food, dietary: .unknown)
        ]
        let slots = [Fixtures.slot("dinner", category: .food, ["food-1", "food-2", "food-unknown"])]

        let plan = try validatedPlan(brief: Fixtures.birthdayBrief, evidence: evidence, slots: slots)

        #expect(plan.warnings.contains(
            PlanWarning(
                .unverifiedDietary(VenueID("food-unknown"), required: [.vegetarian]),
                slotID: SlotID("dinner")
            )
        ))
    }

    @Test("A surveyed venue that misses a hard accessibility requirement fails")
    func unmetAccessibilityConstraintFails() {
        let evidence = [
            Fixtures.venue("sight-1", category: .sights, accessibility: .known([.stepFreeEntry])),
            Fixtures.venue("sight-2", category: .sights, accessibility: .known([.stepFreeEntry])),
            Fixtures.venue("sight-steps", category: .sights, accessibility: .known([.accessibleRestroom]))
        ]
        let slots = [Fixtures.slot("afternoon", category: .sights, ["sight-1", "sight-2", "sight-steps"])]

        let found = violations(brief: Fixtures.accessibleBrief, evidence: evidence, slots: slots)

        #expect(found.contains(
            .unmetAccessibilityRequirement(
                slotID: SlotID("afternoon"),
                venueID: VenueID("sight-steps"),
                missing: [.stepFreeEntry]
            )
        ))
    }

    @Test("An indoor venue fails an explicit outdoor preference")
    func unmetSettingConstraintFails() {
        let evidence = [
            Fixtures.venue("sight-1", category: .sights, setting: .outdoor),
            Fixtures.venue("sight-2", category: .sights, setting: .mixed),
            Fixtures.venue("sight-indoor", category: .sights, setting: .indoor)
        ]
        let slots = [Fixtures.slot("afternoon", category: .sights, ["sight-1", "sight-2", "sight-indoor"])]

        let found = violations(brief: Fixtures.outdoorBrief, evidence: evidence, slots: slots)

        #expect(found.contains(
            .unmetSettingPreference(
                slotID: SlotID("afternoon"),
                venueID: VenueID("sight-indoor"),
                preference: .outdoor,
                actual: .indoor
            )
        ))
    }

    @Test("A soft preference never gates evidence")
    func softSettingPreferenceDoesNotGate() {
        let evidence = [
            Fixtures.venue("sight-1", category: .sights, setting: .outdoor),
            Fixtures.venue("sight-2", category: .sights, setting: .indoor),
            Fixtures.venue("sight-3", category: .sights, setting: .unknown)
        ]
        let slots = [Fixtures.slot("afternoon", category: .sights, ["sight-1", "sight-2", "sight-3"])]

        // `.mixed` and `.noPreference` are soft by contract.
        #expect(SettingPreference.mixed.isHardConstraint == false)
        #expect(SettingPreference.noPreference.isHardConstraint == false)
        #expect(validationFailure(brief: Fixtures.sparseBrief, evidence: evidence, slots: slots) == nil)
    }

    // MARK: - Rule 6: deck depth

    @Test("A thin deck backed by a thin snapshot reports insufficient evidence")
    func thinEvidenceReportsInsufficientEvidence() throws {
        // Only two food venues exist at all — research came up short.
        let evidence = [
            Fixtures.venue("food-1", category: .food),
            Fixtures.venue("food-2", category: .food)
        ]
        let slots = [Fixtures.slot("dinner", category: .food, ["food-1", "food-2"])]

        let failure = try #require(validationFailure(brief: Fixtures.afterWorkBrief, evidence: evidence, slots: slots))

        guard case .insufficientEvidence(let details) = failure.category else {
            Issue.record("expected insufficientEvidence, got \(failure.category)")
            return
        }
        #expect(details == [
            PlanningFailure.InsufficientEvidenceDetail(category: .food, required: 3, found: 2)
        ])
        // It is never padded with invented venues.
        #expect(failure.retryAction == .editRequest)
    }

    @Test("A thin deck despite a rich snapshot is a curation failure, not missing evidence")
    func thinCurationReportsInsufficientCandidates() {
        // Four food venues exist; the curator only picked two.
        let slots = [Fixtures.slot("dinner", category: .food, ["food-1", "food-2"])]

        let found = violations(brief: Fixtures.afterWorkBrief, slots: slots)

        #expect(found == [
            .insufficientCandidates(slotID: SlotID("dinner"), required: 3, found: 2)
        ])
    }

    @Test("An empty curation fails rather than producing an empty plan")
    func emptyCurationFails() {
        let found = violations(brief: Fixtures.afterWorkBrief, slots: [])

        #expect(found == [.emptyCuration])
    }

    // MARK: - Rule 7: savings arithmetic

    @Test("Savings are max(listPrice - perHead, 0) and never guessed")
    func savingsMathIsDeterministic() {
        #expect(VenueCost.known(perHeadRupees: 1_100, listPriceRupees: 1_400).savingsRupees == 300)

        // Never negative.
        #expect(VenueCost.known(perHeadRupees: 1_400, listPriceRupees: 1_100).savingsRupees == 0)

        // Equal prices mean no saving, not nil.
        #expect(VenueCost.known(perHeadRupees: 1_000, listPriceRupees: 1_000).savingsRupees == 0)

        // Unknown inputs produce no number at all.
        #expect(VenueCost.known(perHeadRupees: 1_100, listPriceRupees: nil).savingsRupees == nil)
        #expect(VenueCost.unknown.savingsRupees == nil)
    }

    // MARK: - Rule 8: warnings survive

    @Test("Every validator warning is attached to the plan")
    func warningsSurviveOntoThePlan() throws {
        let evidence = [
            Fixtures.venue("food-1", category: .food),
            Fixtures.venue("food-2", category: .food),
            Fixtures.venue(
                "food-3",
                category: .food,
                perHead: nil,
                availability: .unknown,
                hours: .unknown,
                limitations: ["Kitchen closes early on weekdays."]
            )
        ]
        let slots = [Fixtures.slot("dinner", category: .food, ["food-1", "food-2", "food-3"])]

        let plan = try validatedPlan(brief: Fixtures.afterWorkBrief, evidence: evidence, slots: slots)

        let flagged = VenueID("food-3")
        #expect(plan.warnings.contains(PlanWarning(.unknownCost(flagged), slotID: SlotID("dinner"))))
        #expect(plan.warnings.contains(PlanWarning(.unknownAvailability(flagged), slotID: SlotID("dinner"))))
        #expect(plan.warnings.contains(PlanWarning(.unknownHours(flagged), slotID: SlotID("dinner"))))
        #expect(plan.warnings.contains(
            PlanWarning(
                .providerLimitation(flagged, detail: "Kitchen closes early on weekdays."),
                slotID: SlotID("dinner")
            )
        ))

        // And they are addressable the way the UI will need them.
        #expect(plan.warnings(for: SlotID("dinner")).count == plan.warnings.count)
        #expect(plan.warnings(about: flagged).count == 4)
        #expect(plan.warnings.allSatisfy { !$0.message.isEmpty })
    }

    @Test("An explicitly unavailable venue is surfaced, never silently dropped")
    func unavailableVenueIsSurfaced() throws {
        let evidence = [
            Fixtures.venue("food-1", category: .food),
            Fixtures.venue("food-2", category: .food),
            Fixtures.venue("food-3", category: .food, availability: .unavailable(reason: "Closed for renovation"))
        ]
        let slots = [Fixtures.slot("dinner", category: .food, ["food-1", "food-2", "food-3"])]

        let plan = try validatedPlan(brief: Fixtures.afterWorkBrief, evidence: evidence, slots: slots)

        #expect(plan.warnings.contains(
            PlanWarning(
                .venueUnavailable(VenueID("food-3"), reason: "Closed for renovation"),
                slotID: SlotID("dinner")
            )
        ))
    }

    // MARK: - Determinism

    @Test("Validating the same input twice produces the same violations, in the same order")
    func violationOrderIsStable() {
        let slots = [
            Fixtures.slot("dinner", category: .food, ["food-1", "ghost-a", "ghost-b"]),
            Fixtures.slot("late", category: .nightlife, ["ghost-c", "night-2", "food-1"])
        ]

        let first = violations(brief: Fixtures.afterWorkBrief, slots: slots)
        let second = violations(brief: Fixtures.afterWorkBrief, slots: slots)

        #expect(first == second)
        #expect(!first.isEmpty)
    }

    // MARK: - Fixture scenarios (plan.md §13.1)

    @Test("Impossible budget yields a clear limitation rather than a pretty itinerary")
    func impossibleBudgetIsRejected() throws {
        // Nothing in the snapshot comes in under ₹200 a head.
        let slots = [
            Fixtures.slot("dinner", category: .food, ["food-1", "food-2", "food-3"]),
            Fixtures.slot("late", category: .nightlife, ["night-1", "night-2", "night-3"])
        ]

        let failure = try #require(validationFailure(brief: Fixtures.impossibleBudgetBrief, slots: slots))

        guard case .validationFailed(let violations) = failure.category else {
            Issue.record("expected validationFailed, got \(failure.category)")
            return
        }

        // Every pick is over budget, and each one is named.
        #expect(violations.count == 6)
        #expect(violations.allSatisfy { violation in
            if case .overBudget = violation { return true }
            return false
        })
        #expect(failure.userMessage.contains("₹200"))
        #expect(failure.isRecoverable)
    }

    @Test("The sparse request's safe defaults are all marked as such")
    func sparseRequestMarksSafeDefaults() {
        let brief = Fixtures.sparseBrief

        #expect(brief.occasion.source == .safeDefault)
        #expect(brief.area.source == .safeDefault)
        #expect(brief.groupSize.source == .safeDefault)
        #expect(brief.budgetPerHead.source == .safeDefault)

        #expect(Set(brief.safeDefaults) == Set([.area, .timeWindow, .groupSize, .budgetPerHead]))

        // The host said nothing about these, and the brief does not pretend otherwise.
        #expect(brief.dietary == .unknown)
        #expect(brief.accessibility == .unknown)
        #expect(brief.timeWindow.value.isUnknown)
    }

    @Test("The after-work request keeps host-stated values attributed to the host")
    func afterWorkRequestAttributesHostValues() {
        let brief = Fixtures.afterWorkBrief

        #expect(brief.area.value == "Hauz Khas")
        #expect(brief.area.source == .host)
        #expect(brief.groupSize.value == GroupSize(clamping: 6))
        #expect(brief.groupSize.source == .host)
        #expect(brief.budgetPerHead.value == .upTo(rupees: 1_500))
        #expect(brief.budgetPerHead.source == .host)
        #expect(brief.safeDefaults.isEmpty)
    }

    @Test("The birthday request preserves the dietary requirement and the fixed end")
    func birthdayRequestPreservesHardConstraints() {
        let brief = Fixtures.birthdayBrief

        #expect(brief.dietary == .required([.vegetarian]))
        #expect(brief.dietary.isHardConstraint)
        #expect(brief.timeWindow.value.latestEndMinute == 21 * 60)
        #expect(brief.timeWindow.value.hasFixedEnd)
        #expect(brief.groupSize.value.people == 8)
    }

    @Test("Bounded values clamp rather than trusting extraction")
    func boundedValuesClamp() {
        #expect(GroupSize(clamping: 40_000).people == GroupSize.supportedRange.upperBound)
        #expect(GroupSize(clamping: 0).people == GroupSize.supportedRange.lowerBound)
        #expect(BudgetPerHead.clamping(rupees: -50) == .upTo(rupees: 0))
        #expect(BudgetPerHead.clamping(rupees: 9_999_999) == .upTo(rupees: BudgetPerHead.supportedRange.upperBound))
        #expect(BudgetPerHead.unspecified.limitRupees == nil)
    }
}
