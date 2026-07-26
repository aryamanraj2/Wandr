//
//  ChatSummaryBriefMapperTests.swift
//  WandrTests
//
//  The deterministic JSON→brief bridge. If this drifts, the model is planning for
//  the wrong group — so budget, dietary, setting, and (above all) time parsing are
//  pinned here.
//

import Foundation
import Testing
@testable import Wandr

@Suite("Chat summary brief mapper")
struct ChatSummaryBriefMapperTests {

    private let mapper = ChatSummaryBriefMapper()

    // MARK: - Budget

    @Test("Budget parsing tolerates ₹, commas, 'per head', and a k suffix")
    func budgetParsing() {
        #expect(ChatSummaryBriefMapper.rupees(from: "₹1,500") == 1_500)
        #expect(ChatSummaryBriefMapper.rupees(from: "1500 per head") == 1_500)
        #expect(ChatSummaryBriefMapper.rupees(from: "around ₹1.5k") == 1_500)
        #expect(ChatSummaryBriefMapper.rupees(from: "2k each") == 2_000)
        #expect(ChatSummaryBriefMapper.rupees(from: "no idea") == nil)
        #expect(ChatSummaryBriefMapper.rupees(from: nil) == nil)
    }

    // MARK: - Dietary

    @Test("Dietary keywords map to requirements; 'none' is explicit, junk is unknown")
    func dietaryParsing() {
        #expect(ChatSummaryBriefMapper.dietary(from: "vegetarian") == .required([.vegetarian]))
        #expect(ChatSummaryBriefMapper.dietary(from: "vegan and gluten free") == .required([.vegan, .glutenFree]))
        #expect(ChatSummaryBriefMapper.dietary(from: "no restrictions") == .noneStated)
        #expect(ChatSummaryBriefMapper.dietary(from: "we just love food") == .unknown)
        #expect(ChatSummaryBriefMapper.dietary(from: nil) == .unknown)
    }

    @Test("Accessibility keywords map, including step-free and elevator")
    func accessibilityParsing() {
        #expect(ChatSummaryBriefMapper.accessibility(from: "needs step-free entry") == .required([.stepFreeEntry]))
        #expect(ChatSummaryBriefMapper.accessibility(from: "lift access please") == .required([.elevatorAccess]))
        #expect(ChatSummaryBriefMapper.accessibility(from: nil) == .unknown)
    }

    // MARK: - Setting

    @Test("Indoor/outdoor phrases map to the right setting preference")
    func settingParsing() {
        #expect(ChatSummaryBriefMapper.setting(from: "indoor") == .indoor)
        #expect(ChatSummaryBriefMapper.setting(from: "outdoor rooftop") == .outdoor)
        #expect(ChatSummaryBriefMapper.setting(from: "either is fine") == .noPreference)
        #expect(ChatSummaryBriefMapper.setting(from: "both") == .mixed)
    }

    // MARK: - Time window (the one the demo turns on)

    @Test("A range like 'free only 8-9pm' becomes an 8–9 pm window")
    func rangeWindow() {
        let window = ChatSummaryBriefMapper.timeWindow(day: "Friday", time: "free only 8-9pm")
        #expect(window.earliestStartMinute == 20 * 60)
        #expect(window.latestEndMinute == 21 * 60)
        #expect(window.dayLabel == "Friday")
    }

    @Test("'finish by 9' sets only an upper bound, defaulting to pm")
    func upperBoundWindow() {
        let window = ChatSummaryBriefMapper.timeWindow(day: nil, time: "finish by 9")
        #expect(window.earliestStartMinute == nil)
        #expect(window.latestEndMinute == 21 * 60)
    }

    @Test("'after 8pm' sets only a lower bound")
    func lowerBoundWindow() {
        let window = ChatSummaryBriefMapper.timeWindow(day: nil, time: "after 8pm")
        #expect(window.earliestStartMinute == 20 * 60)
        #expect(window.latestEndMinute == nil)
    }

    @Test("A day with no time carries the label and stays otherwise open")
    func dayOnlyWindow() {
        let window = ChatSummaryBriefMapper.timeWindow(day: "Saturday", time: nil)
        #expect(window.dayLabel == "Saturday")
        #expect(window.earliestStartMinute == nil)
        #expect(window.latestEndMinute == nil)
        #expect(window.maximumDurationMinutes == nil)
    }

    // MARK: - Durations
    //
    // The reported bug in one line: "3 hours" and "3 o'clock" share their digits.
    // The clock scanner found the `3`, applied its unqualified-evening rule, and
    // returned a 3 pm *start* — so a host who said they were short on time got a
    // window that constrained nothing and a plan that ran until 1 am.

