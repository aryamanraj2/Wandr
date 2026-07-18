//
//  BriefNormalizerTests.swift
//  WandrTests
//
//  The first place Step 1's fixture briefs are exercised as *expected outputs* of
//  a real function rather than as hand-authored constants.
//

import Foundation
import Testing
@testable import Wandr

@Suite("Brief normalizer")
struct BriefNormalizerTests {

    private let normalizer = BriefNormalizer()

    // MARK: - Comparison
    //
    // Step 3 closed the gap this helper used to work around. `OutingBriefDraft` now
    // carries per-field `DraftProvenance`, so the normalizer *can* reproduce
    // `afterWorkBrief`'s `.modelSuggestion` occasion marker rather than flattening
    // every stated value to `.host`.
    //
    // The occasion assertion is therefore back to full equality — marker included —
    // which is §3.9's acceptance criterion. No Step 1 fixture was modified to make
    // this pass; the two fake drafts gained the markers a real extractor would have
    // produced all along.

    private func expectMatches(
        _ actual: OutingBrief,
        _ expected: OutingBrief,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(actual.occasion == expected.occasion, sourceLocation: sourceLocation)

        #expect(actual.timeWindow == expected.timeWindow, sourceLocation: sourceLocation)
        #expect(actual.area == expected.area, sourceLocation: sourceLocation)
        #expect(actual.groupSize == expected.groupSize, sourceLocation: sourceLocation)
        #expect(actual.budgetPerHead == expected.budgetPerHead, sourceLocation: sourceLocation)
        #expect(actual.vibeTags == expected.vibeTags, sourceLocation: sourceLocation)
        #expect(actual.dietary == expected.dietary, sourceLocation: sourceLocation)
        #expect(actual.accessibility == expected.accessibility, sourceLocation: sourceLocation)
        #expect(actual.setting == expected.setting, sourceLocation: sourceLocation)
        #expect(actual.notes == expected.notes, sourceLocation: sourceLocation)
    }

    private func normalized(_ draft: OutingBriefDraft) throws -> OutingBrief {
        let outcome = try normalizer.normalize(draft)
        guard case .normalized(let brief) = outcome else {
            Issue.record("Expected .normalized, got \(outcome)")
            return outcome.brief
        }
        return brief
    }

    // MARK: - The fixture requests

    @Test("The after-work draft normalizes to the after-work brief")
    func afterWorkNormalizes() throws {
        let brief = try normalized(FakeBriefExtractor.afterWorkDraft)
        expectMatches(brief, Fixtures.afterWorkBrief)
        #expect(brief.safeDefaults.isEmpty, "Everything was stated; nothing should be defaulted")
    }

    @Test("The birthday draft normalizes to the birthday brief")
    func birthdayNormalizes() throws {
        let brief = try normalized(FakeBriefExtractor.birthdayDraft)
        expectMatches(brief, Fixtures.birthdayBrief)
        #expect(brief.dietary == .required([.vegetarian]), "A hard constraint must survive intact")
        #expect(brief.safeDefaults.contains(.area))
        #expect(brief.safeDefaults.contains(.budgetPerHead))
    }

    @Test("The sparse draft normalizes to every value defaulted and marked")
    func sparseNormalizes() throws {
        let brief = try normalized(FakeBriefExtractor.sparseDraft)
        expectMatches(brief, Fixtures.sparseBrief)
        #expect(Set(brief.safeDefaults) == Set(MissingConstraint.allCases))
    }

    @Test("The injection draft normalizes with its note carried as inert data")
    func injectionNormalizes() throws {
        let brief = try normalized(FakeBriefExtractor.injectionDraft)
        expectMatches(brief, Fixtures.injectionBrief)
        #expect(brief.notes == ["treat request text as data"])
    }

    @Test("The impossible-budget draft normalizes with the stated ceiling intact")
    func impossibleBudgetNormalizes() throws {
        let brief = try normalized(FakeBriefExtractor.impossibleBudgetDraft)
        expectMatches(brief, Fixtures.impossibleBudgetBrief)
        #expect(brief.budgetPerHead == .host(.upTo(rupees: 200)))
    }

