//
//  SchedulePresentation.swift
//  Wandr
//
//  The schedule half of the bridge: a pure mapping from a drafted schedule to
//  the `PlanDay`/`ScheduleBlock` shapes the timeline draws.
//
//  Foundation only, no SwiftUI. Minutes are carried verbatim — every number on
//  the timeline is one the drafter disclosed an assumption for, never one this
//  file made up.
//

import Foundation

enum SchedulePresentation {

    /// Maps a draft into the timeline's day bar and blocks.
    ///
    /// The drafter assumes one sitting (`.singleDayAssumed`), so the day bar
    /// spans exactly the single day the draft covers — dated from the plan's own
    /// `generatedAt`, not from an ambient clock, so the mapping stays pure.
    static func schedule(
        from draft: ScheduleDraft,
        plan: WandrPlan,
        calendar: Calendar = .current
    ) -> (days: [PlanDay], blocks: [ScheduleBlock]) {
        let day = PlanDay(date: calendar.startOfDay(for: plan.generatedAt))

        let blocks = draft.blocks.map { block in
            ScheduleBlock(
                title: block.title,
                category: PlanPresentation.stopCategory(block.category),
                startMinute: block.startMinute,
                durationMinutes: block.durationMinutes,
                dayID: day.id
            )
        }

        return ([day], blocks)
    }
}
