// DaySpanTests.swift WandrTests The span the schedule's ruler covers. The property that matters is containment: every stop on the day has to fall inside the range the timeline is drawn against, because a stop outside it is not clipped or squeezed — it is drawn at a negative offset, outside the timeline, over the rest of the screen.

import Foundation
import Testing
@testable import Wandr

@Suite("Day span")
struct DaySpanTests {

    private static let day = DemoPlan.days[0].id

    private static func stop(at start: Int, minutes: Int = 90) -> ScheduleBlock {
        ScheduleBlock(title: "Stop", category: .food,
                      startMinute: start, durationMinutes: minutes, dayID: day)
    }

    /// The property the whole type exists for. Everything else here is a specific way this can be violated.
    private func expectContains(_ stops: [ScheduleBlock], _ range: ClosedRange<Int>,
                                sourceLocation: SourceLocation = #_sourceLocation) {
        for stop in stops {
            #expect(range.contains(stop.startMinute), sourceLocation: sourceLocation)
            #expect(range.contains(stop.endMinute), sourceLocation: sourceLocation)
        }
    }

    @Test("A morning plan is contained, not drawn above the timeline")
    func morningPlanIsContained() {
        // The reported failure: with a fixed 9am start, an 8am stop resolved to a negative offset and rendered on top of the masthead.
        let stops = [Self.stop(at: 8 * 60)]
        let range = DaySpan.covering(stops)

        expectContains(stops, range)
        #expect(range.lowerBound <= 8 * 60)
    }

    @Test("The day can start at midnight without underflowing")
    func midnightStartIsContained() {
        let stops = [Self.stop(at: 0, minutes: 60)]
        let range = DaySpan.covering(stops)

        expectContains(stops, range)
        #expect(range.lowerBound >= DaySpan.envelope.lowerBound)
    }

    @Test("A close past midnight stays on the ruler")
    func lateCloseIsContained() {
        // Stops are minutes from midnight, so a 10pm start running three hours ends at 25:00 — past the end of the calendar day and past where a fixed midnight bound could reach.
        let stops = [Self.stop(at: 22 * 60, minutes: 180)]
        let range = DaySpan.covering(stops)

        expectContains(stops, range)
        #expect(range.upperBound >= 25 * 60)
    }

    @Test("An all-day plan spans first stop to last")
    func allDayPlanIsContained() {
        let stops = [
            Self.stop(at: 8 * 60),
            Self.stop(at: 13 * 60),
            Self.stop(at: 20 * 60, minutes: 150)
        ]
        let range = DaySpan.covering(stops)

        expectContains(stops, range)
    }

    @Test("The demo evening plan is contained")
    func demoPlanIsContained() {
        let stops = DemoPlan.blocks(for: DemoPlan.days[0])
        expectContains(stops, DaySpan.covering(stops))
    }

    @Test("Bounds land on whole hours, so they fall on labelled gridlines")
    func boundsAreWholeHours() {
        let range = DaySpan.covering([Self.stop(at: 9 * 60 + 25, minutes: 50)])

        #expect(range.lowerBound % 60 == 0)
        #expect(range.upperBound % 60 == 0)
    }

    @Test("A single short stop still gets a ruler worth dragging against")
    func shortStopGetsMinimumSpan() {
        let range = DaySpan.covering([Self.stop(at: 20 * 60, minutes: 30)])

        #expect(range.upperBound - range.lowerBound >= DaySpan.minimumSpan)
    }

    @Test("An unplanned day falls back to an evening rather than an empty range")
    func emptyDayFallsBack() {
        let range = DaySpan.covering([])

        #expect(range == DaySpan.unplanned)
        #expect(range.upperBound > range.lowerBound)
    }

    @Test("Padding never pushes the span outside the envelope")
    func paddingStaysInsideEnvelope() {
        // Both ends sit close enough to the envelope that unbounded padding would cross it.
        let stops = [Self.stop(at: 30, minutes: 30), Self.stop(at: 25 * 60, minutes: 60)]
        let range = DaySpan.covering(stops)

        #expect(range.lowerBound >= DaySpan.envelope.lowerBound)
        #expect(range.upperBound <= DaySpan.envelope.upperBound)
        expectContains(stops, range)
    }

    @Test("Containment outranks the envelope")
    func contentBeyondEnvelopeIsStillContained() {
        // A plan running past the envelope loses its padding, not its ruler: a stop drawn outside the range is drawn outside the timeline, which is the failure this type exists to prevent.
        let stops = [Self.stop(at: 26 * 60, minutes: 90)]
        let range = DaySpan.covering(stops)

        expectContains(stops, range)
    }

    @Test("Padding leaves room above the first stop and below the last")
    func paddingSurroundsThePlan() {
        let stops = [Self.stop(at: 13 * 60, minutes: 60)]
        let range = DaySpan.covering(stops)

        #expect(range.lowerBound < 13 * 60)
        #expect(range.upperBound > 14 * 60)
    }
}