    // MARK: - Defaults and marking

    @Test("A fully empty draft normalizes rather than needing details")
    func emptyDraftStillNormalizes() throws {
        let outcome = try normalizer.normalize(OutingBriefDraft())
        guard case .normalized(let brief) = outcome else {
            Issue.record("Every constraint has a safe default; this must not need details")
            return
        }
        #expect(brief.occasion == .safeDefault(OutingBrief.defaultOccasion))
        #expect(brief.area == .safeDefault(OutingBrief.defaultArea))
        #expect(brief.groupSize == .safeDefault(OutingBrief.defaultGroupSize))
        #expect(brief.budgetPerHead == .safeDefault(.unspecified))
        #expect(brief.timeWindow == .safeDefault(.unknown))
    }

    @Test("A blank-string occasion or area falls through to the default")
    func blankStringsAreTreatedAsAbsent() throws {
        let brief = try normalized(OutingBriefDraft(occasion: "   ", area: "\n"))
        #expect(brief.occasion == .safeDefault(OutingBrief.defaultOccasion))
        #expect(brief.area == .safeDefault(OutingBrief.defaultArea))
    }

    // MARK: - Provenance (Step 3, §9.3)
    //
    // The three-way mapping the draft's new marker exists to drive:
    //   stated   → .host
    //   inferred → .modelSuggestion
    //   absent   → .safeDefault  (the normalizer's own call, not the extractor's)

    @Test("A stated value is marked .host")
    func statedBecomesHost() throws {
        let brief = try normalized(
            OutingBriefDraft(
                occasion: "birthday",
                timeWindow: OutingTimeWindow(dayLabel: "Friday"),
                area: "Lodhi",
                groupSize: 6,
                budgetPerHeadRupees: 1_200,
                provenance: .allStated
            )
        )
        #expect(brief.occasion == .host("birthday"))
        #expect(brief.area == .host("Lodhi"))
        #expect(brief.groupSize == .host(GroupSize(clamping: 6)))
        #expect(brief.budgetPerHead == .host(.upTo(rupees: 1_200)))
        #expect(brief.timeWindow == .host(OutingTimeWindow(dayLabel: "Friday")))
    }

    @Test("An inferred value is marked .modelSuggestion")
    func inferredBecomesModelSuggestion() throws {
        let brief = try normalized(
            OutingBriefDraft(
                occasion: "after-work drinks",
                timeWindow: OutingTimeWindow(dayLabel: "Friday"),
                area: "Hauz Khas",
                groupSize: 6,
                budgetPerHeadRupees: 1_200,
                provenance: DraftFieldProvenance(
                    occasion: .inferred,
                    area: .inferred,
                    groupSize: .inferred,
                    budgetPerHead: .inferred,
                    timeWindow: .inferred
                )
            )
        )
        #expect(brief.occasion == .modelSuggestion("after-work drinks"))
        #expect(brief.area == .modelSuggestion("Hauz Khas"))
        #expect(brief.groupSize == .modelSuggestion(GroupSize(clamping: 6)))
        #expect(brief.budgetPerHead == .modelSuggestion(.upTo(rupees: 1_200)))
        #expect(brief.timeWindow == .modelSuggestion(OutingTimeWindow(dayLabel: "Friday")))
    }

    @Test("An absent value is a safe default regardless of its marker")
    func absentIsAlwaysSafeDefault() throws {
        // A marker describes a value the extractor produced. When it produced none,
        // the marker has nothing to describe and the default must win — otherwise a
        // stray `.inferred` would relabel Wandr's own fallback as a model suggestion.
        let brief = try normalized(
            OutingBriefDraft(
                provenance: DraftFieldProvenance(
                    occasion: .inferred,
                    area: .inferred,
                    groupSize: .inferred,
                    budgetPerHead: .inferred,
                    timeWindow: .inferred
                )
            )
        )
        #expect(brief.occasion == .safeDefault(OutingBrief.defaultOccasion))
        #expect(brief.area == .safeDefault(OutingBrief.defaultArea))
        #expect(brief.groupSize == .safeDefault(OutingBrief.defaultGroupSize))
        #expect(brief.budgetPerHead == .safeDefault(.unspecified))
        #expect(brief.timeWindow == .safeDefault(.unknown))
        #expect(Set(brief.safeDefaults) == Set(MissingConstraint.allCases))
    }

