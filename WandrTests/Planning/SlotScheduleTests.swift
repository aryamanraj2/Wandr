//
//  SlotScheduleTests.swift
//  WandrTests
//
//  The deterministic gate that makes "free only 8–9 pm" a different night from an
//  open one. These are the assertions the two demo scenarios rest on.
//

import Foundation
import Testing
@testable import Wandr

@Suite("Slot schedule")
struct SlotScheduleTests {

    private let eightToNine = OutingTimeWindow(earliestStartMinute: 20 * 60, latestEndMinute: 21 * 60)

    // MARK: - The two headline scenarios

    @Test("Free only 8–9 pm yields exactly the dinner slot, truncated to the hour")
    func eightToNineIsDinnerOnly() throws {
        let schedule = SlotSchedule.compute(for: eightToNine)

        #expect(schedule.feasibleCategories == [.food])
        #expect(schedule.isWindowConstrained)

        let dinner = try #require(schedule.slot(for: .food))
        #expect(dinner.startMinute == 20 * 60)
        #expect(dinner.endMinute == 21 * 60)   // truncated from the 10 pm band end
        #expect(dinner.title == "Dinner")
        #expect(dinner.windowLabel == "8:00 pm – 9:00 pm")
    }

    @Test("No time frame keeps all four slots at their full bands, in time order")
    func unknownWindowKeepsEverything() {
        let schedule = SlotSchedule.compute(for: .unknown)

        #expect(schedule.feasibleCategories == [.sights, .discover, .food, .nightlife])
        #expect(!schedule.isWindowConstrained)
        // Dinner keeps its full 8–10 pm band when nothing constrains it.
        #expect(schedule.slot(for: .food)?.endMinute == 22 * 60)
    }

    // MARK: - The rule generalises

    @Test("Finish by 9 drops nightlife and truncates dinner")
    func finishByNine() throws {
        let schedule = SlotSchedule.compute(for: OutingTimeWindow(latestEndMinute: 21 * 60))

        #expect(!schedule.feasibleCategories.contains(.nightlife))
        #expect(schedule.feasibleCategories.contains(.sights))
        #expect(schedule.feasibleCategories.contains(.discover))

        let dinner = try #require(schedule.slot(for: .food))
        #expect(dinner.startMinute == 20 * 60)
        #expect(dinner.endMinute == 21 * 60)   // clamped to the 9 pm finish
    }

    @Test("After 8 pm drops the afternoon slots")
    func afterEight() {
        let schedule = SlotSchedule.compute(for: OutingTimeWindow(earliestStartMinute: 20 * 60))

        #expect(!schedule.feasibleCategories.contains(.sights))
        #expect(!schedule.feasibleCategories.contains(.discover))
        #expect(schedule.feasibleCategories.contains(.food))
        #expect(schedule.feasibleCategories.contains(.nightlife))
    }

    @Test("A slot with under an hour of room is dropped")
    func tooShortIsDropped() {
        // 8:00–8:40 pm: only 40 minutes inside the dinner band.
        let schedule = SlotSchedule.compute(for: OutingTimeWindow(earliestStartMinute: 20 * 60, latestEndMinute: 20 * 60 + 40))
        #expect(schedule.slots.isEmpty)
    }

    // MARK: - Banner

    @Test("A single-slot window banner names the hour")
    func bannerForOneStop() throws {
        let banner = try #require(GroundedPlanMapper.banner(for: SlotSchedule.compute(for: eightToNine)))
        #expect(banner.contains("8:00 pm"))
        #expect(banner.contains("one stop"))
    }

    @Test("An open plan shows no banner")
    func noBannerWhenUnconstrained() {
        #expect(GroundedPlanMapper.banner(for: SlotSchedule.compute(for: .unknown)) == nil)
    }
}
