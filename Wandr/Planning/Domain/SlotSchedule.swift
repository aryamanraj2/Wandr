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

/// The slots that fit a time window, in time order, each with its intersected window.
nonisolated struct SlotSchedule: Sendable, Equatable {

    /// One slot that survived the window, with the window it actually occupies.
    nonisolated struct FeasibleSlot: Sendable, Equatable, Identifiable {
        let category: SlotCategory
        /// Human name for the slot, matching the curation deck titles ("Dinner").
        let title: String
        /// Minutes from midnight. `startMinute < endMinute`, always ≥ `minimumStopMinutes` apart.
        let startMinute: Int
        let endMinute: Int

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
        let category: SlotCategory
        let title: String
        let startMinute: Int
        let endMinute: Int
    }

    /// In time order, not `SlotCategory.allCases` order.
    private static let bands: [Band] = [
        Band(category: .sights,    title: "Afternoon",     startMinute: 12 * 60 + 30, endMinute: 17 * 60),      // 12:30 – 5:00 pm
        Band(category: .discover,  title: "Something new",  startMinute: 17 * 60,      endMinute: 20 * 60),      //  5:00 – 8:00 pm
        Band(category: .food,      title: "Dinner",         startMinute: 20 * 60,      endMinute: 22 * 60),      //  8:00 – 10:00 pm
        Band(category: .nightlife, title: "Late",           startMinute: 22 * 60,      endMinute: 25 * 60)       // 10:00 pm – 1:00 am
    ]

    // MARK: - Computation

    /// The slots that fit `window`, each intersected with it.
    ///
    /// A slot is kept iff `[earliestStart ?? bandStart, latestEnd ?? bandEnd]`
    /// overlaps its band by at least `minimumStopMinutes`. An `.unknown` window
    /// keeps every slot at its full band.
    static func compute(
        for window: OutingTimeWindow,
        minimumStopMinutes: Int = 60
    ) -> SlotSchedule {
        let feasible: [FeasibleSlot] = bands.compactMap { band in
            let start = max(band.startMinute, window.earliestStartMinute ?? band.startMinute)
            let end = min(band.endMinute, window.latestEndMinute ?? band.endMinute)
            guard end - start >= minimumStopMinutes else { return nil }
            return FeasibleSlot(category: band.category, title: band.title, startMinute: start, endMinute: end)
        }

        return SlotSchedule(slots: feasible, isWindowConstrained: !window.isUnknown)
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
