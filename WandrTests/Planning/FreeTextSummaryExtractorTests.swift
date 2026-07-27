//
//  FreeTextSummaryExtractorTests.swift
//  WandrTests
//
//  The mapping half of extraction, tested without a model.
//
//  `extract(from:)` needs Apple Intelligence and cannot run in CI, but everything
//  that decides whether its answer is *safe* is pure: validating the outing type,
//  rejecting absurd group sizes, trimming blanks, and reporting which fields
//  actually settled. Those are the parts that turn a plausible-looking model answer
//  into a payload the rest of the app trusts, so those are the parts tested here.
//

import Testing
@testable import Wandr

@Suite("Free-text summary extraction")
struct FreeTextSummaryExtractorTests {

    private typealias Extracted = FreeTextSummaryExtractor.ExtractedSummary

    /// The model answered nothing at all — every field omitted.
    private func empty() -> Extracted {
        Extracted(
            outingType: nil, dateOrDay: nil, time: nil, area: nil, groupSize: nil,
            budget: nil, plannedStops: nil, dietary: nil, accessibility: nil,
            vibe: nil, indoorOutdoor: nil, otherNotes: nil
        )
    }

    // MARK: - Outing type
    //
    // Deliberately a validated String rather than a `@Generable` enum: a non-frozen
    // one traps on a case the model invents, and this is the one field with a fixed
    // vocabulary the model can plausibly get wrong.

    @Test("A valid outing type maps through")
    func validOutingTypeMaps() {
        var extracted = empty()
        extracted.outingType = "after-office"

        #expect(FreeTextSummaryExtractor.payload(from: extracted).outingType == .afterOffice)
    }

    @Test("Case and whitespace do not defeat the mapping")
    func outingTypeIsNormalised() {
        var extracted = empty()
        extracted.outingType = "  Birthday  "

        #expect(FreeTextSummaryExtractor.payload(from: extracted).outingType == .birthday)
    }

    // MARK: - Echoed values
    //
    // The reported bug. A host who said only "outing at 12:30, lunch" got back an
    // outing type of after-office, an accessibility requirement of "step-free entry",
    // and a vibe of "quiet" — none of which they had said, and all three of which
    // were verbatim copies of the sample values in Wandr's own `@Guide` descriptions.
    // The examples are gone now; these are the backstop that makes the echo
    // unreachable even if a future guide reintroduces one.

    @Test("An outing type the host's words do not support is dropped")
    func unsupportedOutingTypeIsDropped() {
        var extracted = empty()
        extracted.outingType = "after-office"

        let payload = FreeTextSummaryExtractor.payload(
            from: extracted,
            source: "outing tomorrow around 12:30, we want lunch"
        )
        #expect(payload.outingType == nil, "Nothing in that sentence is about work")
    }

    @Test("An outing type the host did support survives")
    func supportedOutingTypeSurvives() {
        var extracted = empty()
        extracted.outingType = "after-office"

        let payload = FreeTextSummaryExtractor.payload(
            from: extracted,
            source: "drinks after office on Friday"
        )
        #expect(payload.outingType == .afterOffice)
    }

