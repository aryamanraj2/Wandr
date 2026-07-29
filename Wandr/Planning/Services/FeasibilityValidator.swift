// FeasibilityValidator.swift Wandr Pure Swift. The gate that stops beautiful-but-impossible AI output. It receives typed brief fields, an immutable evidence snapshot, and the proposed selections — and nothing else. There is no model call, no network, no file system, no UI framework reachable from this file, by design. The model may add rationale. It can never remove a warning produced here, and it can never turn an unknown into a fact.

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

/// A deterministic rule the curation broke. Every case names the venue and slot responsible, so a failure is debuggable without replaying the model.
nonisolated enum FeasibilityViolation: Sendable, Equatable, Hashable {

    /// The curator returned nothing at all.
    case emptyCuration

    /// A selected ID is not in the evidence snapshot — an invented venue.
    case unknownVenue(slotID: SlotID, venueID: VenueID)

    /// The same venue appears twice in one deck.
    case duplicateWithinSlot(slotID: SlotID, venueID: VenueID)

    /// The same venue fills more than one slot.
    case duplicateAcrossSlots(venueID: VenueID, slotIDs: [SlotID])

    // `overBudget` and `insufficientCandidates` used to live here. Both are gone, and deliberately: a violation fails the *whole run*, and neither of those is the model doing something wrong. A place costing more than the host hoped, or a category with only two options, is a plan worth showing with a note on it — `EvidenceResolver` gives the constraint up and discloses it, and a thin deck is simply thin. What remains below is genuine model misbehaviour, which should still stop the run loudly.

    /// Evidence was surveyed and contradicts a hard dietary requirement.
    case unmetDietaryRequirement(slotID: SlotID, venueID: VenueID, missing: [DietaryRequirement])

    /// Evidence was surveyed and contradicts a hard accessibility requirement.
    case unmetAccessibilityRequirement(slotID: SlotID, venueID: VenueID, missing: [AccessibilityRequirement])

    /// Evidence was surveyed and contradicts an explicit indoor/outdoor preference.
    case unmetSettingPreference(slotID: SlotID, venueID: VenueID, preference: SettingPreference, actual: VenueSetting)

    // MARK: Shape invariants
    // The two below differ in kind from everything above. The others catch a bad *pick* — a venue that should not have been chosen. These catch a bad *plan*: the right venues arranged into a night the host never asked for. They are quantified over every plan rather than written as cases, because the failure they guard against has recurred in a new sentence every time it was fixed as one.

    /// The plan contains a stop the host neither named nor could have implied. Once the host names anything, the span of the plan is pinned: it may not reach earlier than their first stop or later than their last. Anything inside that span is filling a gap they themselves bounded; anything outside it is Wandr deciding it knows better. This is the invariant for the reported failure. "12 to 5, lunch and snacks" recognised only `lunch`, took a growth branch meant for unspecified requests, and extended forward to an 8 pm dinner — three hours past a stated finish, out of a sentence that named two stops. The growth path is gone; this makes its return detectable rather than depending on nobody reintroducing it.
    case grewBeyondRequest(slotID: SlotID, band: SlotBand, named: [SlotBand])

    /// A block runs past the finish the host gave. `SlotSchedule` already truncates to the window, so this should be unreachable — which is the point. It is the backstop that makes "no stop ever ends after their stated end" a property of the *plan*, not a property of one function that happens to be careful.
    case ranPastStatedEnd(slotID: SlotID, endMinute: Int, statedEnd: Int)

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

        case .unmetDietaryRequirement(_, _, let missing):
            let list = missing.map(\.rawValue).joined(separator: ", ")
            return "One pick doesn't cover \(list), which you asked for."

        case .unmetAccessibilityRequirement(_, _, let missing):
            let list = missing.map(\.rawValue).joined(separator: ", ")
            return "One pick doesn't have \(list), which you asked for."

        case .unmetSettingPreference(_, _, let preference, _):
            return "One pick isn't \(preference.rawValue), which you asked for."

        case .grewBeyondRequest:
            return "We put together more of a day than you asked for. Let's try again."

        case .ranPastStatedEnd:
            return "One stop ran past the time you said you had to finish. Let's try again."
        }
    }
}

// MARK: - Validator