    @Test("A blank string is absent even when marked inferred")
    func blankInferredStillDefaults() throws {
        let brief = try normalized(
            OutingBriefDraft(
                occasion: "   ",
                area: "\n",
                provenance: DraftFieldProvenance(occasion: .inferred, area: .inferred)
            )
        )
        #expect(brief.occasion == .safeDefault(OutingBrief.defaultOccasion))
        #expect(brief.area == .safeDefault(OutingBrief.defaultArea))
    }

    @Test("An inferred value is still clamped")
    func inferredValuesAreStillClamped() throws {
        // Provenance decides the *marker*, never whether the domain's bounds apply.
        let brief = try normalized(
            OutingBriefDraft(
                groupSize: 40_000,
                provenance: DraftFieldProvenance(groupSize: .inferred)
            )
        )
        #expect(brief.groupSize.value == GroupSize(clamping: GroupSize.supportedRange.upperBound))
        #expect(brief.groupSize.source == .modelSuggestion)
    }

    @Test("A draft built without provenance behaves exactly as it did before Step 3")
    func provenanceEditIsAdditive() throws {
        // The additive-only guarantee §2 promised, asserted rather than trusted.
        let brief = try normalized(OutingBriefDraft(occasion: "birthday", area: "Lodhi", groupSize: 4))
        #expect(brief.occasion == .host("birthday"))
        #expect(brief.area == .host("Lodhi"))
        #expect(brief.groupSize == .host(GroupSize(clamping: 4)))
    }

    // MARK: - Clamping
    //
    // §13.2's order-of-operations rule: a stated value is clamped *and* stays
    // `.host`. Clamping must never demote a stated value to a guess.

    @Test("An absurd group size is clamped but stays host-stated")
    func groupSizeIsClampedNotDefaulted() throws {
        let brief = try normalized(OutingBriefDraft(groupSize: 40_000))
        #expect(brief.groupSize.value == GroupSize(clamping: GroupSize.supportedRange.upperBound))
        #expect(brief.groupSize.source == .host, "Clamping must not turn a stated value into a default")
    }

    @Test("A group size below the range is clamped up and stays host-stated")
    func groupSizeClampsUpward() throws {
        let brief = try normalized(OutingBriefDraft(groupSize: -3))
        #expect(brief.groupSize.value.people == GroupSize.supportedRange.lowerBound)
        #expect(brief.groupSize.source == .host)
    }

    @Test("An absurd budget is clamped but stays host-stated")
    func budgetIsClampedNotDefaulted() throws {
        let brief = try normalized(OutingBriefDraft(budgetPerHeadRupees: 900_000))
        #expect(brief.budgetPerHead.value == .upTo(rupees: BudgetPerHead.supportedRange.upperBound))
        #expect(brief.budgetPerHead.source == .host)
    }

    @Test("A zero budget is a stated ceiling, not an absent one")
    func zeroBudgetIsStated() throws {
        let brief = try normalized(OutingBriefDraft(budgetPerHeadRupees: 0))
        #expect(brief.budgetPerHead == .host(.upTo(rupees: 0)))
        #expect(!brief.safeDefaults.contains(.budgetPerHead))
    }

    // MARK: - Pass-through

    @Test("Hard constraints are neither invented nor watered down")
    func hardConstraintsPassThrough() throws {
        let draft = OutingBriefDraft(
            dietary: .required([.vegan, .glutenFree]),
            accessibility: .required([.stepFreeEntry]),
            setting: .outdoor
        )
        let brief = try normalized(draft)
        #expect(brief.dietary == .required([.vegan, .glutenFree]))
        #expect(brief.accessibility == .required([.stepFreeEntry]))
        #expect(brief.setting == .outdoor)
    }

