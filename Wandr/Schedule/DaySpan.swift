// DaySpan.swift Wandr How much clock the schedule's ruler covers for one day. This is arithmetic rather than layout, which is why it lives outside the view: getting it wrong does not make the timeline look slightly off, it draws stops outside the timeline entirely, and that is worth being able to test directly.

import Foundation

/// The stretch of the clock a day's timeline is drawn against, derived from the stops actually planned on it.
///
/// The schedule used to hold this fixed at 9am–midnight, which silently assumed every plan was an evening one. Nothing clamped a stop to that assumption, so a breakfast at 8am resolved to a *negative* vertical offset and was drawn above the top of the timeline, on top of the masthead; a stop running past midnight fell off the bottom the same way. Deriving the bounds from the content is what makes a morning plan, an all-day plan, and a 2am close each get a ruler that contains them.
enum DaySpan {

    /// Air kept above the first stop and below the last, so the plan sits *in* the day rather than flush against the ends of the ruler — and so a stop has somewhere to be dragged when it needs to move outside the current span.
    static let padding = 2 * 60

    /// The shortest ruler worth drawing. A single 30-minute stop against a 30-minute timeline gives a drag nowhere to go and reads as a fragment rather than an evening.
    static let minimumSpan = 5 * 60

    /// How far the ruler is padded out beyond the plan: midnight through 3am the following morning. Stops are stored as minutes from midnight and a late close legitimately runs past 24:00, so this has to reach past the end of the calendar day — but it also has to stop somewhere, or the ruler can be walked off into an unbounded scroll one drag at a time.
    ///
    /// It bounds the *padding* only. It is never allowed to clip a stop — see `covering(_:)`.
    static let envelope = 0...(27 * 60)

    /// Where a day starts and ends when nothing is planned on it yet.
    static let unplanned = (18 * 60)...(24 * 60)

    /// The span covering `stops`, padded and snapped to whole hours.
    ///
    /// Containment is the invariant, and it outranks every other rule here. A stop outside the returned range is not clipped or compressed by the timeline — it is positioned relative to the range, so it is drawn *outside* the timeline and over whatever else is on screen. That is the failure this type exists to prevent, so the envelope and the padding both give way to it rather than the other way round.
    static func covering(_ stops: [ScheduleBlock]) -> ClosedRange<Int> {
        guard let earliest = stops.map(\.startMinute).min(),
              let latest = stops.map(\.endMinute).max()
        else { return unplanned }

        // Whole hours on both ends, so the bounds always land on a labelled gridline rather than mid-hour.
        let contentLower = Int((Double(earliest) / 60).rounded(.down)) * 60
        let contentUpper = Int((Double(latest) / 60).rounded(.up)) * 60

        var lower = max(envelope.lowerBound, contentLower - padding)
        var upper = min(envelope.upperBound, contentUpper + padding)

        // Grow whichever end has room. Reaching down first keeps the plan's start where the eye already expects it.
        if upper - lower < minimumSpan {
            upper = min(envelope.upperBound, lower + minimumSpan)
            lower = max(envelope.lowerBound, upper - minimumSpan)
        }

        // The last word: a plan that runs past the envelope keeps its ruler. Losing two hours of padding is a cosmetic compromise; losing a stop off the end of the timeline is the bug.
        return min(lower, contentLower)...max(upper, contentUpper)
    }
}
