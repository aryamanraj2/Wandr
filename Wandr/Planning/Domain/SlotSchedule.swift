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
/// - Note: declared in time order, and `allCases` is relied on for that — seeded
///   growth walks outward from a named band to its neighbours, and "neighbour" means
///   the adjacent row of this table.
nonisolated enum SlotBand: String, Sendable, Hashable, CaseIterable {
    case breakfast
    case lunch
    case afternoon
    case somethingNew
    case dinner
    case late

    var category: SlotCategory {
        switch self {
        case .breakfast, .lunch, .dinner: return .food
        case .afternoon:      return .sights
        case .somethingNew:   return .discover
        case .late:           return .nightlife
        }
    }

    /// Whether naming this stop, and only this stop, implies an outing built around it.
    ///
    /// True of everything except breakfast. "Dinner" is the anchor of a night out and
    /// "a walk" is the start of an afternoon, so both are worth growing into a plan —
    /// that is the whole point of seeding. Breakfast is not: it names a complete
    /// outing by itself, and a host who asked for breakfast in Khan Market got
    /// breakfast, lunch and an activity, which is a day they never asked for.
    ///
    /// This is a rule about *growth*, not reachability. "Breakfast and then shopping"
    /// is two named stops and still means both.
    var seedsAnOuting: Bool { self != .breakfast }

    /// Every band a *vague* request may resolve to — one that named the kind of stop
    /// without naming when. "Somewhere to eat" is lunch or dinner, whichever fits.
    ///
    /// `breakfast` is deliberately absent. It is reachable only when the host names it
    /// or gives a morning window: "let's get food", said at no particular time, is not
    /// a 9 am request, and including it here would put three meals into a plan that
    /// asked for one.
    static func all(in category: SlotCategory) -> Set<SlotBand> {
        Set(allCases.filter { $0.category == category && $0 != .breakfast })
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

    /// `false` when the host named stops their own window could not hold, so the
    /// schedule fell back to the default shape. The caller turns this into a
    /// `PlanRelaxation` — a request quietly dropped is the failure mode this exists
    /// to make visible.
    let requestHonoured: Bool

    /// Which rule in `chooseBands` produced `slots`.
    ///
    /// Reported rather than re-derived, so the log cannot drift from the decision it
    /// is describing. Worth having because "I got one deck when I expected four" is a
    /// different bug for each value: `exact` means the request was read as a whole
    /// plan, `seeded` means growth found nothing that fit, `standard` means the stop
    /// never survived extraction at all.
    let shape: Shape

    /// How the plan's stops were chosen.
    nonisolated enum Shape: String, Sendable, Equatable {
        /// Nothing named — one stop per category, the latest with room.
        case standard
        /// One stop named, and the plan grown around it.
        case seeded
        /// The host described the shape, or ruled everything else out.
        case exact
    }

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
        Band(id: .breakfast,    title: "Breakfast",     startMinute: 8 * 60,       endMinute: 11 * 60 + 30), //  8:00 – 11:30 am
        Band(id: .lunch,        title: "Lunch",         startMinute: 12 * 60,      endMinute: 15 * 60 + 30), // 12:00 – 3:30 pm
        Band(id: .afternoon,    title: "Afternoon",     startMinute: 12 * 60 + 30, endMinute: 17 * 60),      // 12:30 – 5:00 pm
        Band(id: .somethingNew, title: "Something new", startMinute: 17 * 60,      endMinute: 20 * 60),      //  5:00 – 8:00 pm
        Band(id: .dinner,       title: "Dinner",        startMinute: 20 * 60,      endMinute: 22 * 60),      //  8:00 – 10:00 pm
        Band(id: .late,         title: "Late",          startMinute: 22 * 60,      endMinute: 25 * 60)       // 10:00 pm – 1:00 am
    ]

    /// The earliest minute any band opens. The literal minimum of the table.
    ///
    /// - Important: this is *not* where an unanchored plan starts — see
    ///   `defaultDayStartMinute`. Adding the breakfast band moved this from noon to
    ///   8 am, and a duration cap measured from 8 am would have quietly turned "we
    ///   have eight hours" into a plan that opens at breakfast for a host who never
    ///   mentioned morning.
    static var dayStartMinute: Int { bands.map(\.startMinute).min() ?? 0 }

    /// Where a plan opens when the host anchored it to nothing.
    ///
    /// Noon, and a literal rather than `dayStartMinute`, precisely so a new early
    /// band cannot move it. Breakfast is reachable — but only when the host asks for
    /// it by name or gives a morning window, never by default.
    static let defaultDayStartMinute = 12 * 60

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
    /// - Parameters:
    ///   - requested: the stops the host actually named. Empty means they said
    ///     nothing, and every band the window allows is kept.
    ///   - exclusive: the host said these are the *only* stops they want — "just
    ///     dinner", "only the breakfast plan". See `chooseBands` for how one named
    ///     stop differs from two.
    static func compute(
        for window: OutingTimeWindow,
        requesting requested: Set<SlotBand> = [],
        exclusive: Bool = false,
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
            exclusive: exclusive,
            minimumStopMinutes: minimumStopMinutes
        )

        return SlotSchedule(
            slots: layOut(chosen.bands, earliestStart: earliestStart, latestEnd: latestEnd,
                          minimumStopMinutes: minimumStopMinutes),
            isWindowConstrained: !window.isUnknown,
            requestHonoured: chosen.honoured,
            shape: chosen.shape
        )
    }

    /// The bands the plan will actually contain, in time order.
    ///
    /// The shape is read off the request rather than taken from a fixed template.
    /// How many stops the host named is itself the signal:
    ///
    /// 1. **Nothing named** — one band per category, the latest that still has room.
    ///    Latest, not longest: with an open evening ahead, an unspecific "somewhere to
    ///    eat" should mean dinner.
    /// 2. **One stop named** — that stop is guaranteed, and the plan is *grown* around
    ///    it (`grown(from:within:)`). A single word is a seed, not a ceiling. This used
    ///    to filter, so "dinner at Saket" came back as a lone dinner deck when what the
    ///    host wanted was an evening with dinner in it.
    /// 3. **Two or more named** — exactly those, including two that share a category.
    ///    "Lunch and dinner" describes a shape, and nothing goes in between.
    /// 4. **Exclusive** ("just dinner", "only breakfast") — exactly what they named,
    ///    however few. This is the one way to ask for a single-stop plan.
    ///
    /// Rules 2 and 3 both keep the fix that rule 1 alone could not give: the stop the
    /// host actually said is always in the plan.
    private static func chooseBands(
        earliestStart: Int?,
        latestEnd: Int?,
        requested: Set<SlotBand>,
        exclusive: Bool,
        minimumStopMinutes: Int
    ) -> (bands: [Band], honoured: Bool, shape: Shape) {

        func room(_ band: Band) -> Int {
            min(band.endMinute, latestEnd ?? band.endMinute)
                - max(band.startMinute, earliestStart ?? band.startMinute)
        }

        let fits = bands.filter { room($0) >= minimumStopMinutes }

        // When nothing the host named fits their own window — "lunch, but we're only
        // free 8 to 9" — the request is unsatisfiable, so it is dropped rather than
        // used to empty the plan. A contradicted host gets dinner, not nothing.
        let asked = fits.filter { requested.contains($0.id) }

        // In give-up order, not time order: what the host named comes before what
        // Wandr grew around it, so a window too short for everything costs them
        // filler rather than the word they actually said.
        let prioritised: [Band]
        let shape: Shape
        if asked.isEmpty {
            shape = .standard
            // Nothing named, or nothing named that fits: one stop per category, the
            // latest that has room, exactly as an unspecified outing has always worked.
            let latestPerCategory: [Band] = SlotCategory.allCases.compactMap { category in
                fits.filter { $0.category == category }.max { $0.startMinute < $1.startMinute }
            }
            prioritised = latestPerCategory.sorted { $0.startMinute < $1.startMinute }

        } else if let seed = asked.first, requested.count == 1, !exclusive, seed.id.seedsAnOuting {
            shape = .seeded
            prioritised = grown(from: seed, within: fits)

        } else {
            shape = .exact
            prioritised = asked.sorted { $0.startMinute < $1.startMinute }
        }

        let honoured = requested.isEmpty || !asked.isEmpty

        /// How many of these the host actually asked for by name.
        func named(_ list: [Band]) -> Int { list.count { requested.contains($0.id) } }

        // Only a window bounded at both ends has a budget to run out of. An open one
        // keeps everything the request allowed.
        guard let earliestStart, let latestEnd else {
            return (prioritised.sorted { $0.startMinute < $1.startMinute }, honoured, shape)
        }

        let affordable = max(0, (latestEnd - earliestStart) / minimumStopMinutes)
        let kept = Array(prioritised.prefix(affordable))

        // Dropping a stop for want of time only breaks the promise when the host
        // named it. Filler grown around a seed was Wandr's suggestion, not their
        // request, so losing it to a short window is not a request unhonoured — and
        // reporting it as one would put a "we couldn't fit everything" notice in
        // front of a host who got exactly what they asked for.
        return (kept.sorted { $0.startMinute < $1.startMinute },
                honoured && named(kept) == named(prioritised),
                shape)
    }

    /// How many stops a plan grown around a single named request aims for.
    ///
    /// Four — the same depth an unconstrained plan has. "Dinner" should come back as
    /// an afternoon, something to discover, the dinner they asked for, and somewhere
    /// to end up.
    static let targetStopCount = 4

    /// How many bands before the named one a plan may reach back over.
    ///
    /// A plan builds *towards* the thing the host said and only leads in briefly.
    /// Without the cap, "let's get drinks" grew backwards through dinner and something
    /// new all the way to a 12:30 pm afternoon — a whole day invented out of one
    /// evening word. Two is what makes "dinner" reach back to the afternoon (the
    /// asked-for case) while "late" stops at something new.
    static let maximumEarlierStops = 2

    /// The arc around a single named stop, in give-up order: the seed first, then
    /// outward to its neighbours in the band table.
    ///
    /// Later before earlier, because a night out grows forward — "dinner" reaches
    /// `late` before it reaches `afternoon`. Bands the window cannot hold are stepped
    /// over rather than ending the walk, so a 6 pm start still reaches `somethingNew`
    /// even though `afternoon` is already gone.
    ///
    /// Contiguity is what keeps the *other* report fixed: growth from `lunch` runs out
    /// of budget at `dinner`, so a host who says "lunch" is never handed a 10 pm bar.
    private static func grown(from seed: Band, within fits: [Band]) -> [Band] {
        let order = SlotBand.allCases
        guard let seedIndex = order.firstIndex(of: seed.id) else { return [seed] }

        let fitting = Dictionary(fits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var kept: [Band] = [seed]

        func extend(_ indices: [Int]) {
            for index in indices where kept.count < targetStopCount {
                if let band = fitting[order[index]] { kept.append(band) }
            }
        }

        let later = Array((seedIndex + 1)..<order.count)
        // Capped by *position*, not by how many were taken: a band the window already
        // ruled out must not buy the walk another step further into the past.
        let earlier = Array(stride(from: seedIndex - 1, through: 0, by: -1).prefix(maximumEarlierStops))

        extend(later)
        extend(earlier)

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
        guard let duration = window.maximumDurationMinutes else { return defaultDayStartMinute }
        return duration <= eveningSpanMinutes ? defaultEveningStartMinute : defaultDayStartMinute
    }

    /// The feasible slot for a band, if it survived the window.
    ///
    /// Prefer this over `slot(for:)` wherever a specific stop is meant — a schedule
    /// can hold both lunch and dinner, and asking it for "the food slot" then
    /// silently means whichever comes first.
    func slot(band: SlotBand) -> FeasibleSlot? {
        slots.first { $0.band == band }
    }

    /// The *first* feasible slot of a category. Ambiguous by nature when a plan holds
    /// two stops of one category; use `slot(band:)` when the specific stop matters.
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