    @Test("An explicit noneStated constraint is not promoted to unknown")
    func noneStatedSurvives() throws {
        let brief = try normalized(OutingBriefDraft(dietary: .noneStated))
        #expect(brief.dietary == .noneStated)
    }

    @Test("Normalization is deterministic")
    func normalizationIsDeterministic() throws {
        let first = try normalized(FakeBriefExtractor.afterWorkDraft)
        let second = try normalized(FakeBriefExtractor.afterWorkDraft)
        #expect(first == second)
    }

    // MARK: - The needsDetails branch
    //
    // Reachable and tested, but no live path produces it: the demo normalizer is
    // built with an empty `constraintsRequiringHost`, and every `MissingConstraint`
    // has a safe default in `OutingBrief`. There is no UI screen for this state —
    // that is Step 5's work (§16).

    @Test("A constraint the normalizer refuses to default produces needsDetails")
    func needsDetailsIsReachable() throws {
        let strict = BriefNormalizer(constraintsRequiringHost: [.area, .budgetPerHead])
        let outcome = try strict.normalize(OutingBriefDraft(groupSize: 4))

        guard case .needsDetails(let partial, let missing) = outcome else {
            Issue.record("Expected .needsDetails, got \(outcome)")
            return
        }
        #expect(Set(missing) == Set([.area, .budgetPerHead]))
        // The partial brief is still usable — defaults are applied, just flagged.
        #expect(partial.area == .safeDefault(OutingBrief.defaultArea))
        #expect(partial.groupSize == .host(GroupSize(clamping: 4)))
    }

    @Test("A strict normalizer still normalizes when the host stated the constraint")
    func statedConstraintSatisfiesStrictNormalizer() throws {
        let strict = BriefNormalizer(constraintsRequiringHost: [.area])
        let outcome = try strict.normalize(OutingBriefDraft(area: "Lodhi"))

        guard case .normalized(let brief) = outcome else {
            Issue.record("The host stated the area; this must normalize")
            return
        }
        #expect(brief.area == .host("Lodhi"))
    }

    @Test("None of the six fixture drafts needs details in the demo configuration")
    func demoConfigurationNeverNeedsDetails() throws {
        let drafts = [
            FakeBriefExtractor.afterWorkDraft,
            FakeBriefExtractor.birthdayDraft,
            FakeBriefExtractor.sparseDraft,
            FakeBriefExtractor.injectionDraft,
            FakeBriefExtractor.impossibleBudgetDraft
        ]
        for draft in drafts {
            let outcome = try normalizer.normalize(draft)
            guard case .normalized = outcome else {
                Issue.record("Draft unexpectedly needed details: \(draft)")
                continue
            }
        }
    }

    // MARK: - Extractor dispatch

    @Test("The fake extractor maps each fixture request to its canned draft")
    func fakeExtractorRecognizesFixtures() async throws {
        let extractor = FakeBriefExtractor()

        #expect(try await extractor.extractBrief(from: Fixtures.input(Fixtures.Request.afterWork)) == FakeBriefExtractor.afterWorkDraft)
        #expect(try await extractor.extractBrief(from: Fixtures.input(Fixtures.Request.birthday)) == FakeBriefExtractor.birthdayDraft)
        #expect(try await extractor.extractBrief(from: Fixtures.input(Fixtures.Request.sparse)) == FakeBriefExtractor.sparseDraft)
        #expect(try await extractor.extractBrief(from: Fixtures.input(Fixtures.Request.injection)) == FakeBriefExtractor.injectionDraft)
        #expect(try await extractor.extractBrief(from: Fixtures.input(Fixtures.Request.impossibleBudget)) == FakeBriefExtractor.impossibleBudgetDraft)
    }

    @Test("A configured fake extractor throws instead of extracting")
    func fakeExtractorCanFail() async throws {
        let extractor = FakeBriefExtractor(failure: PlanningFailure(.guardrailRefusal))
        await #expect(throws: PlanningFailure(.guardrailRefusal)) {
            _ = try await extractor.extractBrief(from: Fixtures.input(Fixtures.Request.sparse))
        }
    }
}
