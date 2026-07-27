//
//  ConstraintLadder.swift
//  Wandr
//
//  What Wandr gives up, in what order, when the host's request cannot be satisfied
//  exactly — and what it owes them for having given it up.
//
//  ## Why this exists
//
//  Before this file, every constraint was binary: a plan either satisfied all of
//  them or the run died. A group of two with ₹2000 between them asking for lunch
//  got "One pick works out to ₹2400 a head, over your ₹2000 limit" and a dead end,
//  because one candidate over a ceiling was a `FeasibilityViolation` and violations
//  fail the whole run.
//
//  That is the wrong shape. Constraints have *degrees of satisfaction*, not a
//  binary satisfy/violate, and the right answer to "nothing fits" is a plan that
//  gives up the least important thing — and says so — rather than no plan at all.
//  Google's trip planner substitutes where Wandr threw; the preference-aware
//  literature calls the fix relaxing the lowest-importance constraint first, and
//  names "respond with no results" as the anti-pattern.
//
//  ## Importance is already in the brief
//
//  The usual way to get importance weights is to ask a model how much each
//  constraint mattered. Wandr does not need to: `Sourced<Value>.source` already
//  records whether a value came from the host, from the model, or from a Wandr
//  default. A budget Wandr invented gives way before a time the host stated. The
//  weighting was written for the review screen and turns out to be exactly the
//  ranking this needs.
//
//  ## What is never relaxed
//
//  `dietary` and `accessibility`. Relaxing those means proposing food someone
//  cannot eat or a door someone cannot get through — that is not a degraded plan,
//  it is a harmful one. They stay hard filters in `ConstraintEligibility`, and a
//  request that cannot be met without breaking them fails honestly instead.
//
//  Foundation only. No model, no I/O.
//

import Foundation

/// A constraint the plan may have to give up.
///
/// Only constraints that can actually *remove* something are listed. Vibe tags are
/// absent on purpose: they have never filtered a venue, only ranked one, so there
/// is nothing to relax and a rung for them would be theatre.
nonisolated enum RelaxableConstraint: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Indoor/outdoor. A preference about the room, not about the outing.
    case setting
    /// The per-head ceiling. Costs money, not the plan.
    case budget
    /// The hours the host gave. Bends the schedule.
    case timeWindow
    /// The stops they named. Last, because they *asked* for lunch.
    case requestedStops

    /// Product ordering — lower gives way first. Used only to break ties between
    /// constraints of equal provenance.
    var productRank: Int {
        switch self {
        case .setting:        return 0
        case .budget:         return 1
        case .timeWindow:     return 2
        case .requestedStops: return 3
        }
    }
}

/// A constraint that was given up, and the sentence the host is owed for it.
///
/// The disclosure is mandatory, and it is the one place this design departs from
/// the literature it is drawn from: the published approach relaxes silently and
/// presents the result as if it were a match. Wandr's premise is the opposite —
/// guessing is allowed, hiding the guess is not.
nonisolated struct PlanRelaxation: Sendable, Equatable, Hashable {
    let constraint: RelaxableConstraint
    /// Host-readable, and specific about what was given up. Never their own words.
    let disclosure: String

    init(_ constraint: RelaxableConstraint, disclosure: String) {
        self.constraint = constraint
        self.disclosure = disclosure
    }

    /// The stops the host named would not fit the hours they gave, so the schedule
    /// fell back to a shape that does.
    ///
    /// Raised by the coordinator rather than by `EvidenceResolver`: this is a
    /// *schedule* compromise, and the resolver deliberately handles only the two
    /// constraints that change which venues exist. `SlotSchedule.requestHonoured` has
    /// reported this since it was written and nothing read it — so a host who asked
    /// for lunch, and was free only in the evening, was quietly handed dinner with no
    /// word about it anywhere.
    static let stopsDidNotFit = PlanRelaxation(
        .requestedStops,
        disclosure: "We couldn't fit every stop you asked for into that time."
    )
}

/// The order constraints are given up in, for one brief.
nonisolated enum ConstraintLadder {

    /// The rungs that actually constrain this brief, least important first.
    ///
    /// A constraint the host never set is not on the ladder at all — there is
    /// nothing to give up. Ordering is `(provenance, productRank)` ascending, so a
    /// Wandr-defaulted budget is dropped before a host-stated time window even
    /// though budget outranks time on the product ordering.
    static func rungs(for brief: OutingBrief) -> [RelaxableConstraint] {
        var active: [(RelaxableConstraint, Int, Int)] = []

        func add(_ constraint: RelaxableConstraint, _ source: ValueSource) {
            active.append((constraint, weight(of: source), constraint.productRank))
        }

        // Setting and requested stops carry no `Sourced` marker: they exist in the
        // brief only because the host said something, so their presence *is* the
        // provenance.
        if brief.setting.isHardConstraint { add(.setting, .host) }
        if brief.budget.value.ceilingPerHead(for: brief.groupSize.value) != nil {
            add(.budget, brief.budget.source)
        }
        if !brief.timeWindow.value.isUnknown { add(.timeWindow, brief.timeWindow.source) }
        if !brief.requestedStops.isEmpty { add(.requestedStops, .host) }

        return active
            .sorted { lhs, rhs in
                lhs.1 == rhs.1 ? lhs.2 < rhs.2 : lhs.1 < rhs.1
            }
            .map(\.0)
    }

    /// How hard a value is to give up. A host's own word outranks anything inferred.
    private static func weight(of source: ValueSource) -> Int {
        switch source {
        case .safeDefault:     return 0
        case .modelSuggestion: return 1
        case .host:            return 2
        }
    }
}
