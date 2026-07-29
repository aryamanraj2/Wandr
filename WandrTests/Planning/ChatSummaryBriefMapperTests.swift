// ChatSummaryBriefMapperTests.swift WandrTests The deterministic JSON→brief bridge. If this drifts, the model is planning for the wrong group — so budget, dietary, setting, and (above all) time parsing are pinned here.

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
    // The reported bug in one line: "3 hours" and "3 o'clock" share their digits. The clock scanner found the `3`, applied its unqualified-evening rule, and returned a 3 pm *start* — so a host who said they were short on time got a window that constrained nothing and a plan that ran until 1 am.

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
    // The word "lunch" decides whether the plan contains a restaurant. It is read from every field it might have landed in, because the extractor puts it wherever it likes and losing it costs the host the one stop they asked for.

    /// Only the words that *name a meal* are read here now. "Somewhere to eat" and "grab a bite" used to resolve through a 63-word category table, which is gone: deciding that "a bite" means food is semantics, and semantics is the model's job — `PlanShape.stops` classifies it, constrained token-by-token to this vocabulary. What stays deterministic is the three meal names, because three meals is a closed set and no fourth one is coming.
    @Test("A meal named outright is read without a model")
    func mealWordsRequestFood() {
        for field in ["lunch", "we want dinner", "breakfast first"] {
            var payload = ChatSummaryPayload()
            payload.plannedStops = field

            let categories = Set(ChatSummaryBriefMapper.requestedStops(from: payload).map(\.category))
            #expect(categories.contains(.food), "\(field) should ask for food")
        }
    }

    /// The other half of the same rule: a phrase that describes food without naming a meal is the model's to classify, and Swift declines rather than guessing.
    @Test("A phrase that names no meal asks for nothing on its own")
    func unnamedFoodPhrasesNeedTheModel() {
        for field in ["somewhere to eat", "grab a bite", "ramen", "a brewery"] {
            var payload = ChatSummaryPayload()
            payload.plannedStops = field

            #expect(ChatSummaryBriefMapper.requestedStops(from: payload).isEmpty,
                    "\(field) is semantics, not vocabulary")
        }

        // And with the model's answer, it resolves — the path production actually uses.
        #expect(ChatSummaryBriefMapper.stops(classified: ["dinner"], inText: "ramen somewhere")
                == [.dinner])
    }

    /// The half of the request a `Set<SlotCategory>` could not carry. Both of these are `food`, and a host who says one of them does not want the other.
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

    /// A word that names the kind of stop but not the hour asks for every band the category owns, and lets the window decide which one it gets. "Somewhere to eat" names no meal, so it pins no band — the plan's own default shape decides, which is what an unspecified request is *for*. It used to expand to every food band through the category table; that table taught "snacks" to mean dinner, which is how a 12-to-5 request planned an 8 pm meal.
    @Test("A meal word with no hour in it leaves the choice to the plan")
    func unspecificFoodAsksForBoth() {
        var payload = ChatSummaryPayload()
        payload.plannedStops = "somewhere to eat"

        #expect(ChatSummaryBriefMapper.requestedStops(from: payload).isEmpty)
        #expect(ChatSummaryBriefMapper.stops(classified: ["lunch", "dinner"], inText: "somewhere to eat")
                == [.lunch, .dinner], "The model names the meals; the words alone do not")
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

    @Test("Several kinds of stop are all recognised, once the model has read them")
    func multipleCategoriesAreRecognised() {
        var payload = ChatSummaryPayload()
        payload.plannedStops = "lunch, then a walk, then drinks"
        // What a faithful extractor returns for that sentence. "A walk" and "drinks" are semantics; only "lunch" is vocabulary.
        payload.stops = ["lunch", "afternoon", "late"]

        #expect(ChatSummaryBriefMapper.requestedStops(from: payload) == [.lunch, .afternoon, .late])

        // Without the model, the meal survives and the rest does not — deterministically less, never differently.
        payload.stops = nil
        #expect(ChatSummaryBriefMapper.requestedStops(from: payload) == [.lunch])
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
    // Neither source outranks the other. The model is the only thing that can read "something to eat before the movie"; the host's own words are the only thing that cannot be lost to a bad generation. The keyword table used to be a mere fallback, which meant a run where the model dropped the field lost the word the host had literally typed — and the same sentence planned a different night depending on how the generation went.

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

    // MARK: - A word the host typed is never lost
    // The reported bug. "I asked for a dinner at saket ... it got most of the things right but not the DINNER." The model's `stops` came back empty, the keyword scan only ran as a fallback over fields the *same* generation had filled, and the raw text the host actually wrote was never consulted at all — so the one word that decides the whole shape of the plan disappeared with no error anywhere.

    @Test("A stop the model dropped is recovered from the host's own words")
    func rawTextRecoversADroppedStop() {
        #expect(
            ChatSummaryBriefMapper.stops(classified: [], inText: "dinner at saket for 2 people")
                == [.dinner]
        )
    }

    @Test("A stop is recovered even when the model answered with a word we don't use")
    func rawTextSurvivesAnInventedToken() {
        #expect(
            ChatSummaryBriefMapper.stops(classified: ["food"], inText: "dinner at saket")
                == [.dinner]
        )
    }

    @Test("The model's reading and the host's words are unioned, not ranked")
    func bothSourcesContribute() {
        // Only the model can classify the first half; only the text carries "dinner".
        #expect(
            ChatSummaryBriefMapper.stops(
                classified: ["somethingNew"],
                inText: "a bit of shopping and then dinner"
            ) == [.somethingNew, .dinner]
        )
    }

    /// "Drinks" is the whole second half of that plan, and it now reaches the plan through the model rather than a word list — which is the only way "a brewery", "a listening bar" or "somewhere to dance" ever get there too.
    @Test("A stop the model classified is unioned with the meals the host named")
    func modelClassificationAddsUncoveredStops() {
        #expect(
            ChatSummaryBriefMapper.stops(classified: ["dinner", "late"], inText: "dinner then drinks")
                == [.dinner, .late]
        )

        // The union is what makes the meal safe: even if the model returns only the half it understood, the word the host typed still lands.
        #expect(
            ChatSummaryBriefMapper.stops(classified: ["late"], inText: "dinner then drinks")
                == [.dinner, .late]
        )
    }

    @Test("A category word does not add a stop of a kind already asked for")
    func categoryWordsDoNotDuplicateAKind() {
        var payload = ChatSummaryPayload()
        payload.plannedStops = "dinner"
        payload.vibe = "somewhere we can get good coffee"

        // "Coffee" is a food word, but food is already covered — a mood must not put a second meal in the plan.
        #expect(ChatSummaryBriefMapper.requestedStops(from: payload) == [.dinner])
    }

    @Test("Breakfast is its own stop, not a noon lunch")
    func breakfastIsItsOwnBand() {
        #expect(ChatSummaryBriefMapper.stops(classified: nil, inText: "breakfast at 9") == [.breakfast])
    }

    // MARK: - "Just" has to be next to the stop to mean it
    // Presence alone is useless: "just" and "only" are among the commonest words in a sentence about plans, and reading every one of them as exclusivity would turn "just 2 of us for dinner" into a one-stop night.

    @Test("An exclusivity word beside a stop means exactly that stop", arguments: [
        "just dinner",
        "just the breakfast plan",
        "only doing lunch",
        "dinner and nothing else",
        "we just want lunch"
    ])
    func exclusivityIsRecognised(said: String) {
        #expect(ChatSummaryBriefMapper.statesExclusiveStops(inText: said), "\(said)")
    }

    @Test("An exclusivity word about something else does not collapse the plan", arguments: [
        "just 2 of us for dinner",
        "only 1500 each, dinner somewhere",
        "dinner at saket for 2 people",
        "we have just under three hours, dinner and drinks"
    ])
    func exclusivityIsNotOverread(said: String) {
        #expect(!ChatSummaryBriefMapper.statesExclusiveStops(inText: said), "\(said)")
    }

    // MARK: - How many people, read from the sentence
    // The reported run: "dinner and lunch for 2 near Saket with budget around 2000 each" planned for a different number of people. `groupSize` is the fifth of twelve fields in one generation, and nothing checked it against the sentence the host had actually written — where "for 2" is sitting in plain sight.

    @Test("A headcount is read exactly from the host's own words", arguments: [
        ("Let's plan dinner and lunch for 2 near Saket with budget around 2000 each", 2),
        ("8 of us, Khan Market, Saturday evening", 8),
        ("just the two of us for dinner", 2),
        ("table for 6 at 8pm", 6),
        ("a party of 12, birthday", 12),
        ("dinner, 4 people, 1500 each", 4)
    ])
    func groupSizeIsReadFromTheText(said: String, expected: Int) {
        #expect(ChatSummaryBriefMapper.groupSize(inText: said) == expected, "\(said)")
    }

    @Test("A number counting something other than people is not a headcount", arguments: [
        "we've only got 3 hours",
        "dinner, free only 8 to 9 pm",
        "dinner with budget around 2000",
        "drinks, 2k pp",
        "from 6, only three hours"
    ])
    func groupSizeIgnoresOtherNumbers(said: String) {
        #expect(ChatSummaryBriefMapper.groupSize(inText: said) == nil, "\(said)")
    }

    @Test("The model's exclusivity answer reaches the draft")
    func exclusivityReachesTheDraft() {
        var payload = ChatSummaryPayload()
        payload.plannedStops = "dinner"
        payload.onlyTheseStops = true

        #expect(ChatSummaryBriefMapper().draft(from: payload).stopsAreExclusive)
    }

    /// The reported scenario, end to end through the deterministic half of the pipeline: "an outing, 12:30 to 2, lunch, in CP". What the host got instead was a monument. Three separate defects lined up — `food` had no midday band, the summary had nowhere to record "lunch", and nothing carried the request through to the schedule. This asserts the whole chain, because each piece passing on its own is what let the gap survive.
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

    /// The screenshot: "lunch", two people, ₹2000 — and a dead end reading "One pick works out to ₹2400 a head, over your ₹2000 limit." Two separate defects produced that one sentence. Nothing established whether ₹2000 was each or between them, so Wandr assumed the stricter reading and then compared it against a per-head price; and being over the ceiling was fatal rather than worth a note. Both are pinned here.
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

        // The meal they named is in the plan. It is no longer the *whole* plan — one named stop seeds an outing built around it — but this test is about the budget, and what it needs is that lunch survives the shared-budget path.
        #expect(brief.schedule.slots.map(\.band).contains(.lunch))

        // And whatever the dataset offers, the plan is possible: the resolver gives up the ceiling rather than the outing, and says so.
        let resolution = EvidenceResolver().resolve(brief: brief, evidence: Fixtures.evidence)
        #expect(!resolution.eligible.isEmpty, "A tight budget must never empty the plan")
        #expect(resolution.eligible.contains { $0.category == .food })
    }

    /// The second report, and the harder half of it: the host said "lunch" and gave no time at all — just a group of two and a budget. They got a nightlife deck for 10 pm to 1 am. Two things had to be wrong at once. The request only *re-ranked* bands, and only for windows bounded at both ends, so an open window kept the whole table; and even once `food` won, a bare category resolved to its latest band, which is dinner. Nothing here constrains the clock, so both defects are live.
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

        let schedule = brief.schedule

        // The defect was never that the plan had other stops in it — it was that the plan had *no lunch* and did have a 10 pm bar. Both of those stay fixed.
        let meal = try #require(schedule.slot(for: .food))
        #expect(meal.band == .lunch, "They said lunch, not dinner")
        #expect(meal.title == "Lunch")
        #expect(!schedule.slots.map(\.band).contains(.late), "Nobody asked for a 10 pm bar")
        #expect(schedule.shape == .exact, "They named a stop, so the request is the plan")
    }

    /// The same sentence with the one word that makes it a single-stop plan.
    @Test("'We just want lunch' is lunch and nothing else")
    func exclusiveLunchIsOneStop() {
        var payload = ChatSummaryPayload()
        payload.plannedStops = "lunch"
        payload.onlyTheseStops = true

        let draft = ChatSummaryBriefMapper().draft(from: payload)
        guard case .normalized(let brief) = try? BriefNormalizer().normalize(draft) else {
            Issue.record("Expected a normalized brief")
            return
        }

        #expect(brief.schedule.slots.map(\.band) == [.lunch])
        #expect(brief.schedule.shape == .exact)
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
        // "₹1500" with no "each" is the group's total — reading it as per head would invent the more permissive of the two readings.
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

    // MARK: - Per-head basis, however it is spelled

    /// The invariant, not the case: **how a per-head phrase is punctuated cannot change what it means.** Quantified over the spellings of one phrase rather than over a list of examples, because the bug was never about a missing example — it was a literal-string list written with single spaces, which recognised the first spelling of every phrase and silently missed the rest. The observed failure: `"around 1000 perhead"` for seven people read as a ₹1000 group total — a ₹142 ceiling — so a ₹120 chaat counter outranked every restaurant in the deck and nothing reported a problem.
    @Test(
        "A per-head phrase means the same however it is spaced",
        arguments: ["per head", "per person", "per pax"]
    )
    func perHeadSpellingDoesNotChangeMeaning(phrase: String) {
        let closed = phrase.replacingOccurrences(of: " ", with: "")
        let hyphenated = phrase.replacingOccurrences(of: " ", with: "-")
        let doubled = phrase.replacingOccurrences(of: " ", with: "  ")

        for spelling in [phrase, closed, hyphenated, doubled] {
            #expect(
                ChatSummaryBriefMapper.statesPerHead("around 1000 \(spelling)"),
                "'\(spelling)' did not read as per head"
            )
            #expect(
                ChatSummaryBriefMapper.budget(from: "around 1000 \(spelling) budget")
                    == .perHead(rupees: 1_000),
                "'\(spelling)' produced the wrong basis"
            )
        }
    }

    /// The other half: a number with no basis stated stays the group's total, which is the weaker of the two readings and the only one the host actually said.
    @Test(
        "A phrase that does not say 'each' is still the group's total",
        arguments: [
            "around 1000",
            "1000 for the group",
            "1000 in total",
            // The words that *contain* a per-head token without being one. "reach" holds "each"; the old substring check read it as a per-head budget.
            "1000, we'll reach by 8",
            "1000, we're planning ahead",
            "1000 for shopping"
        ]
    )
    func absentBasisStaysTotal(phrase: String) {
        #expect(!ChatSummaryBriefMapper.statesPerHead(phrase), "'\(phrase)' invented a per-head basis")
        #expect(ChatSummaryBriefMapper.budget(from: phrase) == .total(rupees: 1_000))
    }

    // MARK: - A stated time survives the model dropping it

    /// The observed failure: `"after office after 5:30 pm"` came back with `time: nil`, the clause swept into `otherNotes`, and the brief's window `.unknown` — so a stated 5:30 start constrained nothing. One bound per case, named, so the tuple stays simple enough for the type checker inside a parameterised `@Test`.
    struct BoundCase: Sendable {
        let sentence: String
        let earliest: Int?
        let latest: Int?

        static func start(_ sentence: String, _ minute: Int) -> Self {
            Self(sentence: sentence, earliest: minute, latest: nil)
        }
        static func finish(_ sentence: String, _ minute: Int) -> Self {
            Self(sentence: sentence, earliest: nil, latest: minute)
        }
    }

    @Test(
        "A bound stated in prose reaches the window even with no extracted time",
        arguments: [
            BoundCase.start("after office after 5:30 pm, dinner somewhere", 17 * 60 + 30),
            BoundCase.start("dinner from 8pm", 20 * 60),
            BoundCase.start("something at 7", 19 * 60),
            BoundCase.finish("dinner before 9pm", 21 * 60),
            BoundCase.finish("we need to be done by 10:30 pm", 22 * 60 + 30)
        ]
    )
    func statedBoundSurvives(testCase: BoundCase) {
        let phrase = ChatSummaryBriefMapper.timePhrase(inText: testCase.sentence)
        let window = ChatSummaryBriefMapper.timeWindow(day: nil, time: phrase)
        let detail = "\(testCase.sentence) → \(String(describing: phrase))"

        #expect(window.earliestStartMinute == testCase.earliest, "\(detail)")
        #expect(window.latestEndMinute == testCase.latest, "\(detail)")
    }

    // MARK: - A stated budget survives the model dropping it

    @Test(
        "An amount stated in prose reaches the budget, with the basis the host gave",
        arguments: [
            ("around 1000 perhead budget for 7 people", Budget.perHead(rupees: 1_000)),
            ("dinner for 4, 2000 each", .perHead(rupees: 2_000)),
            ("₹1500 for the whole group", .total(rupees: 1_500)),
            ("we can spend 2k", .total(rupees: 2_000)),
            ("budget 800 pp, dinner at 8", .perHead(rupees: 800)),
            ("dinner for 6, rs 3000 total", .total(rupees: 3_000))
        ]
    )
    func statedAmountSurvives(sentence: String, expected: Budget) {
        let phrase = ChatSummaryBriefMapper.moneyPhrase(inText: sentence)
        #expect(
            ChatSummaryBriefMapper.budget(from: phrase) == expected,
            "\(sentence) → \(String(describing: phrase))"
        )
    }

    /// The half that matters more. An invented amount is worse than no amount: it does not widen the search, it marks real venues as over budget. So every number in a sentence that is *not* money has to read as none — a headcount, a clock, a party size, a duration.
    @Test(
        "Numbers that are not money produce no budget",
        arguments: [
            "plan an outing for 7 people, after office after 5:30 pm",
            "dinner for 4 of us at 8pm",
            "a table for 8 on saturday",
            "we've only got 3 hours",
            "6 of us, somewhere loud",
            "dinner at 9:30, 12 people"
        ]
    )
    func unmarkedNumbersAreNotMoney(sentence: String) {
        let phrase = ChatSummaryBriefMapper.moneyPhrase(inText: sentence)
        #expect(phrase == nil, "read '\(String(describing: phrase))' as money")
        #expect(ChatSummaryBriefMapper.budget(from: phrase) == nil)
    }

    /// The scan's whole discipline: a number is a time only when something *says* it is. Handing this sentence to `timeWindow` directly is what produced a window finishing before it started — 7 from "7 people", 10:00 and 00:00 from "1000".
    @Test(
        "Numbers that are not times produce no window",
        arguments: [
            "plan an outing for 7 people with around 1000 perhead budget",
            "dinner for 4 of us, 2000 each",
            "a table for 8",
            "budget is 1500 pp"
        ]
    )
    func unmarkedNumbersAreNotTimes(sentence: String) {
        let phrase = ChatSummaryBriefMapper.timePhrase(inText: sentence)
        #expect(phrase == nil, "read '\(String(describing: phrase))' as a time")
        #expect(ChatSummaryBriefMapper.timeWindow(day: nil, time: phrase).isUnknown)
    }
}