    @Test(
        "A stated duration is read as a length, never as a clock time",
        arguments: [
            ("3 hours", 180), ("3 hrs", 180), ("only about 3 hours", 180),
            ("2h", 120), ("90 mins", 90), ("90 minutes", 90),
            ("1.5 hours", 90), ("an hour", 60), ("a couple of hours", 120),
            ("half an hour", 30), ("hour and a half", 90), ("we have four hours", 240)
        ]
    )
    func durationIsNotAClockTime(phrase: String, minutes: Int) {
        let window = ChatSummaryBriefMapper.timeWindow(day: nil, time: phrase)

        #expect(window.maximumDurationMinutes == minutes, "\(phrase)")
        #expect(window.earliestStartMinute == nil, "\(phrase) must not become a start time")
        #expect(window.latestEndMinute == nil, "\(phrase) must not become a finish time")
    }

    @Test("A duration and a clock time coexist without eating each other's digits")
    func durationAlongsideAClockTime() {
        let window = ChatSummaryBriefMapper.timeWindow(day: "Friday", time: "from 8pm, only 3 hours")

        #expect(window.earliestStartMinute == 20 * 60)
        #expect(window.maximumDurationMinutes == 180)
        #expect(window.latestEndMinute == nil)
        #expect(window.dayLabel == "Friday")
    }

    @Test("A clock phrase with no duration is unchanged")
    func clockPhrasesKeepTheirOldMeaning() {
        let window = ChatSummaryBriefMapper.timeWindow(day: nil, time: "free only 8-9pm")

        #expect(window.earliestStartMinute == 20 * 60)
        #expect(window.latestEndMinute == 21 * 60)
        #expect(window.maximumDurationMinutes == nil)
    }

    /// Unit letters must not swallow ordinary words: "3 monday" is a day.
    @Test("A bare number next to a non-unit word is not a duration")
    func nonUnitWordsAreNotDurations() {
        #expect(ChatSummaryBriefMapper.timeWindow(day: nil, time: "3 monday").maximumDurationMinutes == nil)
        #expect(ChatSummaryBriefMapper.timeWindow(day: nil, time: "8pm").maximumDurationMinutes == nil)
    }

    @Test("An absurd duration is clamped rather than trusted")
    func absurdDurationsAreClamped() {
        let huge = ChatSummaryBriefMapper.timeWindow(day: nil, time: "400 hours")
        #expect(huge.maximumDurationMinutes == 18 * 60)

        let tiny = ChatSummaryBriefMapper.timeWindow(day: nil, time: "5 minutes")
        #expect(tiny.maximumDurationMinutes == 30)
    }

    // MARK: - What the host asked to do
    //
    // The word "lunch" decides whether the plan contains a restaurant. It is read
    // from every field it might have landed in, because the extractor puts it
    // wherever it likes and losing it costs the host the one stop they asked for.

    @Test("A meal word anywhere in the summary asks for food")
    func mealWordsRequestFood() {
        for field in ["lunch", "we want dinner", "somewhere to eat", "grab a bite"] {
            var payload = ChatSummaryPayload()
            payload.plannedStops = field

            let categories = Set(ChatSummaryBriefMapper.requestedStops(from: payload).map(\.category))
            #expect(categories.contains(.food), "\(field) should ask for food")
        }
    }

    /// The half of the request a `Set<SlotCategory>` could not carry. Both of these
    /// are `food`, and a host who says one of them does not want the other.
    @Test("Naming the meal pins the time of day", arguments: [
        ("lunch", Set<SlotBand>([.lunch])),
        ("brunch on sunday", Set<SlotBand>([.lunch])),
        ("dinner somewhere nice", Set<SlotBand>([.dinner])),
        ("lunch and then dinner", Set<SlotBand>([.lunch, .dinner]))
    ])
    func mealWordsPinTheBand(phrase: String, expected: Set<SlotBand>) {
        var payload = ChatSummaryPayload()
        payload.plannedStops = phrase

        #expect(ChatSummaryBriefMapper.requestedStops(from: payload) == expected)
    }

    /// A word that names the kind of stop but not the hour asks for every band the
    /// category owns, and lets the window decide which one it gets.
    @Test("A meal word with no hour in it leaves the choice to the window")
    func unspecificFoodAsksForBoth() {
        var payload = ChatSummaryPayload()
        payload.plannedStops = "somewhere to eat"

        #expect(ChatSummaryBriefMapper.requestedStops(from: payload) == [.lunch, .dinner])
    }

    @Test("The request is read from other fields too, not only plannedStops")
    func requestIsReadFromAnyField() {
        var inNotes = ChatSummaryPayload()
        inNotes.otherNotes = "just lunch, nothing fancy"
        #expect(ChatSummaryBriefMapper.requestedStops(from: inNotes) == [.lunch])

        var inTime = ChatSummaryPayload()
        inTime.time = "lunch time, around 12:30"
        #expect(ChatSummaryBriefMapper.requestedStops(from: inTime) == [.lunch])
    }

