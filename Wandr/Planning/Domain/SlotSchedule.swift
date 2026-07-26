//
//  SlotSchedule.swift
//  Wandr
//
//  The one place the group's time window decides the *shape* of the night.
//
//  A brief that says "we're free 8–9 pm" must produce a materially different plan
//  from one that says nothing at all: fewer slots, truncated windows, fewer poll
//  rounds. That decision is deterministic — it is not the model's job — and it
//  lives here so three surfaces can never disagree:
//
//    1. which decks the curator generates (it only fills feasible slots),
//    2. the window label each deck shows on the "Pick your stops" page,
//    3. the blocks `ScheduleDrafter` lays on the timeline.
//
//  Foundation only. No model, no UI, no I/O.
//
//  Deferred, and deliberately so: matching an *individual venue's* opening hours
//  against the window. `openWindow` is still a label at this layer, and the
//  validator's `unknownHours` warning still rides along. We gate *slots*, not
//  venue hours, in this cut.
//

import Foundation

/// One row of the band table — a kind of stop *at a time of day*.
///
/// The unit a host actually names. "Lunch" and "dinner" are both `SlotCategory.food`
/// and they are not the same stop, so a `Set<SlotCategory>` cannot carry what the
/// host said: a group who asked for lunch and named no clock time was handed a
/// dinner deck, because `food` resolved to its latest band. The request is expressed
/// in these instead, and a category-level word ("food", "eat") simply asks for every
/// band the category owns.
nonisolated enum SlotBand: String, Sendable, Hashable, CaseIterable {
    case lunch
    case afternoon
    case somethingNew
    case dinner
    case late

    var category: SlotCategory {
        switch self {
        case .lunch, .dinner: return .food
        case .afternoon:      return .sights
        case .somethingNew:   return .discover
        case .late:           return .nightlife
        }
    }

    /// Every band that serves `category`, for a request that named the kind of stop
    /// without naming when — "somewhere to eat" is lunch *or* dinner, whichever fits.
    static func all(in category: SlotCategory) -> Set<SlotBand> {
        Set(allCases.filter { $0.category == category })
    }
}

