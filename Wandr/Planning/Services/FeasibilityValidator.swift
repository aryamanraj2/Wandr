//
//  FeasibilityValidator.swift
//  Wandr
//
//  Pure Swift. The gate that stops beautiful-but-impossible AI output.
//
//  It receives typed brief fields, an immutable evidence snapshot, and the
//  proposed selections — and nothing else. There is no model call, no network,
//  no file system, no UI framework reachable from this file, by design.
//
//  The model may add rationale. It can never remove a warning produced here, and
//  it can never turn an unknown into a fact.
//

import Foundation

// MARK: - Rules

/// The knobs the first-step rules expose.
nonisolated struct FeasibilityRules: Sendable, Equatable, Hashable {

    /// How many grounded candidates a deck needs to be worth swiping.
    var minimumCandidatesPerSlot: Int

    /// Whether one venue may fill more than one slot. The product says no today.
    var allowsVenueReuseAcrossSlots: Bool

    init(minimumCandidatesPerSlot: Int = 3, allowsVenueReuseAcrossSlots: Bool = false) {
        self.minimumCandidatesPerSlot = minimumCandidatesPerSlot
        self.allowsVenueReuseAcrossSlots = allowsVenueReuseAcrossSlots
    }

    static let `default` = FeasibilityRules()
}

// MARK: - Violations

/// A deterministic rule the curation broke. Every case names the venue and slot
/// responsible, so a failure is debuggable without replaying the model.
nonisolated enum FeasibilityViolation: Sendable, Equatable, Hashable {

    /// The curator returned nothing at all.
    case emptyCuration

    /// A selected ID is not in the evidence snapshot — an invented venue.
    case unknownVenue(slotID: SlotID, venueID: VenueID)

    /// The same venue appears twice in one deck.
    case duplicateWithinSlot(slotID: SlotID, venueID: VenueID)

    /// The same venue fills more than one slot.
    case duplicateAcrossSlots(venueID: VenueID, slotIDs: [SlotID])

    /// A known per-head price exceeds the confirmed ceiling.
    case overBudget(slotID: SlotID, venueID: VenueID, perHeadRupees: Int, limitRupees: Int)

    /// Evidence was surveyed and contradicts a hard dietary requirement.
    case unmetDietaryRequirement(slotID: SlotID, venueID: VenueID, missing: [DietaryRequirement])

    /// Evidence was surveyed and contradicts a hard accessibility requirement.
    case unmetAccessibilityRequirement(slotID: SlotID, venueID: VenueID, missing: [AccessibilityRequirement])

    /// Evidence was surveyed and contradicts an explicit indoor/outdoor preference.
    case unmetSettingPreference(slotID: SlotID, venueID: VenueID, preference: SettingPreference, actual: VenueSetting)

    /// The deck is too thin, even though the evidence snapshot could have filled it.
    case insufficientCandidates(slotID: SlotID, required: Int, found: Int)

    /// User-readable. Never mentions the host's own words.
    var message: String {
        switch self {
        case .emptyCuration:
            return "We couldn't put a plan together from what we found."

        case .unknownVenue:
            return "One of the suggested places isn't a real option we found. Let's try again."

        case .duplicateWithinSlot:
            return "The same place turned up twice in one round. Let's try again."

        case .duplicateAcrossSlots:
            return "The same place was picked for two different stops. Let's try again."

        case .overBudget(_, _, let perHead, let limit):
            return "One pick works out to ₹\(perHead) a head, over your ₹\(limit) limit."

        case .unmetDietaryRequirement(_, _, let missing):
            let list = missing.map(\.rawValue).joined(separator: ", ")
            return "One pick doesn't cover \(list), which you asked for."

        case .unmetAccessibilityRequirement(_, _, let missing):
            let list = missing.map(\.rawValue).joined(separator: ", ")
            return "One pick doesn't have \(list), which you asked for."

        case .unmetSettingPreference(_, _, let preference, _):
            return "One pick isn't \(preference.rawValue), which you asked for."

        case .insufficientCandidates(_, let required, let found):
            return "One round only has \(found) option\(found == 1 ? "" : "s") to swipe through — we need \(required)."
        }
    }
}

// MARK: - Validator