    @Test("Several kinds of stop are all recognised")
    func multipleCategoriesAreRecognised() {
        var payload = ChatSummaryPayload()
        payload.plannedStops = "lunch, then a walk, then drinks"

        #expect(ChatSummaryBriefMapper.requestedStops(from: payload) == [.lunch, .afternoon, .late])
    }

    @Test("Matching is whole-word, so ordinary prose does not conscript a category")
    func matchingIsWholeWord() {
        var payload = ChatSummaryPayload()
        payload.otherNotes = "somewhere walkable with a barbecue"

        let categories = Set(ChatSummaryBriefMapper.requestedStops(from: payload).map(\.category))
        #expect(!categories.contains(.sights), "'walkable' is not 'walk'")
        #expect(!categories.contains(.nightlife), "'barbecue' is not 'bar'")
    }

    @Test("A summary that names no kind of stop asks for nothing in particular")
    func noRequestIsEmpty() {
        var payload = ChatSummaryPayload()
        payload.area = "Khan Market"
        payload.groupSize = 4

        #expect(ChatSummaryBriefMapper.requestedStops(from: payload).isEmpty)
    }

    // MARK: - The model's own classification
    //
    // The keyword table is the fallback now. It can only ever recognise words
    // somebody thought to list; "something to eat before the movie" is a lunch and
    // no list of nouns will ever say so, which is the job the model does better.

    @Test("A model-classified stop list is used in preference to the keywords")
    func modelClassificationWins() {
        var payload = ChatSummaryPayload()
        payload.plannedStops = "something to eat before the movie"
        payload.stops = ["lunch"]

        #expect(ChatSummaryBriefMapper.requestedStops(from: payload) == [.lunch])
    }

    @Test("An invented token is dropped rather than trusted")
    func invalidTokensAreDropped() {
        var payload = ChatSummaryPayload()
        payload.stops = ["lunch", "brunchtime", "karaoke", "dinner"]

        #expect(ChatSummaryBriefMapper.requestedStops(from: payload) == [.lunch, .dinner])
    }

    @Test("Casing and spacing in a model token do not change the request")
    func tokensAreNormalised() {
        #expect(ChatSummaryBriefMapper.band(named: "Something New") == .somethingNew)
        #expect(ChatSummaryBriefMapper.band(named: "  LUNCH ") == .lunch)
        #expect(ChatSummaryBriefMapper.band(named: "supper") == nil)
    }

    @Test("With no usable classification, the keyword table still answers")
    func keywordsAreTheFallback() {
        var payload = ChatSummaryPayload()
        payload.plannedStops = "lunch"
        payload.stops = ["nonsense"]

        #expect(ChatSummaryBriefMapper.requestedStops(from: payload) == [.lunch])
    }

    @Test("The request reaches the draft")
    func requestReachesTheDraft() {
        var payload = ChatSummaryPayload()
        payload.plannedStops = "lunch"

        #expect(ChatSummaryBriefMapper().draft(from: payload).requestedStops == [.lunch])
    }

    /// The reported scenario, end to end through the deterministic half of the
    /// pipeline: "an outing, 12:30 to 2, lunch, in CP".
    ///
    /// What the host got instead was a monument. Three separate defects lined up —
    /// `food` had no midday band, the summary had nowhere to record "lunch", and
    /// nothing carried the request through to the schedule. This asserts the whole
    /// chain, because each piece passing on its own is what let the gap survive.
    @Test("A lunchtime plan produces a lunch slot, not a monument")
    func lunchtimePlanProducesLunch() throws {
        var payload = ChatSummaryPayload()
        payload.time = "from 12:30 to 2:00 pm"
        payload.area = "CP"
        payload.groupSize = 3
        payload.plannedStops = "lunch"

        let draft = ChatSummaryBriefMapper().draft(from: payload)
        #expect(draft.requestedStops == [.lunch])

        guard case .normalized(let brief) = try BriefNormalizer().normalize(draft) else {
            Issue.record("Expected a normalized brief")
            return
        }
        #expect(brief.requestedStops == [.lunch])

        let schedule = SlotSchedule.compute(
            for: brief.timeWindow.value,
            requesting: brief.requestedStops
        )

        #expect(schedule.feasibleCategories == [.food], "The one stop that fits must be the meal")
        let lunch = try #require(schedule.slot(for: .food))
        #expect(lunch.title == "Lunch")
        #expect(lunch.windowLabel == "12:30 pm – 2:00 pm")
    }

