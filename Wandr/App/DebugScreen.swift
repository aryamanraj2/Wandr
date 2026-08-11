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
    /// The planning wait, walking its four real phases on a clock. The pipeline behind it does not
    /// run in the Simulator at all, so this screen is otherwise unreachable there — which made it
    /// the least-checked surface in the app and, not coincidentally, the one that shipped as a bare
    /// spinner. The clock here is a *stand-in for the pipeline*, not a second implementation of it:
    /// nothing outside this `#if DEBUG` file ever advances a stage on a timer.
    case planning
    /// The other wait — on-device extraction, which genuinely has no phases to report.
    case extracting
    /// The capture screen. Reachable through onboarding, but only after a tap that a fresh install
    /// resets — and the Simulator has no microphone, so the wave that is now the whole subject of
    /// the screen can never be driven there anyway.
    case capture
    /// The wave in each of its four states at once. The Simulator cannot open a microphone, so the
    /// only state reachable there is the resting one — which is the state that matters least.
    case wave
    /// The expanded card, behind a long press on the top of a deck. Reachable in the Simulator only
    /// by holding a card, and then only ever with the hand-written demo deck's content.
    case candidate
    /// The same screen with the content a *curated* pick actually carries: a rationale, the
    /// validator's caveats and the provider's surveyed tags, and none of the story, highlights or
    /// insider tip that only the demo deck has. That is what every real pick looks like, and it is
    /// the layout most at risk of falling apart, so it gets its own door.
    case candidateCurated = "candidate-curated"
    /// The generated Phosphor symbols beside their SF Symbols equivalents. Custom symbols are only
    /// worth having if they sit on the same baseline and read at the same optical weight as the
    /// native ones next to them, and that can only be judged by looking.
    case symbols

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
        case .capture:           PlanCaptureView(onCommit: { _ in }, onCancel: { })
        case .wave:              DebugWaveStates()
        case .symbols:           DebugSymbols()
        case .planning:          DebugPlanningWait()
        case .extracting:        WandrThinkingView(title: "Reading\nthat back",
                                                   caption: "Pulling out the details you gave")
        case .summary:           ItinerarySummaryView(blocks: DemoPlan.blocks(for: DemoPlan.days[0]))
        case .summarySingle:     ItinerarySummaryView(blocks: Self.singleStop)
        case .candidate:         CandidateDetailView(candidate: DemoPlan.decks[0].candidates[0],
                                                     onKeep: {}, onPass: {})
        case .candidateCurated:  CandidateDetailView(candidate: Self.curatedCandidate,
                                                     onKeep: {}, onPass: {})
        }
    }

    /// A candidate shaped the way `GroundedPlanMapper` builds one, borrowing a demo venue for its
    /// name and photograph. Everything the evidence layer does not produce is stripped, and
    /// everything it does produce — and the demo deck omits — is supplied.
    static var curatedCandidate: Candidate {
        var candidate = DemoPlan.decks[0].candidates[1]
        candidate.story = nil
        candidate.highlights = []
        candidate.insiderTip = nil
        candidate.rationale = "A lively room that comfortably takes a group this size, and it stays open late enough for the walk over afterwards."
        candidate.warnings = ["Per head runs over the budget this group worked out to."]
        candidate.vibeTags = ["loud", "lively", "group-friendly"]
        candidate.setting = .indoor
        candidate.dietary = ["Vegetarian", "Vegan"]
        candidate.access = nil
        return candidate
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

/// Walks `WandrThinkingView` through the four phases a real run reports, so the dots, the fill, and
/// the caption transition can be watched without a device.
private struct DebugPlanningWait: View {
    private static let legs: [PlanningState] = [.extracting, .researching, .validating, .curating]

    @State private var index = 0

    var body: some View {
        WandrThinkingView(title: "Planning", stage: Self.legs[index])
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2.2))
                    index = (index + 1) % Self.legs.count
                }
            }
    }
}

/// The four wave states side by side, fed synthetic amplitude. The levels here are noise, not a
/// voice — this exists only so the resting, waking, listening and settled looks can be compared on a
/// machine with no microphone.
private struct DebugWaveStates: View {
    @State private var level: Double = 0.4
    @State private var settled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 46) {
            row("resting", .resting) { 0 }
            row("waking", .waking) { 0 }
            row("listening", .listening) { level }
            // `heard` is a *held* buffer, so it only means anything arrived at from `listening`.
            // Shown cold it is an empty row, which is the one thing it is not.
            row(settled ? "heard (held)" : "listening → heard",
                settled ? .heard : .listening) { level }
        }
        .padding(.horizontal, Metrics.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Wandr.pageBackground)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                level = Double.random(in: 0.04...0.95)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                settled.toggle()
            }
        }
    }

    private func row(
        _ name: String,
        _ activity: CaptureActivity,
        level: @escaping () -> Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(name).wandrLabelStyle()
            PlanWave(activity: activity, level: level)
        }
    }
}

/// Each generated symbol against the SF Symbol it replaces, at three text sizes and two weights.
private struct DebugSymbols: View {
    private static let pairs: [(ImageResource, String, String)] = [
        (.wandrShieldCheck, "hand.raised.fill", "shield-check"),
        (.wandrChats, "text.bubble.fill", "chats-circle"),
        (.wandrClipboardText, "doc.on.doc", "clipboard-text")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            ForEach(Array(Self.pairs.enumerated()), id: \.offset) { _, pair in
                VStack(alignment: .leading, spacing: 12) {
                    Text(pair.2).wandrLabelStyle()

                    ForEach([Font.subheadline, .title3, .largeTitle], id: \.self) { font in
                        HStack(spacing: 18) {
                            Image(pair.0)
                            Image(systemName: pair.1)
                            Text("Hxp")
                        }
                        .font(font)
                        .foregroundStyle(Wandr.brand)
                    }
                }
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Wandr.pageBackground)
    }
}

#endif