/// Deterministic feasibility checks over a proposed curation. Implements only the first-step rules from `nonuistuff/plan.md` §10. Route duration, live opening hours, weather fallback, time-zone resolution, and offer-window validation are deferred rules and are deliberately absent — faking them would be worse than not having them.
nonisolated struct FeasibilityValidator: ItineraryValidating, Sendable {

    let rules: FeasibilityRules

    init(rules: FeasibilityRules = .default) {
        self.rules = rules
    }

    /// Validates the curation and returns the immutable plan, or throws. Check order is deliberate: per-candidate rules run first because they name the exact venue at fault, then cross-slot rules, then deck depth. Deck depth last means a thin deck of *valid* venues reports as thin, rather than masking a bad pick.
    func validate(
        brief: OutingBrief,
        evidence: [GroundedVenue],
        slots: [CurationSlot],
        relaxations: [PlanRelaxation] = [],
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

                // Rule 4 — budget is a warning on the card, never a run-ender.
                warnings.append(contentsOf: budgetWarnings(venue: venue, slot: slot, brief: brief))
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

        // MARK: Rules 9, 10 — the plan's shape
        violations.append(contentsOf: shapeViolations(brief: brief, slots: slots))

        // Sorting keeps the reported order stable across dictionary iteration.
        violations.sort { $0.sortKey < $1.sortKey }

        if !violations.isEmpty {
            throw PlanningFailure.validationFailed(violations)
        }

        // MARK: Rule 6 — deck depth
        // A thin deck is a thin deck, not a failure. This used to throw two different ways — `insufficientEvidence` when the category was short and `insufficientCandidates` when the curator under-picked — and both ended the host's run. Two real restaurants beat no plan, and a low budget or a small neighbourhood should never be able to produce nothing at all. The shortfall is still worth knowing about, so it becomes a warning the host sees and a number the log records. `minimumCandidatesPerSlot` remains what `SlotDeckBuilder` fills *towards*; it is no longer a contract.

        for slot in slots where slot.candidates.count < rules.minimumCandidatesPerSlot {
            warnings.append(
                PlanWarning(
                    .thinDeck(required: rules.minimumCandidatesPerSlot, found: slot.candidates.count),
                    slotID: slot.slotID
                )
            )
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
            relaxations: relaxations,
            evidenceIDs: groundedIDs,
            evidenceSources: sources,
            generatedAt: now
        )
    }

    // MARK: - Rules 9 and 10: the plan's shape

    /// Every way the arrangement of stops can betray the request, checked over the whole plan at once. Quantified deliberately. Both properties below hold for *all* briefs and all plans, and neither names a stop, a time, or a phrasing — so a new sentence cannot require a new branch here. That is the whole reason they are written this way: the failures they cover have each been fixed before as a special case, and each came back wearing different words.
    private func shapeViolations(brief: OutingBrief, slots: [CurationSlot]) -> [FeasibilityViolation] {
        let schedule = brief.schedule
        var found: [FeasibilityViolation] = []

        // Rule 9 — the host's own stops bound the plan's span. Only once they have named something. An unspecified request has no span to exceed, and proposing a full day for it is the feature, not a violation.
        let requested = brief.requestedStops
        // Only when the request was actually satisfiable. A host who asks for lunch and says they are free 8 to 9 pm has contradicted themselves; `SlotSchedule` drops the stop and falls back to the default shape, `requestHonoured` reports it, and the host is told. Applying the span to that fallback would call Wandr's own recovery a violation and fail the run outright — the plan is *entirely* outside a span it was never able to honour.
        let honoured = slots.contains { requested.contains($0.band) }
        if !requested.isEmpty, honoured {
            let order = SlotBand.allCases
            let namedPositions = order.indices.filter { requested.contains(order[$0]) }

            if let first = namedPositions.min(), let last = namedPositions.max() {
                for slot in slots {
                    guard let position = order.firstIndex(of: slot.band) else { continue }
                    guard position < first || position > last else { continue }
                    found.append(
                        .grewBeyondRequest(
                            slotID: slot.slotID,
                            band: slot.band,
                            named: requested.sorted { lhs, rhs in
                                (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
                            }
                        )
                    )
                }
            }
        }

        // Rule 10 — no block ends after the finish the host gave. Over `schedule.slots`, which are the blocks the timeline actually lays down, rather than over the curated decks: a deck has no time of its own, it shows whatever window its band resolved to. Honest about what this is: `SlotSchedule.layOut` clamps every block to `latestEnd`, so as the code stands this cannot fire. It is a backstop, kept because the property is one the host can *see* violated — an 11 pm bar on a plan they said had to end at nine — and because the clamp has been rewritten three times. An assertion that only earns its place after a regression is still worth its four lines. The reachable half of the same property is enforced in `SlotScheduleTests`, quantified over every band and window.
        if let statedEnd = brief.timeWindow.value.latestEndMinute {
            for block in schedule.slots where block.endMinute > statedEnd {
                found.append(
                    .ranPastStatedEnd(
                        slotID: SlotID(block.band.rawValue),
                        endMinute: block.endMinute,
                        statedEnd: statedEnd
                    )
                )
            }
        }

        return found
    }

    // MARK: - Rule 4: budget

    /// A card above the host's ceiling is shown with the number on it, not removed and not fatal. `EvidenceResolver` only lets one through when the alternative was an empty deck, and it discloses that separately — this is the per-card half of the same honesty.
    private func budgetWarnings(
        venue: GroundedVenue,
        slot: CurationSlot,
        brief: OutingBrief
    ) -> [PlanWarning] {
        guard
            let ceiling = brief.budget.value.ceilingPerHead(for: brief.groupSize.value),
            let perHead = venue.cost.knownPerHeadRupees,
            perHead > ceiling
        else { return [] }

        return [
            PlanWarning(
                .overBudget(venue.venueID, perHeadRupees: perHead, ceilingPerHead: ceiling),
                slotID: slot.slotID
            )
        ]
    }

    /// An unknown cost is a warning, never a guessed number — even when the host set no ceiling, because the host still deserves to know we don't know.
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
    /// Groups violations by kind, then by slot and venue, so the reported order never depends on dictionary iteration.
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
        case .unmetDietaryRequirement(let slot, let venue, _):
            return "5|\(slot.rawValue)|\(venue.rawValue)"
        case .unmetAccessibilityRequirement(let slot, let venue, _):
            return "6|\(slot.rawValue)|\(venue.rawValue)"
        case .unmetSettingPreference(let slot, let venue, _, _):
            return "7|\(slot.rawValue)|\(venue.rawValue)"
        case .grewBeyondRequest(let slot, let band, _):
            return "8|\(slot.rawValue)|\(band.rawValue)"
        case .ranPastStatedEnd(let slot, let end, _):
            return "9|\(slot.rawValue)|\(end)"
        }
    }
}