    /// The screenshot: "lunch", two people, ₹2000 — and a dead end reading "One pick
    /// works out to ₹2400 a head, over your ₹2000 limit."
    ///
    /// Two separate defects produced that one sentence. Nothing established whether
    /// ₹2000 was each or between them, so Wandr assumed the stricter reading and then
    /// compared it against a per-head price; and being over the ceiling was fatal
    /// rather than worth a note. Both are pinned here.
    @Test("Two people with ₹2000 between them get a lunch plan, not a dead end")
    func tightSharedBudgetStillPlans() throws {
        var payload = ChatSummaryPayload()
        payload.plannedStops = "lunch"
        payload.groupSize = 2
        payload.budget = "₹2000"

        let draft = ChatSummaryBriefMapper().draft(from: payload)
        #expect(draft.budget == .total(rupees: 2_000), "Unqualified is the group's total")
        #expect(draft.requestedStops == [.lunch])

        guard case .normalized(let brief) = try BriefNormalizer().normalize(draft) else {
            Issue.record("Expected a normalized brief")
            return
        }
        #expect(brief.budget.value.ceilingPerHead(for: brief.groupSize.value) == 1_000)

        // One stop, and it is the meal they named.
        let schedule = SlotSchedule.compute(
            for: brief.timeWindow.value,
            requesting: brief.requestedStops
        )
        #expect(schedule.slots.map(\.band) == [.lunch])

        // And whatever the dataset offers, the plan is possible: the resolver gives
        // up the ceiling rather than the outing, and says so.
        let resolution = EvidenceResolver().resolve(brief: brief, evidence: Fixtures.evidence)
        #expect(!resolution.eligible.isEmpty, "A tight budget must never empty the plan")
        #expect(resolution.eligible.contains { $0.category == .food })
    }

    /// The second report, and the harder half of it: the host said "lunch" and gave
    /// no time at all — just a group of two and a budget. They got a nightlife deck
    /// for 10 pm to 1 am.
    ///
    /// Two things had to be wrong at once. The request only *re-ranked* bands, and
    /// only for windows bounded at both ends, so an open window kept the whole table;
    /// and even once `food` won, a bare category resolved to its latest band, which
    /// is dinner. Nothing here constrains the clock, so both defects are live.
    @Test("Saying lunch and nothing about the time still means lunch, and only lunch")
    func lunchWithNoStatedTimeIsStillLunch() throws {
        var payload = ChatSummaryPayload()
        payload.plannedStops = "lunch"
        payload.groupSize = 2
        payload.budget = "₹3000"

        let draft = ChatSummaryBriefMapper().draft(from: payload)
        guard case .normalized(let brief) = try BriefNormalizer().normalize(draft) else {
            Issue.record("Expected a normalized brief")
            return
        }
        #expect(brief.timeWindow.value.isUnknown, "The host set no time — that is the point")

        let schedule = SlotSchedule.compute(
            for: brief.timeWindow.value,
            requesting: brief.requestedStops
        )

        #expect(schedule.feasibleCategories == [.food], "Nothing they didn't ask for may survive")
        let meal = try #require(schedule.slot(for: .food))
        #expect(meal.band == .lunch, "They said lunch, not dinner")
        #expect(meal.title == "Lunch")
    }

    // MARK: - Whole payload

    @Test("A full payload maps every field into the draft")
    func fullPayloadMaps() {
        let payload = ChatSummaryPayload(
            outingType: .birthday,
            dateOrDay: "Friday",
            time: "free only 8-9pm",
            area: "CP",
            groupSize: 8,
            budget: "₹1500",
            dietary: "vegetarian",
            accessibility: nil,
            vibe: "loud and fun",
            indoorOutdoor: "indoor",
            otherNotes: "someone is turning 30"
        )

        let draft = mapper.draft(from: payload)

        #expect(draft.area == "CP")
        #expect(draft.groupSize == 8)
        // "₹1500" with no "each" is the group's total — reading it as per head
        // would invent the more permissive of the two readings.
        #expect(draft.budget == .total(rupees: 1_500))
        #expect(draft.dietary == .required([.vegetarian]))
        #expect(draft.setting == .indoor)
        #expect(draft.timeWindow.earliestStartMinute == 20 * 60)
        #expect(draft.timeWindow.latestEndMinute == 21 * 60)
        #expect(draft.vibeTags == ["loud", "fun"])
        #expect(draft.notes == ["someone is turning 30"])
    }

    @Test("An empty payload maps to an all-open draft the normalizer can default")
    func emptyPayloadMaps() {
        let draft = mapper.draft(from: ChatSummaryPayload())
        #expect(draft.area == nil)
        #expect(draft.groupSize == nil)
        #expect(draft.budget == nil)
        #expect(draft.dietary == .unknown)
        #expect(draft.timeWindow.isUnknown)
    }
}
