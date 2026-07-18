//
//  WandrPlan.swift
//  Wandr
//
//  The validated, immutable result the curation and schedule surfaces consume.
//
//  A `WandrPlan` can only be produced by the deterministic validator. The model
//  contributes rank order and rationale; it never contributes a display fact and
//  it can never remove a warning.
//

import Foundation

// MARK: - Identifiers

nonisolated struct PlanID: Sendable, Equatable, Hashable, CustomStringConvertible {
    let rawValue: UUID

    init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    var description: String { rawValue.uuidString }
}

/// Identifies one slot across curation, validation, and the schedule.
nonisolated struct SlotID: Sendable, Equatable, Hashable, Comparable, CustomStringConvertible {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var description: String { rawValue }
}

// MARK: - Curated output

/// One ranked choice inside a slot.
///
/// It carries an ID and nothing displayable. Name, area, price, offer, and hours
/// are resolved from the matching `GroundedVenue` at presentation time.
nonisolated struct CuratedCandidate: Sendable, Equatable, Identifiable {
    var id: VenueID { venueID }

    let venueID: VenueID
    /// 1-based position in the deck.
    let rank: Int
    /// Optional model prose explaining the pick. Never a source of facts.
    let rationale: String?

    init(venueID: VenueID, rank: Int, rationale: String? = nil) {
        self.venueID = venueID
        self.rank = rank
        self.rationale = rationale
    }
}

/// One slot in the plan plus the candidates competing for it.
///
/// This is both what the curator proposes and what the validator blesses — the
/// validator returns the same shape rather than a parallel type, so nothing can
/// drift between proposal and plan.
nonisolated struct CurationSlot: Sendable, Equatable, Identifiable {
    var id: SlotID { slotID }

    let slotID: SlotID
    let category: SlotCategory
    /// The human name for this slot, e.g. "Dinner".
    let title: String
    let candidates: [CuratedCandidate]

    init(slotID: SlotID, category: SlotCategory, title: String, candidates: [CuratedCandidate]) {
        self.slotID = slotID
        self.category = category
        self.title = title
        self.candidates = candidates
    }

    var candidateVenueIDs: [VenueID] { candidates.map(\.venueID) }
}

// MARK: - Warnings

/// Something the host must be told. Emitted only by deterministic validation.
///
/// Warnings are attached to the plan and survive every UI mapping. The model
/// cannot add, edit, or remove one.
nonisolated struct PlanWarning: Sendable, Equatable, Hashable {

    nonisolated enum Kind: Sendable, Equatable, Hashable {
        /// The provider has no price for this venue. Never replaced with a guess.
        case unknownCost(VenueID)
        /// Dietary tags were never surveyed for this venue.
        case unverifiedDietary(VenueID, required: [DietaryRequirement])
        /// Accessibility tags were never surveyed for this venue.
        case unverifiedAccessibility(VenueID, required: [AccessibilityRequirement])
        /// Indoor/outdoor was never established for this venue.
        case unverifiedSetting(VenueID, preference: SettingPreference)
        /// The provider does not know whether this venue is usable.
        case unknownAvailability(VenueID)
        /// The provider states this venue is not usable.
        case venueUnavailable(VenueID, reason: String)
        /// Opening hours were never established.
        case unknownHours(VenueID)
        /// A provider-stated caveat, carried through verbatim.
        case providerLimitation(VenueID, detail: String)
    }

    let kind: Kind
    /// The slot this warning belongs to, when it is slot-specific.
    let slotID: SlotID?

    init(_ kind: Kind, slotID: SlotID? = nil) {
        self.kind = kind
        self.slotID = slotID
    }

    /// The venue this warning is about.
    var venueID: VenueID {
        switch kind {
        case .unknownCost(let id),
             .unverifiedDietary(let id, _),
             .unverifiedAccessibility(let id, _),
             .unverifiedSetting(let id, _),
             .unknownAvailability(let id),
             .venueUnavailable(let id, _),
             .unknownHours(let id),
             .providerLimitation(let id, _):
            return id
        }
    }

    /// User-readable, and deliberately non-committal about anything unknown.
    var message: String {
        switch kind {
        case .unknownCost:
            return "We don't have a price for this one — check before you go."
        case .unverifiedDietary(_, let required):
            let list = required.map(\.rawValue).joined(separator: ", ")
            return "We couldn't confirm \(list) options here."
        case .unverifiedAccessibility(_, let required):
            let list = required.map(\.rawValue).joined(separator: ", ")
            return "We couldn't confirm \(list) here."
        case .unverifiedSetting(_, let preference):
            return "We couldn't confirm whether this place is \(preference.rawValue)."
        case .unknownAvailability:
            return "We can't confirm this place is open to you tonight."
        case .venueUnavailable(_, let reason):
            return "This place may not work: \(reason)"
        case .unknownHours:
            return "We don't have opening hours for this one."
        case .providerLimitation(_, let detail):
            return detail
        }
    }
}

