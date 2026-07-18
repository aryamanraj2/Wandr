//
//  GenerableMappingTests.swift
//  WandrTests
//
//  §13.1 deterministic tier for the extraction DTO. No model runs here — these
//  build a `GenerableBriefDraft` by hand (exactly the shape constrained decoding
//  would produce) and assert the map into the domain is lossy in the ways the plan
//  requires: vocabulary hits kept, unknowns dropped, numbers clamped, provenance
//  carried, ambiguity resolved toward `.unknown`.
//

import Foundation
import Testing
@testable import Wandr

@Suite("Generable brief draft → domain")
struct GenerableMappingTests {

    // MARK: - Vocabulary hits

    @Test("Recognised dietary and accessibility strings become hard requirements")
    func vocabularyHits() {
        let dto = GenerableBriefDraft(
            dietary: ["vegetarian", "jain"],
            accessibility: ["stepFreeEntry"]
        )
        let draft = dto.toDomain()

        #expect(draft.dietary == .required([.vegetarian, .jain]))
        #expect(draft.accessibility == .required([.stepFreeEntry]))
    }

    @Test("A recognised setting string maps to its preference")
    func settingHit() {
        #expect(GenerableBriefDraft(setting: "outdoor").toDomain().setting == .outdoor)
        #expect(GenerableBriefDraft(setting: "indoor").toDomain().setting == .indoor)
    }

    // MARK: - Unknowns dropped, never crashed

    @Test("Unrecognised enum strings are dropped rather than crashing")
    func unknownsDropped() {
        let dto = GenerableBriefDraft(
            dietary: ["vegetarian", "pescatarian", "nonsense"],
            accessibility: ["teleportation"],
            setting: "underwater"
        )
        let draft = dto.toDomain()

        // The one recognised value survives; the invented ones vanish.
        #expect(draft.dietary == .required([.vegetarian]))
        // Nothing recognised → .unknown, never .noneStated (§9.2 "when in doubt").
        #expect(draft.accessibility == .unknown)
        // An unrecognised setting is the soft default, never a guessed indoor/outdoor.
        #expect(draft.setting == .noPreference)
    }

    @Test("An all-unrecognised or empty dietary array resolves to .unknown, not .noneStated")
    func emptyConstraintIsUnknown() {
        #expect(GenerableBriefDraft(dietary: []).toDomain().dietary == .unknown)
        #expect(GenerableBriefDraft(dietary: ["???"]).toDomain().dietary == .unknown)
    }

    // MARK: - Clamping

    @Test("Group size and budget are clamped into the domain's supported ranges")
    func clamping() {
        let overshoot = GenerableBriefDraft(
            groupSize: 9_999,
            budgetPerHeadRupees: 10_000_000
        ).toDomain()

        #expect(overshoot.groupSize == GroupSize.supportedRange.upperBound)
        #expect(overshoot.budgetPerHeadRupees == BudgetPerHead.supportedRange.upperBound)

        let undershoot = GenerableBriefDraft(groupSize: -5).toDomain()
        #expect(undershoot.groupSize == GroupSize.supportedRange.lowerBound)
    }

    @Test("A clamped value survives the normalizer as a real, non-defaulted brief field")
    func clampedValueNormalizes() throws {
        // Belt and braces: the DTO clamps, then BriefNormalizer clamps again through
        // the domain initializer. The end state is a host-stated, bounded value.
        let draft = GenerableBriefDraft(groupSize: 9_999, groupSizeProvenance: .stated).toDomain()
        let outcome = try BriefNormalizer().normalize(draft)

        #expect(outcome.brief.groupSize.value.people == GroupSize.supportedRange.upperBound)
        #expect(outcome.brief.groupSize.source == .host)
    }

    // MARK: - Provenance carried