/// The slots that fit a time window, in time order, each with its intersected window.
nonisolated struct SlotSchedule: Sendable, Equatable {

    /// One slot that survived the window, with the window it actually occupies.
    nonisolated struct FeasibleSlot: Sendable, Equatable, Identifiable {
        /// Which row of the band table this came from — "lunch" and "dinner" are one
        /// category and two very different stops.
        let band: SlotBand
        /// Human name for the slot, matching the curation deck titles ("Dinner").
        let title: String
        /// Minutes from midnight. `startMinute < endMinute`, always ≥ `minimumStopMinutes` apart.
        let startMinute: Int
        let endMinute: Int

        var category: SlotCategory { band.category }

        /// A schedule holds at most one slot per category, so the category identifies it.
        var id: SlotCategory { category }

        /// e.g. "8:00 pm – 9:00 pm". The label the deck header and schedule show.
        var windowLabel: String {
            "\(SlotSchedule.clock(startMinute)) – \(SlotSchedule.clock(endMinute))"
        }
    }

    /// Feasible slots, ordered earliest-first.
    let slots: [FeasibleSlot]

    /// Whether the host actually constrained the time at all. Drives the
    /// "you're only free 8–9 pm" banner — an unconstrained plan shows no banner.
    let isWindowConstrained: Bool

    // MARK: - Bands
    //
    // Each slot owns a time-of-day band, taken from the schedule template and the
    // deck windows the design already uses. Nightlife runs past midnight, so its
    // end is expressed as minutes past midnight *continuing* (25:00 = 1 am).

    /// A slot's default band and display name, before any window is applied.
    private nonisolated struct Band {
        let id: SlotBand
        let title: String
        let startMinute: Int
        let endMinute: Int

        var category: SlotCategory { id.category }
    }

    /// Every band a category can occupy, in time order.
    ///
    /// A category may appear more than once. `food` used to exist only from 8 pm,
    /// which meant a group asking for lunch at 12:30 was shown *no restaurants at
    /// all* — the only band their window touched was `sights`, so the model picked a
    /// monument and looked like it had ignored the word "lunch". It had never been
    /// offered a restaurant. A category with no band over the host's hours is a
    /// category the plan silently cannot contain.
    private static let bands: [Band] = [
        Band(id: .lunch,        title: "Lunch",         startMinute: 12 * 60,      endMinute: 15 * 60 + 30), // 12:00 – 3:30 pm
        Band(id: .afternoon,    title: "Afternoon",     startMinute: 12 * 60 + 30, endMinute: 17 * 60),      // 12:30 – 5:00 pm
        Band(id: .somethingNew, title: "Something new", startMinute: 17 * 60,      endMinute: 20 * 60),      //  5:00 – 8:00 pm
        Band(id: .dinner,       title: "Dinner",        startMinute: 20 * 60,      endMinute: 22 * 60),      //  8:00 – 10:00 pm
        Band(id: .late,         title: "Late",          startMinute: 22 * 60,      endMinute: 25 * 60)       // 10:00 pm – 1:00 am
    ]

    /// The earliest a plan ever opens. Named rather than read off `bands.first`, so
    /// reordering the table cannot quietly move when the day starts.
    static var dayStartMinute: Int { bands.map(\.startMinute).min() ?? 0 }

    /// Where a duration-capped outing starts when the host named no start time.
    ///
    /// The Dinner band. Wandr plans nights out — every band title downstream of here
    /// says so, and the clock parser already reads a bare "8" as 8 pm — so a group
    /// with three free hours and no stated start is planning an evening, not a
    /// lunchtime. Anchoring at the first band instead would spend the whole cap on
    /// the afternoon and reproduce the bug this cap exists to fix.
    static let defaultEveningStartMinute = 20 * 60

    /// The span the evening bands cover (8 pm – 1 am). A cap longer than this cannot
    /// be an evening, so it anchors at the top of the day instead.
    private static var eveningSpanMinutes: Int {
        (bands.last?.endMinute ?? 0) - defaultEveningStartMinute
    }

    // MARK: - Computation

    /// The slots that fit `window`, each intersected with it.
    ///
    /// A slot is kept iff `[earliestStart ?? bandStart, latestEnd ?? bandEnd]`
    /// overlaps its band by at least `minimumStopMinutes`. An `.unknown` window
    /// keeps every slot at its full band.
    ///
    /// A stated `maximumDurationMinutes` closes the window from the right: the
    /// outing may not run past `start + duration`, where `start` is the host's own
    /// earliest time when they gave one and `defaultEveningStartMinute` when they
    /// did not. This is the only thing that makes "we've only got 3 hours" produce
    /// a materially shorter night — a duration cannot be expressed as a clock bound,
    /// so before this it expressed nothing at all.
    /// - Parameter requested: the stops the host actually named. A non-empty request
    ///   *is* the plan: nothing they didn't ask for survives. Empty means they said
    ///   nothing, and every band the window allows is kept, exactly as before.
    static func compute(
        for window: OutingTimeWindow,
        requesting requested: Set<SlotBand> = [],
        minimumStopMinutes: Int = 60
    ) -> SlotSchedule {
        let anchor = anchorStart(for: window)
        let cappedEnd = window.maximumDurationMinutes.map { anchor + $0 }

        let latestEnd: Int? = {
            switch (window.latestEndMinute, cappedEnd) {
            case (let stated?, let capped?): return min(stated, capped)
            case (let stated?, nil):         return stated
            case (nil, let capped?):         return capped
            case (nil, nil):                 return nil
            }
        }()

        // The cap moves the *start* too when the host gave no time of day at all —
        // otherwise "3 hours" would still open at the afternoon band and the cap
        // would only trim the tail of a full day.
        let earliestStart = window.earliestStartMinute
            ?? (window.hasDurationCap ? anchor : nil)

        let chosen = chooseBands(
            earliestStart: earliestStart,
            latestEnd: latestEnd,
            requested: requested,
            minimumStopMinutes: minimumStopMinutes
        )

        return SlotSchedule(
            slots: layOut(chosen, earliestStart: earliestStart, latestEnd: latestEnd,
                          minimumStopMinutes: minimumStopMinutes),
            isWindowConstrained: !window.isUnknown
        )
    }

    /// The bands the plan will actually contain, in time order.
    ///
    /// Two rules, in order:
    ///
    /// 1. **A named request filters.** A host who says "lunch" is telling you what the
    ///    outing *is*, not which of four stops they feel most strongly about. This used
    ///    to be a mere tiebreak inside a capacity budget that only ran for windows
    ///    bounded at both ends — so a host who said "lunch" and named no clock time got
    ///    every band in the table, nightlife included, and the word they actually said
    ///    changed nothing at all.
    /// 2. **One band per category — the latest that still has room.** Latest, not
    ///    longest: with an open evening ahead, an unspecific "somewhere to eat" should
    ///    mean dinner. The lunch band is what a window that never reaches 8 pm, or a
    ///    host who said "lunch" outright, falls back to.
    private static func chooseBands(
        earliestStart: Int?,
        latestEnd: Int?,
        requested: Set<SlotBand>,
        minimumStopMinutes: Int
    ) -> [Band] {

        func room(_ band: Band) -> Int {
            min(band.endMinute, latestEnd ?? band.endMinute)
                - max(band.startMinute, earliestStart ?? band.startMinute)
        }

        let fits = bands.filter { room($0) >= minimumStopMinutes }

        // When nothing the host named fits their own window — "lunch, but we're only
        // free 8 to 9" — the request is unsatisfiable, so it is dropped rather than
        // used to empty the plan. A contradicted host gets dinner, not nothing.
        let asked = fits.filter { requested.contains($0.id) }
        let pool = asked.isEmpty ? fits : asked

        let perCategory: [Band] = SlotCategory.allCases.compactMap { category in
            pool.filter { $0.category == category }.max { $0.startMinute < $1.startMinute }
        }
        let ordered = perCategory.sorted { $0.startMinute < $1.startMinute }

        // Only a window bounded at both ends has a budget to run out of. An open one
        // keeps everything the request allowed.
        guard let earliestStart, let latestEnd else { return ordered }

        var capacity = latestEnd - earliestStart
        var kept: [Band] = []
        for band in ordered where capacity >= minimumStopMinutes {
            kept.append(band)
            capacity -= minimumStopMinutes
        }

        return kept
    }

    /// Places the chosen bands end to end inside the window.
    ///
    /// Sequential, not independent: intersecting each band with the window on its own
    /// produced stops that overlapped each other, so a ninety-minute window could
    /// claim to hold three separate hour-long stops.
    private static func layOut(
        _ chosen: [Band],
        earliestStart: Int?,
        latestEnd: Int?,
        minimumStopMinutes: Int
    ) -> [FeasibleSlot] {

        var slots: [FeasibleSlot] = []
        var cursor = earliestStart ?? chosen.first?.startMinute ?? 0
        var remaining = chosen.count

        for band in chosen {
            remaining -= 1

            let start = max(cursor, band.startMinute, earliestStart ?? Int.min)
            var end = min(band.endMinute, latestEnd ?? Int.max)
            // Leave every later stop its minimum, so an early one cannot eat the night.
            if let latestEnd {
                end = min(end, latestEnd - remaining * minimumStopMinutes)
            }

            guard end - start >= minimumStopMinutes else { continue }

            slots.append(
                FeasibleSlot(band: band.id, title: band.title,
                             startMinute: start, endMinute: end)
            )
            cursor = end
        }

        return slots
    }

    /// The minute a duration cap is measured from.
    ///
    /// The host's own start when they gave one. Otherwise the evening anchor, unless
    /// the cap is longer than an evening — a group with eight free hours is planning
    /// a day, and starting them at 8 pm would throw most of their time past midnight.
    private static func anchorStart(for window: OutingTimeWindow) -> Int {
        if let stated = window.earliestStartMinute { return stated }
        guard let duration = window.maximumDurationMinutes else { return dayStartMinute }
        return duration <= eveningSpanMinutes ? defaultEveningStartMinute : dayStartMinute
    }

    /// The feasible slot for a category, if it survived the window.
    func slot(for category: SlotCategory) -> FeasibleSlot? {
        slots.first { $0.category == category }
    }

    /// The categories that fit, in time order — what the curator should fill.
    var feasibleCategories: [SlotCategory] { slots.map(\.category) }

    // MARK: - Clock

    /// Minutes-from-midnight → "8:00 pm" / "12:30 am". Pure, and tolerant of the
    /// nightlife band running past 24:00 (25:00 renders as "1:00 am").
    static func clock(_ minute: Int) -> String {
        let h24 = (minute / 60) % 24
        let m = minute % 60
        let suffix = h24 < 12 ? "am" : "pm"
        var h = h24 % 12
        if h == 0 { h = 12 }
        return m == 0 ? "\(h):00 \(suffix)" : String(format: "%d:%02d %@", h, m, suffix)
    }
}
