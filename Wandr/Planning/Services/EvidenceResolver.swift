//
//  EvidenceResolver.swift
//  Wandr
//
//  The step between research and curation that decides which venues the model is
//  allowed to see — and, when the host's constraints leave nothing to show, which
//  constraint to give up so there is still a plan.
//
//  Pure Swift, no model call, no I/O. Relaxation therefore costs nothing and cannot
//  itself fail, which is the point: this is the code path that used to be a thrown
//  `PlanningFailure` and a dead end.
//
//  ## What it does
//
//  Filters the evidence under every constraint, then asks one question: does every
//  stop the host actually asked for still have something to fill it? If not, it
//  gives up the least important constraint (`ConstraintLadder`), filters again, and
//  records what it gave up so the host can be told.
//
//  Dietary and accessibility are not on the ladder and are never given up here —
//  see `ConstraintLadder` for why.
//

import Foundation

/// Resolves the evidence a brief is allowed to be planned from.
nonisolated struct EvidenceResolver: Sendable {

    /// The venues curation may use, plus every constraint that had to be given up
    /// to leave any.
    nonisolated struct Resolution: Sendable, Equatable {
        let eligible: [GroundedVenue]
        let relaxations: [PlanRelaxation]

        /// A one-line summary for the log. Constraint names only — never host text.
        var summary: String {
            let given = relaxations.map(\.constraint.rawValue).sorted()
            return "eligible=\(eligible.count) relaxed=\(given.isEmpty ? "-" : given.joined(separator: ","))"
        }
    }

    init() {}

    func resolve(brief: OutingBrief, evidence: [GroundedVenue]) -> Resolution {
        // Only the rungs this step can act on. Time window and requested stops shape
        // the *schedule*, not which venues exist, so `SlotSchedule` reports those
        // itself rather than having them relaxed twice from two different places.
        let ladder = ConstraintLadder.rungs(for: brief)
            .filter { $0 == .setting || $0 == .budget }

        // What the plan will actually ask for. Taken from the schedule rather than
        // from `requestedStops` alone: a host who named no stops still gets the
        // default shape, and a budget that leaves that shape with no restaurant is
        // just as much a dead end as one that empties a stop they asked for by name.
        let needed = Set(
            SlotSchedule.compute(for: brief.timeWindow.value, requesting: brief.requestedStops)
                .slots.map(\.category)
        )

        var relaxed: Set<RelaxableConstraint> = []
        var relaxations: [PlanRelaxation] = []
        var eligible = filter(evidence, for: brief, relaxing: relaxed)
        var rung = 0

        while !satisfies(eligible, needing: needed), rung < ladder.count {
            let next = ladder[rung]
            rung += 1
            relaxed.insert(next)

            let widened = filter(evidence, for: brief, relaxing: relaxed)

            // Only disclose a constraint whose removal actually put something back.
            // A rung that changed nothing was not a compromise the host made, and
            // telling them they gave up their budget when the venues were missing
            // for some other reason would be a worse lie than saying nothing.
            if widened.count > eligible.count {
                relaxations.append(PlanRelaxation(next, disclosure: disclosure(for: next, brief: brief)))
            }
            eligible = widened
        }

        // The ladder can run out with the plan still short. That is not a failure
        // here — an empty result becomes an honest `insufficientEvidence` upstream,
        // and a merely thin one becomes a thin deck the host can still use.
        return Resolution(eligible: eligible, relaxations: relaxations)
    }

    // MARK: - Filtering

    private func filter(
        _ evidence: [GroundedVenue],
        for brief: OutingBrief,
        relaxing relaxed: Set<RelaxableConstraint>
    ) -> [GroundedVenue] {
        let ceiling = relaxed.contains(.budget)
            ? nil
            : brief.budget.value.ceilingPerHead(for: brief.groupSize.value)

        return evidence.filter { venue in
            // Dietary and accessibility, always. `ConstraintEligibility` stays the
            // single definition of the never-relaxed rules, shared with both curators.
            guard ConstraintEligibility.isEligible(
                venue, for: brief, ignoringSetting: relaxed.contains(.setting)
            ) else { return false }

            // A venue with no known price is not *known* to break the ceiling, so it
            // survives and the validator warns about the missing price instead.
            guard let ceiling, let perHead = venue.cost.knownPerHeadRupees else { return true }
            return perHead <= ceiling
        }
    }

    /// Whether this evidence can still fill every stop the plan will contain.
    private func satisfies(_ eligible: [GroundedVenue], needing needed: Set<SlotCategory>) -> Bool {
        guard !eligible.isEmpty else { return false }
        guard !needed.isEmpty else { return true }
        return needed.isSubset(of: Set(eligible.map(\.category)))
    }

    // MARK: - Disclosure

    /// What the host is told. Specific about the constraint, never apologetic, and
    /// never a restatement of their own words.
    private func disclosure(for constraint: RelaxableConstraint, brief: OutingBrief) -> String {
        switch constraint {
        case .budget:
            guard let stated = brief.budget.value.statedRupees,
                  let basis = brief.budget.value.basisLabel else {
                return "Nothing came in under your budget — these are the closest."
            }
            return "Nothing here fits ₹\(stated) \(basis) — these are the closest we found."

        case .setting:
            return "We couldn't stay \(brief.setting.rawValue) and still fill the plan."

        case .timeWindow:
            return "We had to go a little outside the hours you gave."

        case .requestedStops:
            return "We couldn't fit every stop you asked for into that time."
        }
    }
}