    @Test("get-together claims nothing specific, so it is never second-guessed")
    func genericOutingTypeIsKept() {
        var extracted = empty()
        extracted.outingType = "get-together"

        #expect(
            FreeTextSummaryExtractor.payload(from: extracted, source: "let's go out").outingType
                == .getTogether
        )
    }

    @Test("A constraint the host never mentioned is dropped rather than shown to them")
    func inventedConstraintsAreDropped() {
        var extracted = empty()
        extracted.accessibility = "step-free entry"
        extracted.vibe = "quiet"

        let payload = FreeTextSummaryExtractor.payload(
            from: extracted,
            source: "outing tomorrow around 12:30, we want lunch"
        )

        #expect(payload.accessibility == nil)
        #expect(payload.vibe == nil)
    }

    @Test("A constraint the host did raise survives, including a reworded one")
    func realConstraintsSurvive() {
        var extracted = empty()
        extracted.accessibility = "wheelchair access"
        extracted.vibe = "somewhere quiet"

        let payload = FreeTextSummaryExtractor.payload(
            from: extracted,
            source: "somewhere quiet please, and one of us uses a wheelchair"
        )

        #expect(payload.accessibility == "wheelchair access", "A reading is not an invention")
        #expect(payload.vibe == "somewhere quiet")
    }

    @Test("With no source text to check against, values pass through untouched")
    func noSourceMeansNoFiltering() {
        var extracted = empty()
        extracted.vibe = "quiet"

        #expect(FreeTextSummaryExtractor.payload(from: extracted).vibe == "quiet")
    }

    // MARK: - What the host wants to do

    @Test("The kind of stop the host asked for reaches the payload")
    func plannedStopsSurvive() {
        var extracted = empty()
        extracted.plannedStops = "lunch and a walk after"

        let payload = FreeTextSummaryExtractor.payload(from: extracted, source: "lunch and a walk after")
        #expect(payload.plannedStops == "lunch and a walk after")
        #expect(payload.settledFieldNames.contains("plannedStops"))
    }

    @Test("An invented outing type becomes nil, not a crash")
    func unknownOutingTypeIsDropped() {
        var extracted = empty()
        extracted.outingType = "wedding-reception"

        #expect(FreeTextSummaryExtractor.payload(from: extracted).outingType == nil)
    }

    // MARK: - Group size

    @Test("A sensible group size survives")
    func groupSizePassesThrough() {
        var extracted = empty()
        extracted.groupSize = 8

        #expect(FreeTextSummaryExtractor.payload(from: extracted).groupSize == 8)
    }

    /// The reported run. The model settled a `groupSize`, and the plan came back for
    /// the wrong number of people — so the host's own "for 2" now wins over it.
    @Test("The host's own headcount beats the model's")
    func rawTextHeadcountWinsOverTheModel() {
        var extracted = empty()
        extracted.groupSize = 5

        let payload = FreeTextSummaryExtractor.payload(
            from: extracted,
            source: "Let's plan dinner and lunch for 2 near Saket with budget around 2000 each"
        )
        #expect(payload.groupSize == 2)
    }

    @Test("With nothing readable in the text, the model's headcount still stands")
    func modelHeadcountSurvivesAnUnreadableSentence() {
        var extracted = empty()
        extracted.groupSize = 6

        // No "for N" or "N of us" anywhere — the model is the only source there is.
        #expect(
            FreeTextSummaryExtractor.payload(from: extracted, source: "a few of us want dinner")
                .groupSize == 6
        )
    }

    @Test("An absurd group size is rejected rather than clamped silently")
    func absurdGroupSizeIsDropped() {
        for value in [0, -4, 5_000] {
            var extracted = empty()
            extracted.groupSize = value

            #expect(
                FreeTextSummaryExtractor.payload(from: extracted).groupSize == nil,
                "\(value) should not reach the brief"
            )
        }
    }

    // MARK: - Blanks

    @Test("Whitespace-only fields are treated as unsaid")
    func blankFieldsBecomeNil() {
        var extracted = empty()
        extracted.area = "   "
        extracted.vibe = "\n\t"
        extracted.otherNotes = ""

        let payload = FreeTextSummaryExtractor.payload(from: extracted)

        #expect(payload.area == nil)
        #expect(payload.vibe == nil)
        #expect(payload.otherNotes == nil)
        #expect(payload.isEmpty, "A payload of blanks must read as nothing settled")
    }

    @Test("Values are trimmed, not passed through raw")
    func valuesAreTrimmed() {
        var extracted = empty()
        extracted.area = "  Khan Market \n"

        #expect(FreeTextSummaryExtractor.payload(from: extracted).area == "Khan Market")
    }

    // MARK: - Settled fields
    //
    // What the log reports. Names only — the values are the host's own words and
    // never appear in a `.public` log field.

    @Test("Only the fields that carry a value are reported as settled")
    func settledFieldNamesAreAccurate() {
        var extracted = empty()
        extracted.area = "Cyber Hub"
        extracted.groupSize = 6
        extracted.budget = "1500"

        let payload = FreeTextSummaryExtractor.payload(from: extracted)

        #expect(Set(payload.settledFieldNames) == ["area", "groupSize", "budget"])
    }

    @Test("An empty answer settles nothing")
    func emptyExtractionSettlesNothing() {
        let payload = FreeTextSummaryExtractor.payload(from: empty())

        #expect(payload.settledFieldNames.isEmpty)
        #expect(payload.isEmpty)
    }

    // MARK: - A realistic answer

    @Test("A typical spoken plan maps to a usable payload")
    func realisticExtractionIsUsable() {
        var extracted = empty()
        extracted.outingType = "get-together"
        extracted.area = "Khan Market"
        extracted.groupSize = 8
        extracted.budget = "around 1500"
        extracted.vibe = "somewhere lively"
        extracted.dateOrDay = "Saturday"

        let payload = FreeTextSummaryExtractor.payload(from: extracted)

        #expect(!payload.isEmpty)
        #expect(payload.outingType == .getTogether)
        #expect(payload.area == "Khan Market")
        #expect(payload.groupSize == 8)
        // Unsaid stays unsaid — the normalizer marks these `.safeDefault` and tells
        // the host, which an invented value would prevent.
        #expect(payload.dietary == nil)
        #expect(payload.accessibility == nil)
    }
}
