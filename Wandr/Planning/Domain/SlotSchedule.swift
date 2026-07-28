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
    case earlyStart
    case breakfast
    case midMorning
    case lunch
    case afternoon
    case somethingNew
    case dinner
    case late

    /// What a row is *for*, which is what decides whether the schedule may add it.
    ///
    /// The day is a spine: meals sit at fixed times and everything else fills the space
    /// between two of them. That distinction is the one this type was missing, and its
    /// absence is why every stop had to be either named or grown — there was no way to
    /// say "this belongs between the two things you asked for".
    nonisolated enum Role: Sendable, Hashable {
        /// A meal. Fixed on the clock, and the thing a host actually names.
        case anchor
        /// Fills the space between two anchors. Has no time of its own — see
        /// `SlotSchedule.interludeCount(forGapOf:pace:)`.
        case interlude
    }

    var role: Role {
        switch self {
        case .breakfast, .lunch, .dinner: return .anchor
        case .earlyStart, .midMorning, .afternoon, .somethingNew, .late: return .interlude
        }
    }

    var category: SlotCategory {
        switch self {
        case .breakfast, .lunch, .dinner: return .food
        case .earlyStart, .afternoon: return .sights
        case .midMorning, .somethingNew: return .discover
        case .late: return .nightlife
        }
    }

    /// Whether this stop is reachable only when the host asks for it.
    ///
    /// The morning is opt-in. Wandr plans nights out by default, so an unanchored
    /// request must not open at six in the morning — but "breakfast then a wander" has
    /// to remain expressible, which it was not while the table began at noon.
    var isOptIn: Bool {
        switch self {
        case .earlyStart, .breakfast, .midMorning: return true
        case .lunch, .afternoon, .somethingNew, .dinner, .late: return false
        }
    }

    /// Every band a *vague* request may resolve to — one that named the kind of stop
    /// without naming when. "Somewhere to eat" is lunch or dinner, whichever fits.
    ///
    /// The opt-in bands are deliberately absent. They are reachable only when the host
    /// names one or gives a morning window: "let's get food", said at no particular
    /// time, is not a 9 am request, and including breakfast here would put three meals
    /// into a plan that asked for one.
    static func all(in category: SlotCategory) -> Set<SlotBand> {
        Set(allCases.filter { $0.category == category && !$0.isOptIn })
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
    /// different bug for each value: `exact` means the host named the stops, so a
    /// short plan is a short *request*; `standard` means nothing they said survived
    /// extraction at all, which is an extraction bug wearing a scheduling costume.
    let shape: Shape

    /// How fast the group wants to move, which is the only thing that decides how many
    /// stops fill a gap.
    ///
    /// A property of the *occasion*, not of the clock: a first date and five colleagues
    /// with two hours to kill want different numbers of stops out of the same
    /// afternoon. The model reads it from what the host said; nothing here counts
    /// anything, and nothing here knows what a date is.
    nonisolated enum Pace: String, Sendable, Hashable, Codable, CaseIterable {
        case unhurried
        case steady
        case packed

        /// Minutes a group at this pace is content to give one stop, travel included.
        ///
        /// This is the definition of the pace, not a tuning knob for a failing case.
        /// Changing it changes what "unhurried" *means*, everywhere and consistently.
        var intervalMinutes: Int {
            switch self {
            case .unhurried: return 150
            case .steady:    return 125
            case .packed:    return 100
            }
        }
    }

    /// How the plan's stops were chosen.
    ///
    /// Two values, and deliberately not three. There used to be a `seeded` rule that
    /// took a single named stop and grew it outward to a target count — that is
    /// inference performed *on top of an explicit request*, and it is what turned
    /// "lunch and snacks, 12 to 5" into a plan ending at an 8 pm dinner. A host who
    /// names their stops gets their stops.
    nonisolated enum Shape: String, Sendable, Equatable {
        /// Nothing named — one stop per category, the latest with room.
        case standard
        /// The host named the stops. Growth is not reachable from here.
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
    /// The spine, in time order. Anchors are the meals; everything else fills between
    /// them.
    ///
    /// The windows on interlude rows are their *widest* extent, not their allocation —
    /// `layOut` narrows them to the gap they actually land in. Anchors are the fixed
    /// points, and they are what the rest is measured from.
    private static let bands: [Band] = [
        Band(id: .earlyStart,   title: "Early start",   startMinute: 6 * 60,       endMinute: 8 * 60),       //  6:00 – 8:00 am
        Band(id: .breakfast,    title: "Breakfast",     startMinute: 8 * 60,       endMinute: 10 * 60 + 30), //  8:00 – 10:30 am
        Band(id: .midMorning,   title: "Mid-morning",   startMinute: 10 * 60 + 30, endMinute: 12 * 60),      // 10:30 – 12:00
        Band(id: .lunch,        title: "Lunch",         startMinute: 12 * 60,      endMinute: 15 * 60 + 30), // 12:00 – 3:30 pm
        Band(id: .afternoon,    title: "Afternoon",     startMinute: 12 * 60 + 30, endMinute: 17 * 60),      // 12:30 – 5:00 pm
        Band(id: .somethingNew, title: "Something new", startMinute: 17 * 60,      endMinute: 20 * 60),      //  5:00 – 8:00 pm
        Band(id: .dinner,       title: "Dinner",        startMinute: 20 * 60,      endMinute: 22 * 60),      //  8:00 – 10:00 pm
        Band(id: .late,         title: "Late",          startMinute: 22 * 60,      endMinute: 25 * 60)       // 10:00 pm – 1:00 am
    ]

    /// The earliest minute any band opens. The literal minimum of the table.
    ///
    /// - Important: this is *not* where an unanchored plan starts — see
    ///   `defaultDayStartMinute`. The morning rows moved this from noon to 6 am, and a
    ///   duration cap measured from 6 am would have quietly turned "we have eight
    ///   hours" into a plan that opens before breakfast for a host who never mentioned
    ///   the morning at all.
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
        pace: Pace = .steady,
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
            pace: pace,
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
    /// Two rules, and the boundary between them is whether the host said anything at
    /// all about what they want to do:
    ///
    /// 1. **Nothing named** — one band per category, the latest that still has room.
    ///    Latest, not longest: with an open evening ahead, an unspecific "somewhere to
    ///    eat" should mean dinner. There is no request here to be wrong about, so
    ///    proposing a whole day is Wandr being useful rather than Wandr overriding
    ///    anyone.
    /// 2. **Anything named** — exactly those stops, plus whatever fills the gaps
    ///    *between* them. Not a floor to build on and not a seed to grow: the list,
    ///    and the spaces the list itself brackets.
    ///
    /// There used to be a third rule between these, and removing it is the point of
    /// this change. A single named stop was treated as a *seed* and grown outward to
    /// `targetStopCount`, on the theory that "dinner at Saket" wants an evening built
    /// around it. The theory is defensible; the mechanism is not, because it performs
    /// inference on top of an explicit request and there is no window in which to
    /// check its work. "12 to 5, lunch and snacks" collapsed to one recognised stop,
    /// hit that branch, and grew forward to an 8 pm dinner — two hours past a stated
    /// finish, from a sentence that named two stops.
    ///
    /// Filling the space *between* two named stops is a different operation and a
    /// legitimate one: it is bounded on both sides by something the host said. That is
    /// what interludes are for, and it is why they are derived from the gap rather
    /// than counted towards a target.
    private static func chooseBands(
        earliestStart: Int?,
        latestEnd: Int?,
        requested: Set<SlotBand>,
        exclusive: Bool,
        pace: Pace,
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

        // In give-up order, not time order: what the host named comes before anything
        // Wandr added, so a window too short for everything costs them filler rather
        // than the word they actually said.
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

        } else {
            shape = .exact
            let named = asked.sorted { $0.startMinute < $1.startMinute }
            // Named stops first, then the fill: give-up order, so a window too short
            // for everything costs them an interlude rather than a stop they asked for.
            //
            // "Nothing else" is the one phrase that turns the fill off. Without it a
            // host naming two stops is describing where their evening starts and ends,
            // not forbidding anything in between.
            prioritised = exclusive
                ? named
                : named + interludes(between: named, within: fits, pace: pace)
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
        // named it. A band Wandr proposed was its suggestion, not their request, so
        // losing it to a short window is not a request unhonoured — and reporting it
        // as one would put a "we couldn't fit everything" notice in front of a host
        // who got exactly what they asked for.
        return (kept.sorted { $0.startMinute < $1.startMinute },
                honoured && named(kept) == named(prioritised),
                shape)
    }

    // MARK: - Interludes

    /// Fewest and most stops one gap may hold.
    ///
    /// The floor is 1 because a gap wide enough to notice is a gap worth filling; the
    /// ceiling is 3 because past that a plan stops being an evening and becomes an
    /// itinerary. Neither is derived from a failing example — they bound a formula,
    /// they do not encode a case.
    static let minimumInterludesPerGap = 1
    static let maximumInterludesPerGap = 3

    /// How many stops belong in a gap of `gapMinutes`, at `pace`.
    ///
    /// The count is *computed*, never chosen. Writing "two stops between lunch and
    /// dinner" would be right for exactly the window it was written against and wrong
    /// for the next one — an eight-hour gap and a ninety-minute gap are not both two
    /// stops. Dividing by the pace's own interval is the whole rule.
    ///
    /// A gap of nothing gets nothing; that is the one case the floor must not apply to.
    static func interludeCount(forGapOf gapMinutes: Int, pace: Pace) -> Int {
        guard gapMinutes > 0 else { return 0 }
        let raw = Int((Double(gapMinutes) / Double(pace.intervalMinutes)).rounded())
        return min(max(raw, minimumInterludesPerGap), maximumInterludesPerGap)
    }

    /// The stops that fill the spaces between the ones the host named.
    ///
    /// This is the legitimate half of what seeded growth was reaching for. Growth
    /// extended a request outward, past anything the host had said, with nothing to
    /// stop it — that is how "lunch and snacks, 12 to 5" reached an 8 pm dinner. A gap
    /// is bounded on *both* sides by something they did say, so filling it can never
    /// run past their own request.
    private static func interludes(between named: [Band], within fits: [Band], pace: Pace) -> [Band] {
        guard named.count > 1 else { return [] }

        let taken = Set(named.map(\.id))
        var filled: [Band] = []

        for (earlier, later) in zip(named, named.dropFirst()) {
            let gapStart = earlier.endMinute
            let gapEnd = later.startMinute
            let wanted = interludeCount(forGapOf: gapEnd - gapStart, pace: pace)
            guard wanted > 0 else { continue }

            /// How much of this gap the band actually covers. Ranking by it means a
            /// gap with room for one stop gets the one that fits it best, rather than
            /// whichever happens to come first in the table.
            func overlap(_ band: Band) -> Int {
                min(band.endMinute, gapEnd) - max(band.startMinute, gapStart)
            }

            let candidates = fits
                .filter { $0.id.role == .interlude && !taken.contains($0.id) && overlap($0) > 0 }
                .sorted { overlap($0) > overlap($1) }

            filled.append(contentsOf: candidates.prefix(wanted))
        }

        return filled.sorted { $0.startMinute < $1.startMinute }
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
