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

    // MARK: - Duration caps
    //
    // The reported bug: a host who said "3 hours" got a whole day out. A duration
    // had nowhere to live on `OutingTimeWindow`, so the clock parser read the bare
    // "3" as 3 pm and produced a *start* with no end — which keeps all four bands
    // and is strictly worse than saying nothing at all.

    @Test("Three hours with no stated start plans an evening, not a whole day")
    func threeHoursIsNotAWholeDay() throws {
        let schedule = SlotSchedule.compute(for: OutingTimeWindow(maximumDurationMinutes: 180))

        #expect(schedule.isWindowConstrained)
        #expect(schedule.feasibleCategories == [.food, .nightlife])
        #expect(!schedule.feasibleCategories.contains(.sights))

        let dinner = try #require(schedule.slot(for: .food))
        #expect(dinner.startMinute == SlotSchedule.defaultEveningStartMinute)

        let last = try #require(schedule.slots.last)
        #expect(last.endMinute - dinner.startMinute == 180, "The plan must fit inside the cap")
    }

    @Test("A duration cap is measured from the host's own start when they gave one")
    func durationRunsFromTheStatedStart() throws {
        // "from 6, only three hours" — 6–9 pm.
        let schedule = SlotSchedule.compute(
            for: OutingTimeWindow(earliestStartMinute: 18 * 60, maximumDurationMinutes: 180)
        )

        let first = try #require(schedule.slots.first)
        let last = try #require(schedule.slots.last)
        #expect(first.startMinute == 18 * 60)
        #expect(last.endMinute == 21 * 60)
        #expect(!schedule.feasibleCategories.contains(.nightlife), "10 pm is past the cap")
    }

    @Test("The tighter of a stated finish and a duration cap wins")
    func tighterBoundWins() throws {
        // "from 8, back by 9, we've got three hours" — the 9 pm finish is the real limit.
        let schedule = SlotSchedule.compute(
            for: OutingTimeWindow(
                earliestStartMinute: 20 * 60,
                latestEndMinute: 21 * 60,
                maximumDurationMinutes: 180
            )
        )

        #expect(schedule.feasibleCategories == [.food])
        #expect(schedule.slot(for: .food)?.endMinute == 21 * 60)
    }

    @Test("One hour leaves room for exactly one stop")
    func oneHourIsOneStop() {
        let schedule = SlotSchedule.compute(for: OutingTimeWindow(maximumDurationMinutes: 60))

        #expect(schedule.feasibleCategories == [.food])
    }

    /// A cap longer than an evening is a day out, so it anchors at the top of the
    /// day. Anchoring it at 8 pm would push most of the host's time past midnight.
    @Test("A cap longer than an evening starts in the afternoon")
    func longCapStartsEarly() throws {
        let schedule = SlotSchedule.compute(for: OutingTimeWindow(maximumDurationMinutes: 8 * 60))

        let first = try #require(schedule.slots.first)
        #expect(first.category == .sights)
        #expect(first.startMinute == 12 * 60 + 30)
        #expect(!schedule.feasibleCategories.contains(.nightlife))
    }

    @Test("A duration alone still counts as a constrained window")
    func durationCountsAsConstrained() {
        #expect(!OutingTimeWindow(maximumDurationMinutes: 180).isUnknown)
        #expect(SlotSchedule.compute(for: OutingTimeWindow(maximumDurationMinutes: 180)).isWindowConstrained)
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
