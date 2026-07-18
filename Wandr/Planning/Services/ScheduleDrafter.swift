//
//  ScheduleDrafter.swift
//  Wandr
//
//  Pure Swift. Turns a validated plan into a timeline.
//
//  Every number this file produces is disclosed. A start minute that isn't backed
//  by a `ScheduleAssumption` in the returned draft is a bug — the tests assert the
//  correspondence in both directions, because "the app quietly decided 8pm" is
//  exactly the kind of invented fact the planning core exists to prevent.
//
//  Travel time between stops is NOT verified: MapKit is out of scope for this
//  step, so `.travelTimeNotVerified` rides on every draft this type produces.
//

import Foundation

/// The real `ScheduleDrafting` implementation.
nonisolated struct ScheduleDrafter: ScheduleDrafting, Sendable {

    /// The disclosed start-time template, in minutes from midnight.
    ///
    /// Chosen to match the deck windows the current curation UI already shows
    /// ("Dinner 8:00 – 10:00 pm", "Late 10:00 pm – late", "Afternoon", "flexible"),
    /// so Step 5's UI bridge is a small diff rather than a re-timing.
    nonisolated struct Template: Sendable, Equatable {
        var sights: Int
        var discover: Int
        var food: Int
        var nightlife: Int
        var durationMinutes: Int

        static let `default` = Template(
            sights: 12 * 60 + 30,   // 12:30 pm
            discover: 17 * 60,      //  5:00 pm
            food: 20 * 60,          //  8:00 pm
            nightlife: 22 * 60,     // 10:00 pm
            durationMinutes: 90
        )

        func startMinute(for category: SlotCategory) -> Int {
            switch category {
            case .sights: return sights
            case .discover: return discover
            case .food: return food
            case .nightlife: return nightlife
            }
        }
    }

    let template: Template

    init(template: Template = .default) {
        self.template = template
    }

    func draftSchedule(for plan: WandrPlan, evidence: [GroundedVenue]) throws -> ScheduleDraft {

        let evidenceByID = Dictionary(
            evidence.map { ($0.venueID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var assumptions: [ScheduleAssumption] = []
        var blocks: [ScheduleDraftBlock] = []

        // Slots are laid out in template order, not curation order, so two slots of
        // the same category resolve their collision deterministically.
        let ordered = plan.slots.sorted { lhs, rhs in
            let left = template.startMinute(for: lhs.category)
            let right = template.startMinute(for: rhs.category)
            return left == right ? lhs.slotID < rhs.slotID : left < right
        }

        for slot in ordered {
            guard let candidate = leadingCandidate(of: slot) else { continue }

            // The validator already guarantees this resolves. If it somehow doesn't,
            // say so with the existing named violation rather than dropping a stop.
            guard let venue = evidenceByID[candidate.venueID] else {
                throw PlanningFailure.validationFailed(
                    [.unknownVenue(slotID: slot.slotID, venueID: candidate.venueID)]
                )
            }

            let start = nextAvailableStart(
                for: slot.category,
                after: blocks,
                duration: template.durationMinutes
            )

            blocks.append(
                ScheduleDraftBlock(
                    slotID: slot.slotID,
                    venueID: venue.venueID,
                    title: venue.name,
                    category: venue.category,
                    startMinute: start,
                    durationMinutes: template.durationMinutes
                )
            )

            // Both numbers on the block above are defaults, so both get disclosed.
            assumptions.append(.defaultStartMinute(start))
            assumptions.append(
                .defaultDuration(minutes: template.durationMinutes, slotID: slot.slotID)
            )
        }

        // True of every schedule this step can produce.
        assumptions.append(.travelTimeNotVerified)
        assumptions.append(.singleDayAssumed)

        return ScheduleDraft(
            planID: plan.id,
            blocks: blocks,
            assumptions: assumptions,
            // Carried forward unchanged. The drafter cannot remove a warning, and
            // has none of its own to add in this step.
            warnings: plan.warnings
        )
    }

    // MARK: - Helpers

    /// The rank-1 pick, falling back to the best-ranked candidate present so a
    /// curator that numbers from zero still produces a schedule.
    private func leadingCandidate(of slot: CurationSlot) -> CuratedCandidate? {
        slot.candidates.first { $0.rank == 1 } ?? slot.candidates.min { $0.rank < $1.rank }
    }

    /// The template start for this category, pushed past any block already sitting
    /// there. Two `food` slots become 8:00 and 9:30 rather than two stops at once.
    private func nextAvailableStart(
        for category: SlotCategory,
        after blocks: [ScheduleDraftBlock],
        duration: Int
    ) -> Int {
        var start = template.startMinute(for: category)
        while blocks.contains(where: { $0.startMinute == start }) {
            start += duration
        }
        return start
    }
}