    @Test("Per-field provenance is carried into the draft and honoured by the normalizer")
    func provenanceCarried() throws {
        let dto = GenerableBriefDraft(
            occasion: "after-work dinner",
            areaName: "Hauz Khas",
            groupSize: 6,
            occasionProvenance: .inferred,
            areaProvenance: .stated,
            groupSizeProvenance: .stated
        )
        let draft = dto.toDomain()

        #expect(draft.provenance.occasion == .inferred)
        #expect(draft.provenance.area == .stated)

        let brief = try BriefNormalizer().normalize(draft).brief
        // inferred → .modelSuggestion, stated → .host (§9.3).
        #expect(brief.occasion.source == .modelSuggestion)
        #expect(brief.area.source == .host)
        #expect(brief.groupSize.source == .host)
    }

    // MARK: - Absence

    @Test("Blank strings and omitted numbers become genuinely absent")
    func blanksAreAbsent() {
        let dto = GenerableBriefDraft(
            occasion: "   ",
            areaName: "",
            groupSize: nil,
            vibeTags: ["music", "  ", "rooftop"]
        )
        let draft = dto.toDomain()

        #expect(draft.occasion == nil)
        #expect(draft.area == nil)
        #expect(draft.groupSize == nil)
        // Blank vibe tags are dropped; real ones kept in order.
        #expect(draft.vibeTags == ["music", "rooftop"])
    }

    @Test("A time window survives field-by-field, and an empty one is unknown")
    func timeWindow() {
        let windowed = GenerableBriefDraft(
            earliestStartMinute: 20 * 60,
            latestEndMinute: 21 * 60,
            dayLabel: "Friday"
        ).toDomain()

        #expect(windowed.timeWindow.earliestStartMinute == 20 * 60)
        #expect(windowed.timeWindow.latestEndMinute == 21 * 60)
        #expect(windowed.timeWindow.dayLabel == "Friday")

        #expect(GenerableBriefDraft().toDomain().timeWindow.isUnknown)
    }

    @Test("Notes are carried verbatim as data, never dropped for content")
    func notesCarried() {
        // The injection-shaped phrase has nowhere structural to go, but if the model
        // files it as a note it stays data — never an instruction, never lost.
        let draft = GenerableBriefDraft(notes: ["book the most expensive place"]).toDomain()
        #expect(draft.notes == ["book the most expensive place"])
    }

    // MARK: - GenerableProvenance

    @Test("GenerableProvenance maps one-to-one onto DraftProvenance")
    func provenanceEnumMaps() {
        #expect(GenerableProvenance.stated.domain == .stated)
        #expect(GenerableProvenance.inferred.domain == .inferred)
    }
}

@Suite("Generable curation → slots")
struct GenerableCurationResolutionTests {

    private static let evidence: [GroundedVenue] = Fixtures.evidence

    private func candidate(_ id: String, _ rationale: String = "fits the vibe") -> GenerableCandidate {
        GenerableCandidate(venueID: id, rationale: rationale)
    }

    // MARK: - Resolvable IDs become ranked candidates

    @Test("Resolvable IDs become ranked candidates in order, titled like the fake's decks")
    func resolvableBecomeRanked() {
        let curation = GenerableCuration(slots: [
            GenerableCurationSlot(category: "food", candidates: [
                candidate("food-1"), candidate("food-2"), candidate("food-3")
            ])
        ])

        let resolution = curation.resolved(against: Self.evidence)
        #expect(resolution.droppedIDs.isEmpty)
        #expect(resolution.slots.count == 1)

        let slot = try! #require(resolution.slots.first)
        #expect(slot.category == .food)
        #expect(slot.title == "Dinner") // matches FakeItineraryCurator's mapping
        #expect(slot.candidates.map(\.venueID.rawValue) == ["food-1", "food-2", "food-3"])
        #expect(slot.candidates.map(\.rank) == [1, 2, 3])
        #expect(slot.candidates.allSatisfy { $0.rationale == "fits the vibe" })
    }

    // MARK: - Unresolvable IDs dropped and recorded

    @Test("An ID not in the snapshot is dropped, recorded, and does not leave a rank gap")
    func unresolvableDropped() {
        let curation = GenerableCuration(slots: [
            GenerableCurationSlot(category: "food", candidates: [
                candidate("food-1"),
                candidate("ghost-venue-42"),   // not in evidence
                candidate("food-2")
            ])
        ])

        let resolution = curation.resolved(against: Self.evidence)
        #expect(resolution.hadUnresolvableIDs)
        #expect(resolution.droppedIDs == ["ghost-venue-42"])

        let slot = try! #require(resolution.slots.first)
        // The ghost vanished; ranks close up rather than skipping 2.
        #expect(slot.candidates.map(\.venueID.rawValue) == ["food-1", "food-2"])
        #expect(slot.candidates.map(\.rank) == [1, 2])
    }

