//
//  SchedulePresentationTests.swift
//  WandrTests
//
//  The schedule half of the bridge: drafted minutes reach the timeline
//  verbatim, and the day bar spans only the day the draft covers.
//

import Foundation
import Testing
@testable import Wandr

@MainActor
@Suite("SchedulePresentation")
struct SchedulePresentationTests {

    private func plan() -> WandrPlan {
        WandrPlan(
            runID: Fixtures.runID,
            brief: Fixtures.afterWorkBrief,
            slots: Fixtures.validSlots,
            warnings: [],
            evidenceIDs: [],
            evidenceSources: [Fixtures.source],
            evidence: Fixtures.evidence,
            generatedAt: Fixtures.now
        )
    }

    private func draft() -> ScheduleDraft {
        ScheduleDraft(
            planID: PlanID(),
            blocks: [
                ScheduleDraftBlock(
                    slotID: SlotID("dinner"), venueID: VenueID("food-1"),
                    title: "Venue food-1", category: .food,
                    startMinute: 20 * 60, durationMinutes: 90
                ),
                ScheduleDraftBlock(
                    slotID: SlotID("late"), venueID: VenueID("night-1"),
                    title: "Venue night-1", category: .nightlife,
                    startMinute: 22 * 60, durationMinutes: 90
                )
            ],
            assumptions: [.travelTimeNotVerified, .singleDayAssumed]
        )
    }

    @Test("Drafted minutes, titles, and categories reach the timeline verbatim")
    func minutesCarryVerbatim() {
        let (_, blocks) = SchedulePresentation.schedule(from: draft(), plan: plan())

        #expect(blocks.count == 2)
        #expect(blocks[0].title == "Venue food-1")
        #expect(blocks[0].category == .food)
        #expect(blocks[0].startMinute == 20 * 60)
        #expect(blocks[0].durationMinutes == 90)
        #expect(blocks[0].endMinute == 21 * 60 + 30)
        #expect(blocks[1].title == "Venue night-1")
        #expect(blocks[1].category == .nightlife)
        #expect(blocks[1].startMinute == 22 * 60)
    }

    @Test("The day bar spans only the single day the draft covers")
    func singleDayOnly() {
        let calendar = Calendar(identifier: .gregorian)
        let (days, blocks) = SchedulePresentation.schedule(
            from: draft(), plan: plan(), calendar: calendar
        )

        #expect(days.count == 1)
        #expect(days[0].date == calendar.startOfDay(for: Fixtures.now))
        let allOnDay = blocks.allSatisfy { $0.dayID == days[0].id }
        #expect(allOnDay)
    }

    @Test("An empty draft maps to a single empty day, not an invented block")
    func emptyDraftStaysEmpty() {
        let empty = ScheduleDraft(planID: PlanID(), blocks: [])
        let (days, blocks) = SchedulePresentation.schedule(from: empty, plan: plan())

        #expect(days.count == 1)
        #expect(blocks.isEmpty)
    }
}
