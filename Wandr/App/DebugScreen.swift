// DebugScreen.swift Wandr A launch-time door straight onto one screen, for looking at it. The planning pipeline is on-device and does not run in the Simulator, so the surfaces downstream of it — the schedule and the finished itinerary — are otherwise only reachable on a device. That makes them the two screens in the app it is hardest to check a layout change against, which is exactly backwards. Debug builds only; it is compiled out of release entirely, alongside the `WANDR_SEED_SUMMARY` hook in `WandrApp` that it sits beside.

#if DEBUG
import SwiftUI

/// A screen the app can be launched directly into, e.g.
/// `xcrun simctl launch <device> aryaman.Wandr` with `SIMCTL_CHILD_WANDR_SCREEN=schedule-morning`.
enum DebugScreen: String {
    case curation
    case schedule
    /// The case that motivated the hook: a plan that starts before the schedule's old fixed 9am bound.
    case scheduleMorning = "schedule-morning"
    /// A plan running past midnight, the same failure at the other end of the day.
    case scheduleLateClose = "schedule-late-close"
    case summary
    /// One stop only — the layout with the least content to hold it together.
    case summarySingle = "summary-single"

    static var requested: DebugScreen? {
        ProcessInfo.processInfo.environment["WANDR_SCREEN"].flatMap(DebugScreen.init(rawValue:))
    }

    @ViewBuilder
    var view: some View {
        switch self {
        case .curation:          CurationView()
        case .schedule:          ScheduleView()
        case .scheduleMorning:   ScheduleView(stops: Self.morningStops)
        case .scheduleLateClose: ScheduleView(stops: Self.lateCloseStops)
        case .summary:           ItinerarySummaryView(blocks: DemoPlan.blocks(for: DemoPlan.days[0]))
        case .summarySingle:     ItinerarySummaryView(blocks: Self.singleStop)
        }
    }

    private static var day: PlanDay.ID { DemoPlan.days[0].id }

    /// Breakfast onward — the earliest stop sits well before the old fixed lower bound.
    private static var morningStops: [ScheduleBlock] {
        [
            ScheduleBlock(title: "Kunzum Café", category: .food,
                          startMinute: 8 * 60, durationMinutes: 75, dayID: day),
            ScheduleBlock(title: "Lodhi Art District", category: .sights,
                          startMinute: 10 * 60, durationMinutes: 90, dayID: day)
        ]
    }

    /// A close past midnight, which is stored as minutes beyond 24:00.
    private static var lateCloseStops: [ScheduleBlock] {
        [
            ScheduleBlock(title: "Hub Brewworks", category: .nightlife,
                          startMinute: 22 * 60, durationMinutes: 210, dayID: day)
        ]
    }

    private static var singleStop: [ScheduleBlock] {
        [
            ScheduleBlock(title: "Hub Brewworks", category: .nightlife,
                          startMinute: 21 * 60 + 45, durationMinutes: 90, dayID: day)
        ]
    }
}
#endif
