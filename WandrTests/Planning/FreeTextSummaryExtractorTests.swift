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
            budgetPerHead: nil, dietary: nil, accessibility: nil, vibe: nil,
            indoorOutdoor: nil, otherNotes: nil
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
        extracted.budgetPerHead = "1500"

        let payload = FreeTextSummaryExtractor.payload(from: extracted)

        #expect(Set(payload.settledFieldNames) == ["area", "groupSize", "budgetPerHead"])
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
        extracted.budgetPerHead = "around 1500"
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
