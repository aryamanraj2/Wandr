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
        // Lunch, not sightseeing: a day starting at half twelve starts with a meal.
        // The dinner band is past the cap, so `food` falls back to its lunch band —
        // which is the whole point of a category owning more than one band.
        #expect(first.category == .food)
        #expect(first.title == "Lunch")
        // `defaultDayStartMinute`, not `dayStartMinute`: the breakfast band moved the
        // table's literal minimum to 8 am, but an unanchored plan still opens at noon.
        #expect(first.startMinute == SlotSchedule.defaultDayStartMinute)
        #expect(!schedule.feasibleCategories.contains(.nightlife))
        // Stops are laid end to end, never stacked on the same hour.
        #expect(zip(schedule.slots, schedule.slots.dropFirst()).allSatisfy { $0.endMinute <= $1.startMinute })
    }

    @Test("A duration alone still counts as a constrained window")
    func durationCountsAsConstrained() {
        #expect(!OutingTimeWindow(maximumDurationMinutes: 180).isUnknown)
        #expect(SlotSchedule.compute(for: OutingTimeWindow(maximumDurationMinutes: 180)).isWindowConstrained)
    }

    // MARK: - Lunch
    //
    // The reported bug: "outing, 12:30 to 2, lunch" came back with a monument. The
    // `food` category existed only from 8 pm, so a midday window touched exactly one
    // band — `sights` — and the model was never shown a restaurant to choose. It had
    // not misunderstood "lunch"; it had never been offered lunch.

    @Test("A midday window can contain a meal")
    func middayWindowReachesFood() throws {
        let schedule = SlotSchedule.compute(
            for: OutingTimeWindow(earliestStartMinute: 12 * 60 + 30, latestEndMinute: 14 * 60)
        )

        #expect(schedule.feasibleCategories.contains(.food), "Lunch must be reachable at lunchtime")
        #expect(schedule.slot(for: .food)?.title == "Lunch")
    }

    @Test("Asking for lunch in a short window gets the meal, not whatever starts first")
    func requestedCategoryWinsATightWindow() throws {
        let window = OutingTimeWindow(earliestStartMinute: 12 * 60 + 30, latestEndMinute: 14 * 60)
        let schedule = SlotSchedule.compute(for: window, requesting: [.lunch])

        #expect(schedule.feasibleCategories == [.food])

        let lunch = try #require(schedule.slot(for: .food))
        #expect(lunch.title == "Lunch")
        #expect(lunch.startMinute == 12 * 60 + 30)
        #expect(lunch.endMinute == 14 * 60)
    }

    @Test("Asking for sights in the same window gets sights instead")
    func requestSteersTheSameWindowElsewhere() {
        let window = OutingTimeWindow(earliestStartMinute: 12 * 60 + 30, latestEndMinute: 14 * 60)
        let schedule = SlotSchedule.compute(for: window, requesting: [.afternoon])

        #expect(schedule.feasibleCategories == [.sights])
    }

    /// "Somewhere to eat" names no hour, so it asks for both meal bands and the
    /// window picks. An open evening is dinner.
    @Test("An evening window still means dinner, not lunch")
    func eveningStillMeansDinner() throws {
        let schedule = SlotSchedule.compute(for: eightToNine, requesting: [.lunch, .dinner])

        let dinner = try #require(schedule.slot(for: .food))
        #expect(dinner.title == "Dinner")
        #expect(dinner.startMinute == 20 * 60)
    }

    // MARK: - One named stop seeds the plan
    //
    // Two reports, and they pull in opposite directions:
    //
    //   1. "still i just said lunch" — the plan came back with a 10 pm nightlife deck.
    //      The named stop was only ever a tiebreak, so an open window ignored it and
    //      the word did nothing.
    //   2. "dinner at saket ... only showing me dinner options instead of the whole
    //      list from afternoon to late" — fixing (1) by making the request a hard
    //      filter over-corrected: one word became the entire plan.
    //
    // Seeded growth satisfies both. The named stop is guaranteed, the plan is built
    // around it, and growth is contiguous — so "lunch" grows forward into dinner and
    // runs out of budget before it ever reaches a bar.

    @Test("One named stop is a seed, and the plan is built around it")
    func oneNamedStopSeedsTheArc() {
        let schedule = SlotSchedule.compute(for: .unknown, requesting: [.dinner])

        #expect(schedule.slots.map(\.band) == [.afternoon, .somethingNew, .dinner, .late])
        #expect(schedule.shape == .seeded)
        #expect(schedule.requestHonoured)
    }

    @Test("The earlier report stays fixed: lunch never reaches a 10 pm bar")
    func seedingLunchNeverReachesNightlife() throws {
        let schedule = SlotSchedule.compute(for: .unknown, requesting: [.lunch])

        let bands = schedule.slots.map(\.band)
        #expect(bands.contains(.lunch), "The word they actually said must be in the plan")
        #expect(!bands.contains(.late), "Nobody asked for a 10 pm bar")
        #expect(try #require(schedule.slots.first).band == .lunch,
                "A bare `food` would have resolved to dinner")
    }

    @Test("Growth reaches back only so far, so an evening word is not a whole day")
    func growthDoesNotInventAMorning() {
        let schedule = SlotSchedule.compute(for: .unknown, requesting: [.late])

        #expect(schedule.slots.map(\.band) == [.somethingNew, .dinner, .late])
        #expect(!schedule.slots.map(\.band).contains(.lunch), "'Drinks' is not a day out")
    }

    @Test("Exclusive means exactly what was named, however few")
    func exclusiveCollapsesToTheNamedStops() {
        let schedule = SlotSchedule.compute(for: .unknown, requesting: [.dinner], exclusive: true)

        #expect(schedule.slots.map(\.band) == [.dinner])
        #expect(schedule.shape == .exact)
        #expect(schedule.requestHonoured)
    }

    @Test("Filler lost to a short window is not a broken promise")
    func droppedFillerStillCountsAsHonoured() {
        // Free only 8–9 pm, and they asked for dinner. The grown arc cannot fit, but
        // the stop they named did — so nothing was taken from them.
        let schedule = SlotSchedule.compute(for: eightToNine, requesting: [.dinner])

        #expect(schedule.slots.map(\.band) == [.dinner])
        #expect(schedule.requestHonoured, "They asked for dinner and got dinner")
    }

    @Test("A seeded stop outranks the filler grown around it when time is short")
    func theSeedSurvivesTheCapacityTrim() {
        // 12:30–2 holds one stop. Lunch starts earlier than afternoon, so a trim that
        // simply took stops in time order would hand them lunch instead.
        let window = OutingTimeWindow(earliestStartMinute: 12 * 60 + 30, latestEndMinute: 14 * 60)
        let schedule = SlotSchedule.compute(for: window, requesting: [.afternoon])

        #expect(schedule.slots.map(\.band) == [.afternoon])
    }

    // MARK: - Breakfast
    //
    // There was no breakfast band at all: the table opened at noon and "breakfast" was
    // a keyword for `.lunch`, so a host asking for one was scheduled a 12 o'clock meal.

    @Test("A morning plan is now representable")
    func breakfastIsReachable() throws {
        let morning = OutingTimeWindow(earliestStartMinute: 9 * 60, latestEndMinute: 11 * 60 + 30)
        let schedule = SlotSchedule.compute(for: morning, requesting: [.breakfast])

        let breakfast = try #require(schedule.slot(band: .breakfast))
        #expect(breakfast.title == "Breakfast")
        #expect(breakfast.startMinute == 9 * 60)
        #expect(schedule.requestHonoured)
    }

    @Test("Breakfast is opt-in: an unanchored plan still opens at noon")
    func breakfastIsNeverADefault() {
        let schedule = SlotSchedule.compute(for: .unknown)

        #expect(!schedule.slots.map(\.band).contains(.breakfast))
        #expect(SlotSchedule.defaultDayStartMinute == 12 * 60)
    }

    @Test("A vague 'somewhere to eat' never resolves to breakfast")
    func vagueFoodExcludesBreakfast() {
        #expect(SlotBand.all(in: .food) == [.lunch, .dinner])
    }

    /// The reported case: "breakfast in khan market" came back as breakfast, lunch and
    /// an activity. Seeding is right for a stop that anchors an outing — dinner earns
    /// an afternoon in front of it — but breakfast *is* the outing.
    @Test("Breakfast names a whole outing, so it does not grow one")
    func breakfastDoesNotSeedADay() {
        let schedule = SlotSchedule.compute(for: .unknown, requesting: [.breakfast])

        #expect(schedule.slots.map(\.band) == [.breakfast])
        #expect(schedule.shape == .exact, "Nothing was grown around it")
        #expect(!SlotBand.breakfast.seedsAnOuting)
        #expect(SlotBand.allCases.filter { !$0.seedsAnOuting } == [.breakfast],
                "Every other stop is worth building a plan around")
    }

    @Test("Breakfast named alongside another stop still means both")
    func breakfastStillCombines() {
        let schedule = SlotSchedule.compute(for: .unknown, requesting: [.breakfast, .somethingNew])

        #expect(schedule.slots.map(\.band) == [.breakfast, .somethingNew])
    }

    @Test("Two named stops give exactly two stops, in time order")
    func requestOfTwoGivesTwo() {
        let schedule = SlotSchedule.compute(for: .unknown, requesting: [.dinner, .late])

        #expect(schedule.feasibleCategories == [.food, .nightlife])
        #expect(schedule.slots.map(\.title) == ["Dinner", "Late"])
    }

    /// The host contradicted themselves: lunch, but free only from 8 pm. An
    /// unsatisfiable request is dropped rather than used to empty the plan.
    @Test("A request the window cannot hold falls back rather than planning nothing")
    func impossibleRequestFallsBack() throws {
        let schedule = SlotSchedule.compute(for: eightToNine, requesting: [.lunch])

        #expect(!schedule.slots.isEmpty, "An impossible request must not erase the night")
        let stop = try #require(schedule.slots.first)
        #expect(stop.band == .dinner)
    }

    @Test("An empty request still keeps everything the window allows")
    func noRequestKeepsEverything() {
        let schedule = SlotSchedule.compute(for: .unknown, requesting: [])

        #expect(schedule.feasibleCategories == [.sights, .discover, .food, .nightlife])
    }

    // MARK: - Two stops of one category
    //
    // "if a user mentions a lunch and a dinner no in between fine — just show them
    // lunch and a dinner". Impossible until slots stopped being keyed by category:
    // both are `.food`, so one overwrote the other in the curator, the squad poll,
    // and the schedule alike.

    @Test("Lunch and dinner are two stops, with nothing in between")
    func lunchAndDinnerAreTwoStops() throws {
        let schedule = SlotSchedule.compute(for: .unknown, requesting: [.lunch, .dinner])

        #expect(schedule.slots.map(\.band) == [.lunch, .dinner])
        #expect(schedule.slots.map(\.title) == ["Lunch", "Dinner"])
        #expect(schedule.feasibleCategories == [.food, .food])
        #expect(!schedule.feasibleCategories.contains(.sights), "Nothing in between")
        #expect(!schedule.feasibleCategories.contains(.nightlife))

        // And they are still laid out in time order, not stacked.
        let lunch = try #require(schedule.slot(band: .lunch))
        let dinner = try #require(schedule.slot(band: .dinner))
        #expect(lunch.endMinute <= dinner.startMinute)
    }

    /// `slot(for:)` answers "the first food stop", which is the wrong question once a
    /// plan holds two of them.
    @Test("A specific stop is reachable by band, not by category")
    func bandLookupDisambiguates() throws {
        let schedule = SlotSchedule.compute(for: .unknown, requesting: [.lunch, .dinner])

        #expect(try #require(schedule.slot(band: .lunch)).title == "Lunch")
        #expect(try #require(schedule.slot(band: .dinner)).title == "Dinner")
    }

    // MARK: - An unhonoured request is reported

    @Test("A request the window cannot hold is reported, not silently dropped")
    func unhonouredRequestIsFlagged() {
        // Lunch, but free only 8–9 pm.
        #expect(!SlotSchedule.compute(for: eightToNine, requesting: [.lunch]).requestHonoured)
        #expect(SlotSchedule.compute(for: eightToNine, requesting: [.dinner]).requestHonoured)
        #expect(SlotSchedule.compute(for: .unknown, requesting: []).requestHonoured)
    }

    /// Bands used to be intersected with the window one at a time, so three of them
    /// could each claim the same ninety minutes and the schedule would promise three
    /// stops that all started at once.
    @Test("Stops never overlap each other", arguments: [
        OutingTimeWindow(earliestStartMinute: 12 * 60, latestEndMinute: 22 * 60),
        OutingTimeWindow(earliestStartMinute: 12 * 60 + 30, latestEndMinute: 14 * 60),
        OutingTimeWindow(maximumDurationMinutes: 240),
        OutingTimeWindow(latestEndMinute: 21 * 60),
        .unknown
    ])
    func stopsAreLaidEndToEnd(window: OutingTimeWindow) {
        let slots = SlotSchedule.compute(for: window).slots

        for (earlier, later) in zip(slots, slots.dropFirst()) {
            #expect(earlier.endMinute <= later.startMinute,
                    "\(earlier.title) runs into \(later.title)")
        }
        #expect(slots.allSatisfy { $0.endMinute - $0.startMinute >= 60 })
    }

    @Test("A window is never promised more stops than it can hold")
    func stopCountFitsTheWindow() {
        // Ninety minutes is one stop, whatever else overlaps it.
        let schedule = SlotSchedule.compute(
            for: OutingTimeWindow(earliestStartMinute: 12 * 60 + 30, latestEndMinute: 14 * 60)
        )
        #expect(schedule.slots.count == 1)
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