/// Deterministic feasibility checks over a proposed curation.
///
/// Implements only the first-step rules from `nonuistuff/plan.md` §10. Route
/// duration, live opening hours, weather fallback, time-zone resolution, and
/// offer-window validation are deferred rules and are deliberately absent —
/// faking them would be worse than not having them.
nonisolated struct FeasibilityValidator: ItineraryValidating, Sendable {

    let rules: FeasibilityRules

    init(rules: FeasibilityRules = .default) {
        self.rules = rules
    }

    /// Validates the curation and returns the immutable plan, or throws.
    ///
    /// Check order is deliberate: per-candidate rules run first because they name
    /// the exact venue at fault, then cross-slot rules, then deck depth. Deck depth
    /// last means a thin deck of *valid* venues reports as thin, rather than
    /// masking a bad pick.
    func validate(
        brief: OutingBrief,
        evidence: [GroundedVenue],
        slots: [CurationSlot],
        runID: PlanningRunID,
        now: Date
    ) throws -> WandrPlan {

        guard !slots.isEmpty else {
            throw PlanningFailure.validationFailed([.emptyCuration])
        }

        let evidenceByID = Dictionary(evidence.map { ($0.venueID, $0) }, uniquingKeysWith: { first, _ in first })

        var violations: [FeasibilityViolation] = []
        var warnings: [PlanWarning] = []

        // Rule 3 bookkeeping: which slots each venue was selected for.
        var slotsByVenue: [VenueID: [SlotID]] = [:]

        // MARK: Rules 1, 2, 4, 5 — per candidate

        for slot in slots {
            var seenInSlot: Set<VenueID> = []

            for candidate in slot.candidates {
                let venueID = candidate.venueID

                // Rule 1 — the ID must exist in the snapshot.
                guard let venue = evidenceByID[venueID] else {
                    violations.append(.unknownVenue(slotID: slot.slotID, venueID: venueID))
                    continue
                }

                // Rule 2 — no duplicate inside one deck.
                if seenInSlot.contains(venueID) {
                    violations.append(.duplicateWithinSlot(slotID: slot.slotID, venueID: venueID))
                    continue
                }
                seenInSlot.insert(venueID)
                slotsByVenue[venueID, default: []].append(slot.slotID)

                // Rule 4 — budget.
                violations.append(contentsOf: budgetViolations(venue: venue, slot: slot, brief: brief))
                warnings.append(contentsOf: costWarnings(venue: venue, slot: slot))

                // Rule 5 — hard constraints.
                let constraint = constraintOutcome(venue: venue, slot: slot, brief: brief)
                violations.append(contentsOf: constraint.violations)
                warnings.append(contentsOf: constraint.warnings)

                // Rule 8 — provider caveats become plan warnings.
                warnings.append(contentsOf: provenanceWarnings(venue: venue, slot: slot))
            }
        }

        // MARK: Rule 3 — no venue in two slots

        if !rules.allowsVenueReuseAcrossSlots {
            for (venueID, slotIDs) in slotsByVenue where slotIDs.count > 1 {
                violations.append(.duplicateAcrossSlots(venueID: venueID, slotIDs: slotIDs.sorted()))
            }
        }

        // Sorting keeps the reported order stable across dictionary iteration.
        violations.sort { $0.sortKey < $1.sortKey }

        if !violations.isEmpty {
            throw PlanningFailure.validationFailed(violations)
        }

        // MARK: Rule 6 — deck depth
        //
        // A thin deck means one of two very different things. If the snapshot
        // never had enough *offerable* venues of that category, research came up
        // short and the host should widen the search. If it did, the curator
        // under-picked and the run should be retried. Padding with invented
        // venues is not an option either way.
        //
        // "Offerable" applies the same hard-constraint filter the curators do:
        // a category with four venues of which two are proven incompatible has
        // two real options, and retrying the model can never conjure a third —
        // that shortfall is missing evidence, not a curation fault.

        var evidenceShortfalls: [PlanningFailure.InsufficientEvidenceDetail] = []
        var curationShortfalls: [FeasibilityViolation] = []

        for slot in slots where slot.candidates.count < rules.minimumCandidatesPerSlot {
            let availableInCategory = evidence.count {
                $0.category == slot.category && ConstraintEligibility.isEligible($0, for: brief)
            }

            if availableInCategory < rules.minimumCandidatesPerSlot {
                evidenceShortfalls.append(
                    PlanningFailure.InsufficientEvidenceDetail(
                        category: slot.category,
                        required: rules.minimumCandidatesPerSlot,
                        found: availableInCategory
                    )
                )
            } else {
                curationShortfalls.append(
                    .insufficientCandidates(
                        slotID: slot.slotID,
                        required: rules.minimumCandidatesPerSlot,
                        found: slot.candidates.count
                    )
                )
            }
        }

        if !evidenceShortfalls.isEmpty {
            throw PlanningFailure.insufficientEvidence(evidenceShortfalls)
        }
        if !curationShortfalls.isEmpty {
            throw PlanningFailure.validationFailed(curationShortfalls)
        }

        // MARK: Rule 8 — every warning rides on the plan

        let selectedIDs = slots.flatMap(\.candidateVenueIDs)
        let groundedIDs = Set(selectedIDs).sorted()
        let sources = Set(groundedIDs.compactMap { evidenceByID[$0]?.source })
            .sorted { ($0.provider, $0.version) < ($1.provider, $1.version) }

        return WandrPlan(
            runID: runID,
            brief: brief,
            slots: slots,
            warnings: warnings,
            evidenceIDs: groundedIDs,
            evidenceSources: sources,
            generatedAt: now
        )
    }

    // MARK: - Rule 4: budget

    private func budgetViolations(
        venue: GroundedVenue,
        slot: CurationSlot,
        brief: OutingBrief
    ) -> [FeasibilityViolation] {
        guard
            let limit = brief.budgetPerHead.value.limitRupees,
            let perHead = venue.cost.knownPerHeadRupees,
            perHead > limit
        else { return [] }

        return [
            .overBudget(
                slotID: slot.slotID,
                venueID: venue.venueID,
                perHeadRupees: perHead,
                limitRupees: limit
            )
        ]
    }

    /// An unknown cost is a warning, never a guessed number — even when the host
    /// set no ceiling, because the host still deserves to know we don't know.
    private func costWarnings(venue: GroundedVenue, slot: CurationSlot) -> [PlanWarning] {
        guard venue.cost == .unknown else { return [] }
        return [PlanWarning(.unknownCost(venue.venueID), slotID: slot.slotID)]
    }

    // MARK: - Rule 5: hard constraints

    /// Surveyed-and-contradicted fails. Never-surveyed warns.
    private func constraintOutcome(
        venue: GroundedVenue,
        slot: CurationSlot,
        brief: OutingBrief
    ) -> (violations: [FeasibilityViolation], warnings: [PlanWarning]) {

        var violations: [FeasibilityViolation] = []
        var warnings: [PlanWarning] = []

        // Dietary
        if brief.dietary.isHardConstraint {
            let required = brief.dietary.requirements
            switch venue.dietaryTags.unsatisfied(by: required) {
            case .none:
                warnings.append(
                    PlanWarning(.unverifiedDietary(venue.venueID, required: required), slotID: slot.slotID)
                )
            case .some(let missing) where !missing.isEmpty:
                violations.append(
                    .unmetDietaryRequirement(slotID: slot.slotID, venueID: venue.venueID, missing: missing)
                )
            default:
                break
            }
        }

        // Accessibility
        if brief.accessibility.isHardConstraint {
            let required = brief.accessibility.requirements
            switch venue.accessibilityTags.unsatisfied(by: required) {
            case .none:
                warnings.append(
                    PlanWarning(.unverifiedAccessibility(venue.venueID, required: required), slotID: slot.slotID)
                )
            case .some(let missing) where !missing.isEmpty:
                violations.append(
                    .unmetAccessibilityRequirement(slotID: slot.slotID, venueID: venue.venueID, missing: missing)
                )
            default:
                break
            }
        }

        // Indoor / outdoor
        if brief.setting.isHardConstraint {
            switch venue.setting.satisfies(brief.setting) {
            case .none:
                warnings.append(
                    PlanWarning(.unverifiedSetting(venue.venueID, preference: brief.setting), slotID: slot.slotID)
                )
            case .some(false):
                violations.append(
                    .unmetSettingPreference(
                        slotID: slot.slotID,
                        venueID: venue.venueID,
                        preference: brief.setting,
                        actual: venue.setting
                    )
                )
            case .some(true):
                break
            }
        }

        return (violations, warnings)
    }

    // MARK: - Rule 8: provenance warnings

    private func provenanceWarnings(venue: GroundedVenue, slot: CurationSlot) -> [PlanWarning] {
        var warnings: [PlanWarning] = []

        switch venue.availability {
        case .available:
            break
        case .unknown:
            warnings.append(PlanWarning(.unknownAvailability(venue.venueID), slotID: slot.slotID))
        case .unavailable(let reason):
            warnings.append(PlanWarning(.venueUnavailable(venue.venueID, reason: reason), slotID: slot.slotID))
        }

        if venue.openWindow == .unknown {
            warnings.append(PlanWarning(.unknownHours(venue.venueID), slotID: slot.slotID))
        }

        for limitation in venue.limitations {
            warnings.append(
                PlanWarning(.providerLimitation(venue.venueID, detail: limitation), slotID: slot.slotID)
            )
        }

        return warnings
    }
}

