//
//  BriefNormalizer.swift
//  Wandr
//
//  Pure Swift. Turns an uncertain draft into a canonical brief.
//
//  No model, no network, no file system — the draft is already in memory by the
//  time this runs. This is the one place safe defaults are applied, and every one
//  of them is marked `.safeDefault` so a later "here's what we assumed" screen can
//  show the host exactly what Wandr filled in on their behalf.
//
//  Order of operations matters and is asserted in the tests: a value the draft
//  *states* is clamped and marked `.host`; only an absent value falls through to
//  the default. Clamping never turns a stated value into a guessed one.
//

import Foundation

/// The real `BriefNormalizing` implementation.
nonisolated struct BriefNormalizer: BriefNormalizing, Sendable {

    /// Constraints this normalizer refuses to default.
    ///
    /// Empty in the demo configuration, which is why `.needsDetails` is reachable
    /// and tested but never actually produced by any of the six fixture requests —
    /// every constraint in `MissingConstraint` has a safe default in `OutingBrief`.
    /// Step 5's UI bridge is what would populate this; nothing renders the
    /// `needsDetails` state yet.
    let constraintsRequiringHost: Set<MissingConstraint>

    init(constraintsRequiringHost: Set<MissingConstraint> = []) {
        self.constraintsRequiringHost = constraintsRequiringHost
    }

    func normalize(_ draft: OutingBriefDraft) throws -> BriefNormalizationOutcome {

        let occasion = sourced(draft.occasion, default: OutingBrief.defaultOccasion)
        let area = sourced(draft.area, default: OutingBrief.defaultArea)

        // Bounded values are clamped through the domain's own initializers rather
        // than by re-deriving the limits here.
        let groupSize: Sourced<GroupSize> = draft.groupSize
            .map { .host(GroupSize(clamping: $0)) }
            ?? .safeDefault(OutingBrief.defaultGroupSize)

        let budget: Sourced<BudgetPerHead> = draft.budgetPerHeadRupees
            .map { .host(BudgetPerHead.clamping(rupees: $0)) }
            ?? .safeDefault(.unspecified)

        let timeWindow: Sourced<OutingTimeWindow> = draft.timeWindow.isUnknown
            ? .safeDefault(.unknown)
            : .host(draft.timeWindow)

        let brief = OutingBrief(
            occasion: occasion,
            timeWindow: timeWindow,
            area: area,
            groupSize: groupSize,
            budgetPerHead: budget,
            vibeTags: draft.vibeTags,
            // Hard constraints pass through untouched. Normalization never invents
            // one the draft didn't carry, and never waters down one it did.
            dietary: draft.dietary,
            accessibility: draft.accessibility,
            setting: draft.setting,
            // Notes are data, never instructions. Carried verbatim.
            notes: draft.notes
        )

        let missing = brief.safeDefaults.filter(constraintsRequiringHost.contains)
        guard missing.isEmpty else {
            return .needsDetails(partial: brief, missing: missing)
        }

        return .normalized(brief)
    }

    /// Stated → `.host`. Absent or blank → the stated default, marked as one.
    private func sourced(_ value: String?, default fallback: String) -> Sourced<String> {
        guard let value else { return .safeDefault(fallback) }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .safeDefault(fallback) : .host(trimmed)
    }
}