// MARK: - Revision

/// Where a plan sits in the replan chain. The loop itself is deferred.
nonisolated struct PlanRevisionMetadata: Sendable, Equatable {
    /// 1 for the first plan of a run.
    let revision: Int
    let parentPlanID: PlanID?

    init(revision: Int = 1, parentPlanID: PlanID? = nil) {
        self.revision = revision
        self.parentPlanID = parentPlanID
    }

    static let first = PlanRevisionMetadata()
}

// MARK: - Plan

/// The immutable validated result. Once this exists, the UI may render it.
nonisolated struct WandrPlan: Sendable, Equatable, Identifiable {
    let id: PlanID
    let runID: PlanningRunID
    let brief: OutingBrief
    let slots: [CurationSlot]
    /// Every warning validation produced. These are mandatory on the plan.
    let warnings: [PlanWarning]
    /// Every venue ID this plan is grounded in, sorted for determinism.
    let evidenceIDs: [VenueID]
    let evidenceSources: [EvidenceSource]
    let revision: PlanRevisionMetadata
    let generatedAt: Date

    init(
        id: PlanID = PlanID(),
        runID: PlanningRunID,
        brief: OutingBrief,
        slots: [CurationSlot],
        warnings: [PlanWarning],
        evidenceIDs: [VenueID],
        evidenceSources: [EvidenceSource],
        revision: PlanRevisionMetadata = .first,
        generatedAt: Date
    ) {
        self.id = id
        self.runID = runID
        self.brief = brief
        self.slots = slots
        self.warnings = warnings
        self.evidenceIDs = evidenceIDs
        self.evidenceSources = evidenceSources
        self.revision = revision
        self.generatedAt = generatedAt
    }

    func warnings(for slotID: SlotID) -> [PlanWarning] {
        warnings.filter { $0.slotID == slotID }
    }

    func warnings(about venueID: VenueID) -> [PlanWarning] {
        warnings.filter { $0.venueID == venueID }
    }
}

// MARK: - Schedule

/// An assumption the schedule rests on, stated rather than hidden.
nonisolated enum ScheduleAssumption: Sendable, Equatable, Hashable {
    case defaultStartMinute(Int)
    case defaultDuration(minutes: Int, slotID: SlotID)
    /// Travel time between stops is a deferred rule — MapKit is not wired up.
    case travelTimeNotVerified
    /// The host gave no day, so the draft assumes one sitting.
    case singleDayAssumed
}

/// One block on the timeline, derived deterministically from the plan.
nonisolated struct ScheduleDraftBlock: Sendable, Equatable, Identifiable {
    var id: SlotID { slotID }

    let slotID: SlotID
    let venueID: VenueID
    let title: String
    let category: SlotCategory
    /// Minutes from midnight.
    let startMinute: Int
    let durationMinutes: Int

    var endMinute: Int { startMinute + durationMinutes }
}

/// Ordered blocks plus the assumptions behind them.
///
/// Derived from the validated plan's leading candidates — never from model text,
/// and never from the placeholder starts currently hardcoded in `CurationView`.
nonisolated struct ScheduleDraft: Sendable, Equatable {
    let planID: PlanID
    let blocks: [ScheduleDraftBlock]
    let assumptions: [ScheduleAssumption]
    /// Warnings carried forward from the plan plus any the draft adds.
    let warnings: [PlanWarning]

    init(
        planID: PlanID,
        blocks: [ScheduleDraftBlock],
        assumptions: [ScheduleAssumption] = [],
        warnings: [PlanWarning] = []
    ) {
        self.planID = planID
        self.blocks = blocks
        self.assumptions = assumptions
        self.warnings = warnings
    }

    var startMinute: Int? { blocks.map(\.startMinute).min() }
    var endMinute: Int? { blocks.map(\.endMinute).max() }
}