// MARK: - Deterministic ordering

nonisolated private extension FeasibilityViolation {
    /// Groups violations by kind, then by slot and venue, so the reported order
    /// never depends on dictionary iteration.
    var sortKey: String {
        switch self {
        case .emptyCuration:
            return "0"
        case .unknownVenue(let slot, let venue):
            return "1|\(slot.rawValue)|\(venue.rawValue)"
        case .duplicateWithinSlot(let slot, let venue):
            return "2|\(slot.rawValue)|\(venue.rawValue)"
        case .duplicateAcrossSlots(let venue, let slots):
            return "3|\(venue.rawValue)|\(slots.map(\.rawValue).joined(separator: ","))"
        case .overBudget(let slot, let venue, _, _):
            return "4|\(slot.rawValue)|\(venue.rawValue)"
        case .unmetDietaryRequirement(let slot, let venue, _):
            return "5|\(slot.rawValue)|\(venue.rawValue)"
        case .unmetAccessibilityRequirement(let slot, let venue, _):
            return "6|\(slot.rawValue)|\(venue.rawValue)"
        case .unmetSettingPreference(let slot, let venue, _, _):
            return "7|\(slot.rawValue)|\(venue.rawValue)"
        case .insufficientCandidates(let slot, _, _):
            return "8|\(slot.rawValue)"
        }
    }
}