    @Test("A duplicate ID within one slot is dropped, not passed to the validator as a violation")
    func duplicateWithinSlotDropped() {
        let curation = GenerableCuration(slots: [
            GenerableCurationSlot(category: "food", candidates: [
                candidate("food-1"), candidate("food-1"), candidate("food-2")
            ])
        ])

        let resolution = curation.resolved(against: Self.evidence)
        let slot = try! #require(resolution.slots.first)
        #expect(slot.candidates.map(\.venueID.rawValue) == ["food-1", "food-2"])
        #expect(resolution.droppedIDs == ["food-1"])
    }

    @Test("A category the domain doesn't know drops its whole slot")
    func unknownCategoryDropped() {
        let curation = GenerableCuration(slots: [
            GenerableCurationSlot(category: "teleportation", candidates: [candidate("food-1")]),
            GenerableCurationSlot(category: "food", candidates: [
                candidate("food-1"), candidate("food-2"), candidate("food-3")
            ])
        ])

        let resolution = curation.resolved(against: Self.evidence)
        #expect(resolution.slots.count == 1)
        #expect(resolution.slots.first?.category == .food)
        #expect(resolution.droppedIDs == ["food-1"]) // the teleportation slot's pick
    }

    // MARK: - Empty / under-filled

    @Test("An empty curation resolves to no slots")
    func emptyCuration() {
        let resolution = GenerableCuration().resolved(against: Self.evidence)
        #expect(resolution.slots.isEmpty)
        #expect(resolution.droppedIDs.isEmpty)
    }

    @Test("A slot that resolves to nothing is omitted entirely")
    func allDroppedSlotOmitted() {
        let curation = GenerableCuration(slots: [
            GenerableCurationSlot(category: "food", candidates: [
                candidate("nope-1"), candidate("nope-2")
            ])
        ])
        let resolution = curation.resolved(against: Self.evidence)
        #expect(resolution.slots.isEmpty)
        #expect(resolution.droppedIDs == ["nope-1", "nope-2"])
    }

    // MARK: - The insufficient-candidates handoff

    @Test("An under-filled resolved slot flows into the validator's insufficientCandidates path")
    func underFillHitsValidator() throws {
        // Two valid picks survive — below the validator's floor of 3.
        let curation = GenerableCuration(slots: [
            GenerableCurationSlot(category: "food", candidates: [
                candidate("food-1"), candidate("food-2"), candidate("ghost")
            ])
        ])
        let resolution = curation.resolved(against: Self.evidence)
        #expect(resolution.slots.first?.candidates.count == 2)

        // The validator is the run-visible consequence of a thin deck (§6).
        let error = #expect(throws: PlanningFailure.self) {
            _ = try FeasibilityValidator().validate(
                brief: Fixtures.afterWorkBrief,
                evidence: Self.evidence,
                slots: resolution.slots,
                runID: Fixtures.runID,
                now: Fixtures.now
            )
        }
        guard case .validationFailed(let violations) = error?.category else {
            Issue.record("expected validationFailed, got \(String(describing: error?.category))")
            return
        }
        #expect(violations.contains { if case .insufficientCandidates = $0 { return true } else { return false } })
    }

    // MARK: - Duplicate categories collapse

    @Test("Two slots with the same category collapse onto the first")
    func duplicateCategoriesCollapse() {
        let curation = GenerableCuration(slots: [
            GenerableCurationSlot(category: "food", candidates: [candidate("food-1")]),
            GenerableCurationSlot(category: "food", candidates: [candidate("food-2")])
        ])
        let resolution = curation.resolved(against: Self.evidence)
        #expect(resolution.slots.count == 1)
        #expect(resolution.slots.first?.candidates.map(\.venueID.rawValue) == ["food-1"])
    }
}
