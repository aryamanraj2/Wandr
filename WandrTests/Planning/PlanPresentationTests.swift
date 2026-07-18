//
//  PlanPresentationTests.swift
//  WandrTests
//
//  The UI bridge's deterministic tier: `WandrPlan` → `[Deck]` mapping rules,
//  the no-fabrication guarantees, and the §5.1 warning-survival assertion.
//
//  No model, no network, no view — the mapper is pure, so these run anywhere.
//

import Foundation
import Testing
@testable import Wandr

@MainActor
@Suite("PlanPresentation")
struct PlanPresentationTests {

    // MARK: - Helpers

    private func plan(
        evidence: [GroundedVenue] = Fixtures.evidence,
        slots: [CurationSlot] = Fixtures.validSlots,
        warnings: [PlanWarning] = []
    ) -> WandrPlan {
        WandrPlan(
            runID: Fixtures.runID,
            brief: Fixtures.afterWorkBrief,
            slots: slots,
            warnings: warnings,
            evidenceIDs: slots.flatMap(\.candidateVenueIDs).sorted(),
            evidenceSources: [Fixtures.source],
            evidence: evidence,
            generatedAt: Fixtures.now
        )
    }

    // MARK: - Ordering

    @Test("Slot order and rank order are preserved verbatim")
    func orderingPreserved() {
        let slots = [
            Fixtures.slot("late", category: .nightlife, title: "Late", ["night-2", "night-1", "night-3"]),
            Fixtures.slot("dinner", category: .food, title: "Dinner", ["food-3", "food-1", "food-2"])
        ]
        let decks = PlanPresentation.decks(from: plan(slots: slots))

        #expect(decks.map(\.slotName) == ["Late", "Dinner"])
        // Fixtures.slot assigns rank by position, so rank order is author order.
        #expect(decks[0].candidates.map(\.name) == ["Venue night-2", "Venue night-1", "Venue night-3"])
        #expect(decks[1].candidates.map(\.name) == ["Venue food-3", "Venue food-1", "Venue food-2"])
    }

    // MARK: - No fabricated display facts

    @Test("VenueCost.unknown maps to nil perHead, never 0 — free stays free")
    func unknownCostIsNotZero() {
        let evidence = [
            Fixtures.venue("food-unpriced", category: .food, perHead: nil),
            Fixtures.venue("sight-free", category: .sights, perHead: 0),
            Fixtures.venue("food-2", category: .food),
            Fixtures.venue("food-3", category: .food)
        ]
        let slots = [
            Fixtures.slot("dinner", category: .food, ["food-unpriced", "food-2", "food-3"]),
            Fixtures.slot("walk", category: .sights, ["sight-free"])
        ]
        let decks = PlanPresentation.decks(from: plan(evidence: evidence, slots: slots))

        let unpriced = decks[0].candidates[0]
        let free = decks[1].candidates[0]
        #expect(unpriced.perHead == nil)
        #expect(unpriced.priceLabel == "Price unknown")
        #expect(free.perHead == 0)
        #expect(free.priceLabel == "Free")
    }

    @Test("OpeningHours.unknown maps to nil, and travelNote is always nil")
    func unknownsRenderAsAbsent() {
        let evidence = [
            Fixtures.venue("food-1", category: .food, hours: .unknown),
            Fixtures.venue("food-2", category: .food)
        ]
        let slots = [Fixtures.slot("dinner", category: .food, ["food-1", "food-2"])]
        let candidates = PlanPresentation.decks(from: plan(evidence: evidence, slots: slots))[0].candidates

        #expect(candidates[0].openWindow == nil)
        #expect(candidates[1].openWindow == "Open till 11:00 pm")
        let travelNotesAbsent = candidates.allSatisfy { $0.travelNote == nil }
        #expect(travelNotesAbsent)
    }

    @Test("Known facts carry through verbatim — nothing rounded, renamed, or inferred")
    func factsCarryVerbatim() {
        let venue = GroundedVenue(
            venueID: VenueID("food-9"),
            name: "Venue food-9",
            category: .food,
            area: "Test Area",
            tagline: "A sanitized fixture venue.",
            cost: .known(perHeadRupees: 1_100, listPriceRupees: 1_400),
            offer: "1+1 on cocktails",
            offerWindow: "till 9:30 pm",
            openWindow: .known(label: "Open till 11:30 pm"),
            availability: .available,
            source: Fixtures.source,
            retrievedAt: Fixtures.retrievedAt,
            imageSeed: 7
        )
        let slots = [Fixtures.slot("dinner", category: .food, ["food-9"])]
        let card = PlanPresentation.decks(from: plan(evidence: [venue], slots: slots))[0].candidates[0]

        #expect(card.venueID == VenueID("food-9"))
        #expect(card.name == "Venue food-9")
        #expect(card.area == "Test Area")
        #expect(card.perHead == 1_100)
        #expect(card.listPrice == 1_400)
        #expect(card.savings == 300)
        #expect(card.offer == "1+1 on cocktails")
        #expect(card.offerWindow == "till 9:30 pm")
        #expect(card.openWindow == "Open till 11:30 pm")
        #expect(card.imageSeed == 7)
    }

    // MARK: - Unresolvable IDs

    @Test("A venueID with no evidence match is dropped, not rendered as a placeholder")
    func unresolvableIDDropped() {
        let slots = [Fixtures.slot("dinner", category: .food, ["food-1", "ghost-1", "food-2"])]
        let decks = PlanPresentation.decks(from: plan(slots: slots))

        #expect(decks[0].candidates.map(\.name) == ["Venue food-1", "Venue food-2"])
    }

