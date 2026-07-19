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
            budgetPerHead: "₹1500",
            dietary: "vegetarian",
            accessibility: nil,
            vibe: "loud and fun",
            indoorOutdoor: "indoor",
            otherNotes: "someone is turning 30"
        )

        let draft = mapper.draft(from: payload)

        #expect(draft.area == "CP")
        #expect(draft.groupSize == 8)
        #expect(draft.budgetPerHeadRupees == 1_500)
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
        #expect(draft.budgetPerHeadRupees == nil)
        #expect(draft.dietary == .unknown)
        #expect(draft.timeWindow.isUnknown)
    }
}