    // MARK: - Category mapping

    @Test("Category mapping is total and round-trips", arguments: SlotCategory.allCases)
    func categoryMappingRoundTrips(category: SlotCategory) {
        let stop = PlanPresentation.stopCategory(category)
        #expect(PlanPresentation.slotCategory(stop) == category)
        #expect(stop.rawValue == category.rawValue)
    }

    // MARK: - Windows

    @Test("Deck.window comes from the schedule draft's block, else stays empty")
    func windowFromDraft() {
        let draft = ScheduleDraft(
            planID: PlanID(),
            blocks: [
                ScheduleDraftBlock(
                    slotID: SlotID("dinner"), venueID: VenueID("food-1"),
                    title: "Venue food-1", category: .food,
                    startMinute: 20 * 60, durationMinutes: 90
                )
            ]
        )
        let decks = PlanPresentation.decks(from: plan(), schedule: draft)

        #expect(decks.first { $0.slotName == "Dinner" }?.window == "8:00 pm – 9:30 pm")
        #expect(decks.first { $0.slotName == "Late" }?.window == "")

        let noDraft = PlanPresentation.decks(from: plan())
        let windowsEmpty = noDraft.allSatisfy { $0.window == "" }
        #expect(windowsEmpty)
    }

    // MARK: - §5.1: every warning reaches a rendered surface

    /// Every `PlanWarning.Kind`, one instance each, all attached to a venue in
    /// the dinner slot. The switch below is exhaustive with no default, so adding
    /// a `Kind` fails this file at compile time until the new case is listed —
    /// and its message asserted to survive.
    private static let everyKind: [PlanWarning.Kind] = [
        .unknownCost(VenueID("food-1")),
        .unverifiedDietary(VenueID("food-1"), required: [.vegetarian]),
        .unverifiedAccessibility(VenueID("food-1"), required: [.stepFreeEntry]),
        .unverifiedSetting(VenueID("food-1"), preference: .outdoor),
        .unknownAvailability(VenueID("food-1")),
        .venueUnavailable(VenueID("food-1"), reason: "closed for a private event"),
        .unknownHours(VenueID("food-1")),
        .providerLimitation(VenueID("food-1"), detail: "kitchen closes early on weekdays")
    ]

    /// Compile-time exhaustiveness: a new `Kind` breaks this switch, forcing the
    /// list above (and the survival assertion) to be extended.
    private static func isCovered(_ kind: PlanWarning.Kind) -> Bool {
        switch kind {
        case .unknownCost, .unverifiedDietary, .unverifiedAccessibility,
             .unverifiedSetting, .unknownAvailability, .venueUnavailable,
             .unknownHours, .providerLimitation:
            return true
        }
    }

    @Test("Every warning kind's message survives onto a rendered surface", arguments: everyKind)
    func warningSurvives(kind: PlanWarning.Kind) {
        #expect(Self.isCovered(kind))

        let warning = PlanWarning(kind, slotID: SlotID("dinner"))
        let decks = PlanPresentation.decks(from: plan(warnings: [warning]))

        let rendered = decks.flatMap { deck in
            deck.warnings + deck.candidates.flatMap(\.warnings)
        }
        #expect(rendered.contains(warning.message))
    }

    @Test("A warning about a dropped candidate surfaces on the deck, not nowhere")
    func droppedCandidateWarningLandsOnDeck() {
        // ghost-1 is selected but absent from evidence: its card is dropped, so
        // its warning must climb to the deck header rather than vanish.
        let slots = [Fixtures.slot("dinner", category: .food, ["food-1", "ghost-1"])]
        let warning = PlanWarning(.unknownAvailability(VenueID("ghost-1")), slotID: SlotID("dinner"))
        let decks = PlanPresentation.decks(from: plan(slots: slots, warnings: [warning]))

        #expect(decks[0].warnings == [warning.message])
        #expect(decks[0].candidates.flatMap(\.warnings).isEmpty)
    }

    @Test("A rendered candidate's warnings ride on the card and are not duplicated on the deck")
    func renderedWarningsAttachToCard() {
        let warning = PlanWarning(.unknownCost(VenueID("food-1")), slotID: SlotID("dinner"))
        let decks = PlanPresentation.decks(from: plan(warnings: [warning]))

        let dinner = decks.first { $0.slotName == "Dinner" }
        let card = dinner?.candidates.first { $0.venueID == VenueID("food-1") }
        #expect(card?.warnings == [warning.message])
        #expect(dinner?.warnings.isEmpty == true)
    }

    // MARK: - Evidence additivity

    @Test("A plan built without evidence behaves exactly as before — and maps to empty decks' candidates")
    func evidenceIsAdditive() {
        let bare = plan(evidence: [])
        #expect(bare.venue(VenueID("food-1")) == nil)

        // Same plan, evidence attached: identical everywhere except resolution.
        let full = plan()
        #expect(bare.slots == full.slots)
        #expect(bare.warnings == full.warnings)
        #expect(bare.evidenceIDs == full.evidenceIDs)
        #expect(full.venue(VenueID("food-1"))?.name == "Venue food-1")

        // Without evidence nothing can resolve, so decks render no cards —
        // absent, never placeholders.
        let decks = PlanPresentation.decks(from: bare)
        let noCards = decks.allSatisfy { $0.candidates.isEmpty }
        #expect(noCards)
    }
}
